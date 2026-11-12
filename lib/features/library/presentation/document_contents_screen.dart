import 'package:flutter/material.dart';

import '../../image_import/services/image_picker_service.dart';
import '../../listening/services/speech_service.dart';
import '../data/document_page.dart';
import '../data/document_store.dart';
import '../data/reading_position.dart';
import '../data/saved_document.dart';
import 'add_page_screen.dart';
import 'saved_document_screen.dart';
import 'document_details_dialog.dart';

/// Shows pages for every category; it does not own a speech engine.
class DocumentContentsScreen extends StatefulWidget {
  const DocumentContentsScreen({
    super.key,
    required this.document,
    this.store,
    this.speechService,
    this.onUpdated,
    this.pickerService = const ImagePickerService(),
  });

  final SavedDocument document;
  final DocumentStore? store;
  final SpeechService? speechService;
  final VoidCallback? onUpdated;
  final ImagePickerService pickerService;

  @override
  State<DocumentContentsScreen> createState() => _DocumentContentsScreenState();
}

class _DocumentContentsScreenState extends State<DocumentContentsScreen> {
  late SavedDocument _document;
  List<DocumentPage> _pages = const [];
  bool _loading = true;
  bool _opening = false;
  bool _deleting = false;
  bool _reordering = false;
  int? _deletingPageId;
  String? _error;
  int _loadId = 0;
  int _positionLoadId = 0;
  ReadingPosition? _readingPosition;

  DocumentStore get _store => widget.store ?? DocumentStore.instance;
  bool get _busy => _loading || _opening || _deleting || _reordering;

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _load();
  }

  Future<void> _load() async {
    final run = ++_loadId;
    _positionLoadId++;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final document = await _store.getDocument(widget.document.id);
      if (!mounted || run != _loadId) return;
      if (document == null) {
        setState(() {
          _loading = false;
          _error = 'İçerik bulunamadı. Kayıtlarım ekranına dönebilirsin.';
        });
        return;
      }
      final pages = await _store.pages(document.id);
      if (!mounted || run != _loadId) return;
      setState(() {
        _document = document;
        _pages = pages;
        _loading = false;
      });
      await _loadReadingPosition();
    } catch (_) {
      if (!mounted || run != _loadId) return;
      setState(() {
        _loading = false;
        _error = 'Sayfalar yüklenemedi. Tekrar deneyebilirsin.';
      });
    }
  }

  Future<void> _loadReadingPosition() async {
    final loadId = ++_positionLoadId;
    try {
      final position = await _store.readingPosition(_document.id);
      if (!mounted || loadId != _positionLoadId) return;
      setState(() {
        _readingPosition =
            position != null &&
                _pages.any(
                  (page) =>
                      page.id == position.pageId &&
                      page.text == position.pageText,
                )
            ? position
            : null;
      });
    } catch (_) {
      if (!mounted || loadId != _positionLoadId) return;
      setState(() => _readingPosition = null);
      _showMessage('Okuma konumu yüklenemedi. Sayfaları açabilirsin.');
    }
  }

  Future<void> _openPage(
    DocumentPage page,
    int number, {
    int? initialSentence,
  }) async {
    if (_busy || _error != null) return;
    setState(() => _opening = true);
    var changed = false;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => SavedDocumentScreen(
            document: SavedDocument(
              id: _document.id,
              title: _document.title,
              category: _document.category,
              text: page.text,
              createdAt: _document.createdAt,
            ),
            pageId: page.id,
            pageNumber: number,
            initialSentence: initialSentence,
            store: _store,
            speechService: widget.speechService,
            onUpdated: () {
              changed = true;
              widget.onUpdated?.call();
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (!mounted) return;
    if (changed) {
      await _load();
    } else {
      await _loadReadingPosition();
    }
  }

  Future<void> _editDetails() async {
    if (_busy || _error != null) return;
    setState(() => _opening = true);
    try {
      final updated = await showDocumentDetailsDialog(
        context: context,
        document: _document,
        store: _store,
      );
      if (!mounted || updated == null) return;
      setState(() => _document = updated);
      widget.onUpdated?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İçerik bilgileri güncellendi.')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _addPage() async {
    if (_busy || _error != null) return;
    setState(() => _opening = true);
    bool? saved;
    try {
      saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => AddPageScreen(
            documentId: _document.id,
            documentTitle: _document.title,
            store: _store,
            speechService: widget.speechService,
            pickerService: widget.pickerService,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (!mounted || saved != true) return;
    widget.onUpdated?.call();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Sayfa eklendi.')));
    await _load();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deletePage(DocumentPage page, int number) async {
    if (_busy || _error != null) return;
    setState(() => _deleting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final colors = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            title: Text('Sayfa $number silinsin mi?'),
            content: const Text(
              'Bu işlem geri alınamaz. İçeriğin diğer sayfaları korunur.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Sil'),
              ),
            ],
          );
        },
      );
      if (!mounted || confirmed != true) return;
      setState(() => _deletingPageId = page.id);
      final deleted = await _store.deletePage(
        documentId: _document.id,
        pageId: page.id,
      );
      if (!mounted) return;
      if (deleted) {
        setState(() {
          _pages = _pages
              .where((item) => item.id != page.id)
              .toList(growable: false);
          if (_readingPosition?.pageId == page.id) _readingPosition = null;
          _document = SavedDocument(
            id: _document.id,
            title: _document.title,
            category: _document.category,
            text: _pages.isEmpty ? '' : _pages.first.text,
            createdAt: _document.createdAt,
          );
        });
        widget.onUpdated?.call();
        _showMessage('Sayfa silindi.');
      } else {
        // Another operation already removed it; reload authoritative data.
        widget.onUpdated?.call();
        await _load();
        if (mounted) _showMessage('Sayfa zaten kaldırılmış. Liste yenilendi.');
      }
    } catch (_) {
      if (mounted) _showMessage('Sayfa silinemedi. Tekrar deneyebilirsin.');
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
          _deletingPageId = null;
        });
      }
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_busy || _error != null) return;
    // onReorderItem already reports newIndex after the item is removed.
    if (oldIndex == newIndex) return;

    final previous = _pages;
    final reordered = [...previous];
    reordered.insert(newIndex, reordered.removeAt(oldIndex));

    setState(() {
      _pages = reordered;
      _reordering = true;
    });

    try {
      await _store.reorderPages(
        documentId: _document.id,
        orderedPageIds: [for (final page in reordered) page.id],
      );
      if (!mounted) return;
      setState(() {
        _document = SavedDocument(
          id: _document.id,
          title: _document.title,
          category: _document.category,
          text: reordered.first.text,
          createdAt: _document.createdAt,
        );
      });
      widget.onUpdated?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() => _pages = previous);
      _showMessage('Sayfa sırası kaydedilemedi. Önceki sıra geri yüklendi.');
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  Widget _dragHandle(int index, int number) {
    return ReorderableDragStartListener(
      key: ValueKey('page-handle-$number'),
      index: index,
      enabled: !_busy,
      child: Semantics(
        label: 'Sayfa $number sırasını değiştir',
        hint: 'Sürüklemek için basılı tutup taşı',
        excludeSemantics: true,
        child: const Tooltip(
          message: 'Sırayı değiştirmek için sürükle',
          excludeFromSemantics: true,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.drag_handle),
          ),
        ),
      ),
    );
  }

  Widget _pageMenu(BuildContext context, DocumentPage page, int number) {
    final errorColor = Theme.of(context).colorScheme.error;
    if (_deletingPageId == page.id) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: 'Sayfa siliniyor',
            ),
          ),
        ),
      );
    }
    return PopupMenuButton<String>(
      key: ValueKey('page-menu-${page.id}'),
      tooltip: 'Sayfa $number seçenekleri',
      enabled: !_busy,
      onSelected: (_) => _deletePage(page, number),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 12),
              Text('Sil', style: TextStyle(color: errorColor)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _deletingPageId == null && !_reordering,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_document.title),
          actions: [
            if (MediaQuery.sizeOf(context).width < 400 &&
                MediaQuery.textScalerOf(context).scale(14) > 20)
              IconButton(
                key: const ValueKey('add-page'),
                tooltip: 'Sayfa ekle',
                onPressed: _busy || _error != null ? null : _addPage,
                icon: const Icon(Icons.add),
              )
            else
              TextButton.icon(
                key: const ValueKey('add-page'),
                onPressed: _busy || _error != null ? null : _addPage,
                icon: const Icon(Icons.add),
                label: const Text('Sayfa ekle'),
              ),
            PopupMenuButton<String>(
              key: const ValueKey('content-options'),
              tooltip: 'İçerik seçenekleri',
              enabled: !_busy && _error == null,
              onSelected: (_) => _editDetails(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Düzenle')),
              ],
            ),
          ],
        ),
        body: SafeArea(child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      );
    }
    final canReorder = _pages.length >= 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('${_document.category.label} · ${_pages.length} sayfa'),
        ),
        if (_readingPosition != null &&
            _pages.any((page) => page.id == _readingPosition!.pageId))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        final index = _pages.indexWhere(
                          (page) => page.id == _readingPosition!.pageId,
                        );
                        _openPage(
                          _pages[index],
                          index + 1,
                          initialSentence: _readingPosition!.sentenceIndex,
                        );
                      },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Kaldığın yerden devam et'),
              ),
            ),
          ),
        if (canReorder)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text.rich(
              key: const ValueKey('page-reorder-hint'),
              TextSpan(
                children: [
                  const TextSpan(text: 'Sıralamak için sağdaki tutamacı ('),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: ExcludeSemantics(
                      child: Icon(
                        Icons.drag_handle,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const TextSpan(text: ') sürükle.'),
                ],
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_reordering)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(semanticsLabel: 'Sıra kaydediliyor'),
                SizedBox(height: 4),
                Text('Sıra kaydediliyor…'),
              ],
            ),
          ),
        Expanded(
          child: _pages.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Henüz sayfa yok. “Sayfa ekle” ile başlayabilirsin.',
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: _pages.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    final number = index + 1;
                    return Column(
                      key: ValueKey('page-${page.id}'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.article_outlined),
                          title: Text('Sayfa $number'),
                          subtitle: Text(
                            page.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _pageMenu(context, page, number),
                              if (canReorder) _dragHandle(index, number),
                            ],
                          ),
                          onTap: _busy ? null : () => _openPage(page, number),
                        ),
                        const Divider(height: 1),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

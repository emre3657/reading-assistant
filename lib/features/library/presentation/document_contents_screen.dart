import 'package:material_ui/material_ui.dart';

import '../../guide/guide_host.dart';
import '../../guide/guide_manager.dart';

import '../../image_import/services/image_picker_service.dart';
import '../../image_import/presentation/image_import_controller.dart';
import '../../image_import/services/image_rotation_service.dart';
import '../../image_import/services/text_recognition_service.dart';
import '../../listening/services/speech_service.dart';
import '../../listening/presentation/reading_preferences.dart';
import '../data/document_page.dart';
import '../data/document_store.dart';
import '../data/reading_position.dart';
import '../data/saved_document.dart';
import 'add_page_screen.dart';
import 'saved_document_screen.dart';
import 'document_details_dialog.dart';
import 'selection_app_bar.dart';

/// Shows pages for every category; it does not own a speech engine.
class DocumentContentsScreen extends StatefulWidget {
  const DocumentContentsScreen({
    super.key,
    required this.document,
    this.store,
    this.speechService,
    this.onUpdated,
    this.pickerService = const ImagePickerService(),
    this.textRecognitionService = const TextRecognitionService(),
    this.rotationService = const ImageRotationService(),
    this.previewImageBuilder = fileImageProvider,
  });

  final SavedDocument document;
  final DocumentStore? store;
  final SpeechService? speechService;
  final VoidCallback? onUpdated;
  final ImagePickerService pickerService;
  final TextRecognitionService textRecognitionService;
  final ImageRotationService rotationService;
  final PreviewImageBuilder previewImageBuilder;

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
  ReadingPosition? _bookmark;
  bool _selecting = false;
  final Set<int> _selectedPageIds = {};
  final _guideResume = GlobalKey();

  DocumentStore get _store =>
      widget.store ??
      context
          .getInheritedWidgetOfExactType<ReadingPreferencesScope>()
          ?.preferences
          .store ??
      DocumentStore.instance;
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
    try {
      final bookmark = await _store.bookmark(_document.id);
      if (!mounted || loadId != _positionLoadId) return;
      setState(() {
        _bookmark =
            bookmark != null &&
                _pages.any(
                  (page) =>
                      page.id == bookmark.pageId &&
                      page.text == bookmark.pageText,
                )
            ? bookmark
            : null;
      });
    } catch (_) {
      if (!mounted || loadId != _positionLoadId) return;
      setState(() => _bookmark = null);
      _showMessage('Ayraç yüklenemedi. Sayfaları açabilirsin.');
    }
  }

  Future<void> _openPage(
    DocumentPage page,
    int number, {
    int? initialSentence,
    bool revealInitialSentence = false,
  }) async {
    if (_busy || _error != null) return;
    setState(() => _opening = true);
    var changed = false;
    final preferences = ReadingPreferencesScope.maybeOf(context);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) {
            final screen = SavedDocumentScreen(
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
              revealInitialSentence: revealInitialSentence,
              store: _store,
              speechService: widget.speechService,
              onUpdated: () {
                changed = true;
                widget.onUpdated?.call();
              },
            );
            return preferences == null
                ? screen
                : ReadingPreferencesScope(
                    preferences: preferences,
                    child: screen,
                  );
          },
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
    int? savedCount;
    final preferences = ReadingPreferencesScope.maybeOf(context);
    try {
      savedCount = await Navigator.of(context).push<int>(
        MaterialPageRoute(
          builder: (context) {
            final screen = AddPageScreen(
              documentId: _document.id,
              documentTitle: _document.title,
              store: _store,
              speechService: widget.speechService,
              pickerService: widget.pickerService,
              textRecognitionService: widget.textRecognitionService,
              rotationService: widget.rotationService,
              previewImageBuilder: widget.previewImageBuilder,
            );
            return preferences == null
                ? screen
                : ReadingPreferencesScope(
                    preferences: preferences,
                    child: screen,
                  );
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (!mounted || savedCount == null) return;
    widget.onUpdated?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          savedCount == 1 ? 'Sayfa eklendi.' : '$savedCount sayfa eklendi.',
        ),
      ),
    );
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
          if (_bookmark?.pageId == page.id) _bookmark = null;
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

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedPageIds.clear();
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (!_selectedPageIds.add(id)) _selectedPageIds.remove(id);
    });
  }

  Future<void> _deleteSelected() async {
    if (_busy || _error != null || _selectedPageIds.isEmpty) return;
    final ids = Set<int>.of(_selectedPageIds);
    setState(() => _deleting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(
            ids.length == 1
                ? 'Sayfa silinsin mi?'
                : '${ids.length} sayfa silinsin mi?',
          ),
          content: Text(
            ids.length == 1
                ? 'Seçili sayfa silinecek. Bu işlem geri alınamaz.'
                : 'Seçili sayfalar silinecek. Bu işlem geri alınamaz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sil'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final count = await _store.deletePages(
        documentId: _document.id,
        pageIds: ids,
      );
      if (!mounted) return;
      _exitSelection();
      widget.onUpdated?.call();
      await _load();
      if (mounted) {
        _showMessage(count == 1 ? 'Sayfa silindi.' : '$count sayfa silindi.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Sayfalar silinemedi. Seçim korundu, tekrar deneyebilirsin.',
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_busy || _selecting || _error != null) return;
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
    return GuideHost(
      offers: [
        GuideOffer(
          group: GuideGroup.resume,
          enabled:
              !_busy &&
              !_selecting &&
              _error == null &&
              _readingPosition != null,
          steps: [GuideStep(_guideResume, 'Son okuduğun konuma dönebilirsin.')],
        ),
      ],
      child: PopScope(
        canPop: !_selecting && _deletingPageId == null && !_reordering,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _selecting && !_busy) _exitSelection();
        },
        child: Scaffold(
          appBar: _selecting
              ? selectionAppBar(
                  count: _selectedPageIds.length,
                  busy: _busy,
                  onClose: _exitSelection,
                  onSelectAll: () => setState(() {
                    _selectedPageIds.addAll(_pages.map((page) => page.id));
                  }),
                  onDelete: _deleteSelected,
                )
              : AppBar(
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
    final canReorder = _pages.length >= 2 && !_selecting;
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: _pages.length,
      onReorderItem: _reorder,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('${_document.category.label} · ${_pages.length} sayfa'),
          ),
          if (_readingPosition != null || _bookmark != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_readingPosition case final position?)
                      ListTile(
                        key: _guideResume,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: const Icon(Icons.play_arrow),
                        title: const Text('Kaldığın yerden devam et'),
                        subtitle: Text(
                          'Son okuduğun yer · Sayfa '
                          '${_pages.indexWhere((page) => page.id == position.pageId) + 1}',
                        ),
                        enabled: !_busy && !_selecting,
                        onTap: _busy || _selecting
                            ? null
                            : () {
                                final index = _pages.indexWhere(
                                  (page) => page.id == position.pageId,
                                );
                                if (index >= 0) {
                                  _openPage(
                                    _pages[index],
                                    index + 1,
                                    initialSentence: position.sentenceIndex,
                                  );
                                }
                              },
                      ),
                    if (_readingPosition != null && _bookmark != null)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    if (_bookmark case final bookmark?)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: const Icon(Icons.bookmark_outline),
                        title: const Text('Ayraca git'),
                        subtitle: Text(
                          'İşaretlediğin yer · Sayfa '
                          '${_pages.indexWhere((page) => page.id == bookmark.pageId) + 1}',
                        ),
                        enabled: !_busy && !_selecting,
                        onTap: _busy || _selecting
                            ? null
                            : () {
                                final index = _pages.indexWhere(
                                  (page) => page.id == bookmark.pageId,
                                );
                                if (index >= 0) {
                                  _openPage(
                                    _pages[index],
                                    index + 1,
                                    initialSentence: bookmark.sentenceIndex,
                                    revealInitialSentence: true,
                                  );
                                }
                              },
                      ),
                    if (_readingPosition != null &&
                        _bookmark != null &&
                        _readingPosition!.pageId == _bookmark!.pageId &&
                        _readingPosition!.sentenceIndex ==
                            _bookmark!.sentenceIndex &&
                        _readingPosition!.pageText == _bookmark!.pageText)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Text(
                          'Ayraç ve son okuma konumun aynı yerde.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Semantics(
              header: true,
              child: Text(
                'Sayfalar',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          if (canReorder)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
          if (_pages.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Henüz sayfa yok. “Sayfa ekle” ile başlayabilirsin.',
                ),
              ),
            ),
        ],
      ),
      itemBuilder: (context, index) {
        final page = _pages[index];
        final number = index + 1;
        return Column(
          key: ValueKey('page-${page.id}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: _selecting
                  ? Semantics(
                      label: 'Sayfa $number seçimi',
                      child: Checkbox(
                        value: _selectedPageIds.contains(page.id),
                        onChanged: _busy
                            ? null
                            : (_) => _toggleSelection(page.id),
                      ),
                    )
                  : const Icon(Icons.article_outlined),
              title: Text('Sayfa $number'),
              subtitle: Text(
                page.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _selecting
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _pageMenu(context, page, number),
                        if (canReorder) _dragHandle(index, number),
                      ],
                    ),
              onTap: _busy
                  ? null
                  : () => _selecting
                        ? _toggleSelection(page.id)
                        : _openPage(page, number),
              onLongPress: _busy || _selecting
                  ? null
                  : () {
                      setState(() {
                        _selecting = true;
                        _selectedPageIds.add(page.id);
                      });
                    },
            ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../../listening/services/speech_service.dart';
import '../data/document_page.dart';
import '../data/document_store.dart';
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
  });

  final SavedDocument document;
  final DocumentStore? store;
  final SpeechService? speechService;
  final VoidCallback? onUpdated;

  @override
  State<DocumentContentsScreen> createState() => _DocumentContentsScreenState();
}

class _DocumentContentsScreenState extends State<DocumentContentsScreen> {
  late SavedDocument _document;
  List<DocumentPage> _pages = const [];
  bool _loading = true;
  bool _opening = false;
  String? _error;
  int _loadId = 0;

  DocumentStore get _store => widget.store ?? DocumentStore.instance;
  bool get _busy => _loading || _opening;

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _load();
  }

  Future<void> _load() async {
    final run = ++_loadId;
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
    } catch (_) {
      if (!mounted || run != _loadId) return;
      setState(() {
        _loading = false;
        _error = 'Sayfalar yüklenemedi. Tekrar deneyebilirsin.';
      });
    }
  }

  Future<void> _openPage(DocumentPage page, int number) async {
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
    if (mounted && changed) await _load();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_document.title),
        actions: [
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('${_document.category.label} · ${_pages.length} sayfa'),
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
              : ListView.separated(
                  itemCount: _pages.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return ListTile(
                      key: ValueKey('page-${page.id}'),
                      leading: const Icon(Icons.article_outlined),
                      title: Text('Sayfa ${index + 1}'),
                      subtitle: Text(
                        page.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy ? null : () => _openPage(page, index + 1),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

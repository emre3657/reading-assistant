import 'package:flutter/material.dart';

import '../../listening/services/speech_service.dart';
import '../data/document_store.dart';
import '../data/saved_document.dart';
import 'document_contents_screen.dart';

enum _DocumentAction { delete }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.store, this.speechService});

  final DocumentStore? store;

  /// An injected service remains owned by its caller.
  final SpeechService? speechService;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late Future<List<SavedDocument>> _documents;
  bool _opening = false;
  bool _deleting = false;
  int? _deletingId;

  DocumentStore get _store => widget.store ?? DocumentStore.instance;
  bool get _busy => _opening || _deleting;

  @override
  void initState() {
    super.initState();
    _documents = _store.list();
  }

  void _reload() {
    setState(() {
      _documents = _store.list();
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(SavedDocument document) async {
    if (_busy) return;
    setState(() => _opening = true);
    var changed = false;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => DocumentContentsScreen(
            document: document,
            store: _store,
            speechService: widget.speechService,
            onUpdated: () => changed = true,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (mounted && changed) _reload();
  }

  Future<void> _deleteDocument(SavedDocument document) async {
    if (_busy) return;
    setState(() => _deleting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final colors = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            title: const Text('Kayıt silinsin mi?'),
            content: Text(
              '“${document.title}” silinecek.\n\nBu işlem geri alınamaz.',
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
      setState(() => _deletingId = document.id);
      final deleted = await _store.delete(document.id);
      if (!mounted) return;
      _reload();
      _showMessage(
        deleted
            ? 'Kayıt silindi.'
            : 'Kayıt zaten kaldırılmış. Liste yenilendi.',
      );
    } catch (_) {
      if (mounted) _showMessage('Kayıt silinemedi. Tekrar deneyebilirsin.');
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
          _deletingId = null;
        });
      }
    }
  }

  Widget _buildDocumentMenu(SavedDocument document) {
    if (_deletingId == document.id) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: 'Kayıt siliniyor',
            ),
          ),
        ),
      );
    }
    return PopupMenuButton<_DocumentAction>(
      key: ValueKey('document-menu-${document.id}'),
      tooltip: 'Kayıt seçenekleri',
      enabled: !_busy,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case _DocumentAction.delete:
            _deleteDocument(document);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _DocumentAction.delete,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 12),
              const Text('Sil'),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kayıtlarım'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<SavedDocument>>(
          future: _documents,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Kayıtlar yüklenemedi.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _reload,
                        child: const Text('Tekrar dene'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final documents = snapshot.data ?? const <SavedDocument>[];
            if (documents.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Henüz kayıt yok. Çıkardığın metni kaydederek başlayabilirsin.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.separated(
              itemCount: documents.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final document = documents[index];
                return ListTile(
                  key: ValueKey('document-${document.id}'),
                  leading: const Icon(Icons.description_outlined),
                  title: Text(document.title),
                  subtitle: Text(document.category.label),
                  trailing: _buildDocumentMenu(document),
                  onTap: _busy ? null : () => _open(document),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../listening/services/speech_service.dart';
import '../data/document_store.dart';
import '../data/saved_document.dart';
import 'saved_document_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.store, this.speechService});

  final DocumentStore? store;

  /// An injected service remains owned by its caller. Only the top reading
  /// screen may use it; navigation back awaits the saved screen's stop.
  final SpeechService? speechService;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late Future<List<SavedDocument>> _documents;
  bool _opening = false;

  DocumentStore get _store => widget.store ?? DocumentStore.instance;

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

  Future<void> _open(SavedDocument document) async {
    if (_opening) return;
    _opening = true;
    var changed = false;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => SavedDocumentScreen(
            document: document,
            store: _store,
            speechService: widget.speechService,
            onUpdated: () => changed = true,
          ),
        ),
      );
    } finally {
      _opening = false;
    }
    if (mounted && changed) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kayıtlarım'),
        actions: [
          IconButton(
            onPressed: _reload,
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
                        onPressed: _reload,
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
                  leading: const Icon(Icons.description_outlined),
                  title: Text(document.title),
                  subtitle: Text(document.category.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(document),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../data/document_store.dart';
import '../data/saved_document.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late Future<List<SavedDocument>> _documents;

  @override
  void initState() {
    super.initState();
    _documents = DocumentStore.instance.list();
  }

  void _reload() {
    setState(() {
      _documents = DocumentStore.instance.list();
    });
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
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (context) =>
                            SavedDocumentScreen(document: document),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class SavedDocumentScreen extends StatelessWidget {
  const SavedDocumentScreen({super.key, required this.document});

  final SavedDocument document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                document.category.label,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 16),
              SelectableText(
                document.text,
                textAlign: document.category == DocumentCategory.book
                    ? TextAlign.justify
                    : TextAlign.start,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

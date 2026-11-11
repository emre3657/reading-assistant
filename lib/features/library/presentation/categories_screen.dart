import 'package:flutter/material.dart';

import '../data/document_store.dart';
import '../data/saved_document.dart';
import 'category_editor.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, required this.store});

  final DocumentStore store;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late Future<List<DocumentCategory>> _categories;
  bool _editing = false;
  bool _changed = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _categories = widget.store.categories();
  }

  void _reload() {
    setState(() {
      _categories = widget.store.categories();
    });
  }

  Future<void> _edit([DocumentCategory? category]) async {
    if (_editing) return;
    setState(() => _editing = true);
    try {
      final result = await showCategoryEditor(
        context,
        store: widget.store,
        category: category,
      );
      if (!mounted || result == null) return;
      _changed = true;
      _reload();
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _close() async {
    if (_editing || _allowPop) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(_changed);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Kategorileri yönet')),
      body: SafeArea(
        child: FutureBuilder<List<DocumentCategory>>(
          future: _categories,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Kategoriler yüklenemedi.'),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Tekrar dene'),
                    ),
                  ],
                ),
              );
            }
            final categories = snapshot.requireData;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FilledButton.icon(
                  onPressed: _editing ? null : () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Yeni kategori oluştur'),
                ),
                for (final category in categories)
                  ListTile(
                    title: Text(category.label),
                    trailing: IconButton(
                      tooltip:
                          '${category.label} kategorisini yeniden adlandır',
                      onPressed: _editing ? null : () => _edit(category),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

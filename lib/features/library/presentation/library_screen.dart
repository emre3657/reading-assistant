import 'package:flutter/material.dart';

import '../../listening/services/speech_service.dart';
import '../data/document_store.dart';
import '../data/saved_document.dart';
import '../data/turkish_text.dart';
import 'document_contents_screen.dart';
import 'document_details_dialog.dart';
import 'categories_screen.dart';

enum _DocumentAction { edit, delete }

enum _DateOrder { newest, oldest }

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
  final _searchController = TextEditingController();
  bool _opening = false;
  bool _deleting = false;
  int? _deletingId;
  final Set<String> _selectedCategories = {};
  _DateOrder _dateOrder = _DateOrder.newest;
  bool _loadingCategories = false;
  int _loadRevision = 0;

  DocumentStore get _store => widget.store ?? DocumentStore.instance;
  bool get _busy => _opening || _deleting || _loadingCategories;

  @override
  void initState() {
    super.initState();
    _documents = _store.list();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _documents = _loadDocuments(++_loadRevision);
    });
  }

  Future<List<SavedDocument>> _loadDocuments(int revision) async {
    final documents = await _store.list();
    if (_selectedCategories.isNotEmpty) {
      try {
        final categories = await _store.categories();
        if (mounted && revision == _loadRevision) {
          setState(() {
            _selectedCategories.retainAll(
              categories.map((c) => c.name).toSet(),
            );
          });
        }
      } catch (_) {
        if (mounted && revision == _loadRevision) {
          _showMessage('Kategoriler yenilenemedi. Tekrar deneyebilirsin.');
        }
      }
    }
    return documents;
  }

  Future<void> _openCategoryFilter() async {
    if (_busy) return;
    setState(() => _loadingCategories = true);
    final List<DocumentCategory> categories;
    try {
      categories = await _store.categories();
    } catch (_) {
      if (mounted) {
        setState(() => _loadingCategories = false);
        _showMessage('Kategoriler yüklenemedi. Tekrar deneyebilirsin.');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _loadingCategories = false;
      _selectedCategories.retainAll(categories.map((c) => c.name).toSet());
    });
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, updatePanel) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.75,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Kategori',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        TextButton(
                          onPressed: _selectedCategories.isEmpty
                              ? null
                              : () {
                                  setState(_selectedCategories.clear);
                                  updatePanel(() {});
                                },
                          child: const Text('Temizle'),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedCategories.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Tüm kategoriler'),
                    ),
                  for (final category in categories)
                    CheckboxListTile(
                      key: ValueKey('category-filter-${category.name}'),
                      title: Text(category.label),
                      value: _selectedCategories.contains(category.name),
                      onChanged: (selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedCategories.add(category.name);
                          } else {
                            _selectedCategories.remove(category.name);
                          }
                        });
                        updatePanel(() {});
                      },
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Kapat'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _manageCategories() async {
    if (_busy) return;
    setState(() => _opening = true);
    try {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => CategoriesScreen(store: _store)),
      );
      if (mounted && changed == true) _reload();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
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

  Future<void> _editDetails(SavedDocument document) async {
    if (_busy) return;
    setState(() => _opening = true);
    try {
      final updated = await showDocumentDetailsDialog(
        context: context,
        document: document,
        store: _store,
      );
      if (!mounted || updated == null) return;
      _reload();
      _showMessage('İçerik bilgileri güncellendi.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
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
          case _DocumentAction.edit:
            _editDetails(document);
          case _DocumentAction.delete:
            _deleteDocument(document);
        }
      },
      itemBuilder: (context) {
        final errorColor = Theme.of(context).colorScheme.error;
        return [
          const PopupMenuItem(
            value: _DocumentAction.edit,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_outlined),
                SizedBox(width: 12),
                Text('Düzenle'),
              ],
            ),
          ),
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
                Text('Sil', style: TextStyle(color: errorColor)),
              ],
            ),
          ),
        ];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kayıtlarım'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Kayıtlarım menüsü',
            enabled: !_busy,
            onSelected: (_) => _manageCategories(),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'categories',
                child: Row(
                  children: [
                    Icon(Icons.category_outlined, size: 20),
                    SizedBox(width: 12),
                    Expanded(child: Text('Kategorileri yönet')),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: _busy ? null : _reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const ValueKey('title-search'),
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Başlık ara',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Aramayı temizle',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 5),
              child: Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('category-filter-button'),
                    onPressed: _busy ? null : _openCategoryFilter,
                    icon: Semantics(
                      label: _selectedCategories.isEmpty
                          ? null
                          : '${_selectedCategories.length} kategori seçili',
                      child: ExcludeSemantics(
                        child: Badge(
                          isLabelVisible: _selectedCategories.isNotEmpty,
                          label: Text('${_selectedCategories.length}'),
                          child: const Icon(Icons.filter_list),
                        ),
                      ),
                    ),
                    label: const Text('Kategori'),
                  ),
                  DropdownButton<_DateOrder>(
                    key: const ValueKey('date-order'),
                    value: _dateOrder,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                        value: _DateOrder.newest,
                        child: Text('En yeni'),
                      ),
                      DropdownMenuItem(
                        value: _DateOrder.oldest,
                        child: Text('En eski'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _dateOrder = value);
                    },
                  ),
                ],
              ),
            ),
            Expanded(child: _buildDocumentList()),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentList() {
    return FutureBuilder<List<SavedDocument>>(
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
        final query = normalizeTurkishCase(_searchController.text.trim());
        final filtered =
            documents.where((document) {
              return (_selectedCategories.isEmpty ||
                      _selectedCategories.contains(document.category.name)) &&
                  normalizeTurkishCase(document.title).contains(query);
            }).toList()..sort((a, b) {
              final date = a.createdAt.compareTo(b.createdAt);
              final comparison = date != 0 ? date : a.id.compareTo(b.id);
              return _dateOrder == _DateOrder.newest ? -comparison : comparison;
            });
        if (filtered.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aramana veya filtrelerine uygun kayıt bulunamadı.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: filtered.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final document = filtered[index];
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
    );
  }
}

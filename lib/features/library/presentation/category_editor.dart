import 'package:flutter/material.dart';

import '../data/document_store.dart';
import '../data/saved_document.dart';

Future<DocumentCategory?> showCategoryEditor(
  BuildContext context, {
  required DocumentStore store,
  DocumentCategory? category,
}) => showDialog<DocumentCategory>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _CategoryEditor(store: store, category: category),
);

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({required this.store, this.category});

  final DocumentStore store;
  final DocumentCategory? category;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final TextEditingController _name;
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.label);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final category = widget.category;
      final result = category == null
          ? await widget.store.createCategory(_name.text)
          : await widget.store.renameCategory(category, _name.text);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on DuplicateCategoryException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Bu adla bir kategori zaten var.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Kategori kaydedilemedi. Tekrar deneyebilirsin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(
        widget.category == null
            ? 'Yeni kategori oluştur'
            : 'Kategoriyi yeniden adlandır',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('category-name'),
                controller: _name,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Kategori adı'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Bir kategori adı yaz.'
                    : null,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              if (_saving) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Kaydet'),
        ),
      ],
    ),
  );
}

class CategoryPicker extends StatefulWidget {
  const CategoryPicker({
    super.key,
    required this.store,
    required this.value,
    required this.onChanged,
    required this.onReady,
    required this.enabled,
    this.selectFirstIfMissing = false,
  });

  final DocumentStore store;
  final DocumentCategory value;
  final ValueChanged<DocumentCategory> onChanged;
  final ValueChanged<bool> onReady;
  final bool enabled;
  final bool selectFirstIfMissing;

  @override
  State<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<CategoryPicker> {
  static const _create = DocumentCategory(
    '__create__',
    'Yeni kategori oluştur',
  );
  List<DocumentCategory>? _categories;
  bool _loading = true;
  bool _failed = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final categories = await widget.store.categories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _loading = false;
      });
      if (widget.selectFirstIfMissing &&
          !categories.contains(widget.value) &&
          categories.isNotEmpty) {
        widget.onChanged(categories.first);
      }
      widget.onReady(
        categories.contains(widget.value) ||
            (widget.selectFirstIfMissing && categories.isNotEmpty),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _select(DocumentCategory? value) async {
    if (value == null) return;
    if (value != _create) {
      widget.onChanged(value);
      return;
    }
    final created = await showCategoryEditor(context, store: widget.store);
    if (!mounted) return;
    if (created == null) {
      setState(() => _revision++);
      return;
    }
    setState(() => _categories = [..._categories!, created]);
    widget.onChanged(created);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LinearProgressIndicator(
        semanticsLabel: 'Kategoriler yükleniyor',
      );
    }
    if (_failed) {
      return Column(
        children: [
          const Text('Kategoriler yüklenemedi.'),
          TextButton(onPressed: _load, child: const Text('Tekrar dene')),
        ],
      );
    }
    final categories = _categories!;
    if (!categories.contains(widget.value)) {
      return const Text('Seçili kategori bulunamadı.');
    }
    return DropdownButtonFormField<DocumentCategory>(
      key: ValueKey('category-picker-${widget.value.name}-$_revision'),
      initialValue: widget.value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Kategori',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final category in categories)
          DropdownMenuItem(value: category, child: Text(category.label)),
        const DropdownMenuItem(
          value: _create,
          child: Text('Yeni kategori oluştur'),
        ),
      ],
      onChanged: widget.enabled ? _select : null,
    );
  }
}

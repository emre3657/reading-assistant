import 'package:flutter/material.dart';

import '../data/document_store.dart';
import '../data/saved_document.dart';

class DeleteCategoryDialog extends StatefulWidget {
  const DeleteCategoryDialog({
    super.key,
    required this.store,
    required this.category,
  });

  final DocumentStore store;
  final DocumentCategory category;

  @override
  State<DeleteCategoryDialog> createState() => _DeleteCategoryDialogState();
}

class _DeleteCategoryDialogState extends State<DeleteCategoryDialog> {
  List<DocumentCategory> _others = [];
  DocumentCategory? _target;
  int? _count;
  bool _loading = true;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? message}) async {
    setState(() {
      _loading = true;
      _error = message;
    });
    try {
      final categories = await widget.store.categories();
      final count = await widget.store.categoryDocumentCount(widget.category);
      if (!mounted) return;
      final exists = categories.contains(widget.category);
      final others = categories.where((c) => c != widget.category).toList();
      setState(() {
        _others = others;
        if (!others.contains(_target)) _target = null;
        _count = exists ? count : null;
        _loading = false;
        if (!exists) _error = 'Bu kategori artık bulunmuyor.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _count = null;
        _error = 'Kategori bilgileri yüklenemedi. Tekrar deneyebilirsin.';
      });
    }
  }

  Future<void> _delete() async {
    if (_loading || _deleting || _count == null || _others.isEmpty) return;
    if (_count! > 0 && _target == null) {
      setState(() => _error = 'Kayıtlar için bir hedef kategori seç.');
      return;
    }
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.store.deleteCategory(widget.category, target: _target);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      final message = switch (error) {
        CategoryDeletionException(
          problem: CategoryDeletionProblem.lastCategory,
        ) =>
          'Son kalan kategori silinemez.',
        CategoryDeletionException(
          problem: CategoryDeletionProblem.missingCategory,
        ) =>
          'Bu kategori artık bulunmuyor.',
        CategoryDeletionException(
          problem: CategoryDeletionProblem.invalidTarget,
        ) =>
          'Kayıtlar değişti veya hedef kategori artık geçerli değil. Tekrar seç.',
        _ => 'Kategori silinemedi. Kayıtlar korundu, tekrar deneyebilirsin.',
      };
      await _load(message: message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return PopScope(
      canPop: !_deleting,
      child: AlertDialog(
        title: const Text('Kategori silinsin mi?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading)
                const LinearProgressIndicator(
                  semanticsLabel: 'Kategori bilgileri yükleniyor',
                )
              else if (count != null) ...[
                if (_others.isEmpty)
                  const Text(
                    'Son kalan kategori silinemez. En az bir kategori bulunmalıdır.',
                  )
                else if (count == 0)
                  Text('“${widget.category.label}” kategorisi silinecek.'),
                if (_others.isNotEmpty && count > 0) ...[
                  Text(
                    '“${widget.category.label}” kategorisinde $count kayıt var. '
                    'Kayıtlar seçtiğin kategoriye taşınacak; içerikler silinmeyecek.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<DocumentCategory>(
                    key: ValueKey('category-delete-target-${_target?.name}'),
                    initialValue: _target,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Hedef kategori',
                    ),
                    items: [
                      for (final category in _others)
                        DropdownMenuItem(
                          value: category,
                          child: Text(
                            category.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _deleting
                        ? null
                        : (value) => setState(() {
                            _target = value;
                            _error = null;
                          }),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                if (count == null)
                  TextButton(
                    onPressed: _loading || _deleting ? null : () => _load(),
                    child: const Text('Tekrar dene'),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _deleting ? null : () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('confirm-category-delete'),
            onPressed: _loading || _deleting || count == null || _others.isEmpty
                ? null
                : _delete,
            child: Text(_deleting ? 'Siliniyor…' : 'Sil'),
          ),
        ],
      ),
    );
  }
}

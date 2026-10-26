import 'package:flutter/material.dart';

import '../data/document_store.dart';
import '../data/saved_document.dart';

class SaveDocumentDialog extends StatefulWidget {
  const SaveDocumentDialog({super.key, required this.text});

  final String text;

  @override
  State<SaveDocumentDialog> createState() => _SaveDocumentDialogState();
}

class _SaveDocumentDialogState extends State<SaveDocumentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();

  DocumentCategory _category = DocumentCategory.note;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await DocumentStore.instance.save(
        title: _titleController.text,
        category: _category,
        text: widget.text,
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = 'Metin kaydedilemedi. Tekrar deneyebilirsin.';
      });
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Metni kaydet'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleController,
                  enabled: !_saving,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Başlık',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Bir başlık yaz.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<DocumentCategory>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kategori',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final category in DocumentCategory.values)
                      DropdownMenuItem(
                        value: category,
                        child: Text(category.label),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _category = value);
                          }
                        },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                if (_saving) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(semanticsLabel: 'Kaydediliyor'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
          ),
        ],
      ),
    );
  }
}

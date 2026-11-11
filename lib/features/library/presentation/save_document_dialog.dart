import 'package:flutter/material.dart';

import '../data/document_store.dart';
import '../data/saved_document.dart';
import 'category_editor.dart';

class SaveDocumentDialog extends StatefulWidget {
  const SaveDocumentDialog({super.key, required this.text, this.store});

  final String text;
  final DocumentStore? store;

  @override
  State<SaveDocumentDialog> createState() => _SaveDocumentDialogState();
}

class _SaveDocumentDialogState extends State<SaveDocumentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();

  DocumentCategory _category = DocumentCategory.note;
  bool _saving = false;
  bool _categoriesReady = false;
  String? _error;
  DocumentStore get _store => widget.store ?? DocumentStore.instance;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_categoriesReady || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _store.save(
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
                CategoryPicker(
                  store: _store,
                  value: _category,
                  enabled: !_saving,
                  onReady: (ready) => setState(() => _categoriesReady = ready),
                  onChanged: (value) => setState(() => _category = value),
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
            onPressed: _saving || !_categoriesReady ? null : _save,
            child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../data/document_store.dart';
import '../data/saved_document.dart';

Future<SavedDocument?> showDocumentDetailsDialog({
  required BuildContext context,
  required SavedDocument document,
  required DocumentStore store,
}) {
  return showDialog<SavedDocument>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DocumentDetailsDialog(document: document, store: store),
  );
}

class _DocumentDetailsDialog extends StatefulWidget {
  const _DocumentDetailsDialog({required this.document, required this.store});

  final SavedDocument document;
  final DocumentStore store;

  @override
  State<_DocumentDetailsDialog> createState() => _DocumentDetailsDialogState();
}

class _DocumentDetailsDialogState extends State<_DocumentDetailsDialog> {
  late final TextEditingController _title;
  late DocumentCategory _category;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _closing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.document.title);
    _category = widget.document.category;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _closing) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final title = _title.text.trim();
    final category = _category;
    final document = widget.document;
    if (title == document.title && category == document.category) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.store.updateDetails(
        id: document.id,
        title: title,
        category: category,
      );
      if (!mounted) return;
      if (!updated) {
        setState(() {
          _saving = false;
          _error = 'İçerik bulunamadı. Değişikliklerin korundu.';
        });
        return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Bilgiler kaydedilemedi. Değişikliklerin korundu, tekrar deneyebilirsin.';
      });
      return;
    }
    setState(() => _closing = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.of(context).pop(
      SavedDocument(
        id: document.id,
        title: title,
        category: category,
        text: document.text,
        createdAt: document.createdAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving || _closing,
      child: AlertDialog(
        title: const Text('İçerik bilgilerini düzenle'),
        scrollable: true,
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('document-details-title'),
                controller: _title,
                enabled: !_saving,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Başlık',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final title = value?.trim() ?? '';
                  if (title.isEmpty) return 'Bir başlık yaz.';
                  if (title.length > 120) {
                    return 'Başlık en fazla 120 karakter olabilir.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<DocumentCategory>(
                key: const ValueKey('document-details-category'),
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
                        if (value != null) setState(() => _category = value);
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
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('save-document-details'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
          ),
        ],
      ),
    );
  }
}

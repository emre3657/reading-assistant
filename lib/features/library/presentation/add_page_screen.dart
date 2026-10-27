import 'dart:async';

import 'package:flutter/material.dart';

import '../../image_import/presentation/image_import_screen.dart';
import '../../listening/services/speech_service.dart';
import '../data/document_store.dart';

enum _DraftExit { keepEditing, discard, save }

class AddPageScreen extends StatefulWidget {
  const AddPageScreen({
    super.key,
    required this.documentId,
    required this.documentTitle,
    this.store,
    this.speechService,
  });

  final int documentId;
  final String documentTitle;
  final DocumentStore? store;
  final SpeechService? speechService;

  @override
  State<AddPageScreen> createState() => _AddPageScreenState();
}

class _AddPageScreenState extends State<AddPageScreen> {
  final _text = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _importing = false;
  bool _exiting = false;
  bool _allowPop = false;
  String? _error;

  DocumentStore get _store => widget.store ?? DocumentStore.instance;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _importOcr() async {
    if (_saving || _importing || _exiting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _importing = true);
    try {
      final text = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => ImageImportScreen(
            returnText: true,
            speechService: widget.speechService,
          ),
        ),
      );
      if (!mounted || text == null || text.trim().isEmpty) return;
      if (_text.text.isNotEmpty) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sayfa metni değiştirilsin mi?'),
            content: const Text(
              'Yeni çıkarılan metin mevcut taslağın yerine geçecek.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Değiştir'),
              ),
            ],
          ),
        );
        if (!mounted || replace != true) return;
      }
      _text.value = TextEditingValue(text: text);
      setState(() => _error = null);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _close(bool saved) async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(saved);
  }

  Future<void> _save() async {
    if (_saving || _importing || (_exiting && !_allowSaveDuringExit)) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final text = _text.text;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _store.appendPage(documentId: widget.documentId, text: text);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Sayfa eklenemedi. Metnin korundu; tekrar deneyebilirsin.';
      });
      return;
    }
    if (!mounted) return;
    await _close(true);
  }

  // Only the explicit save-and-exit choice can save during the exit flow.
  bool _allowSaveDuringExit = false;

  Future<void> _requestExit() async {
    if (_saving || _importing || _exiting || _allowPop) return;
    _exiting = true;
    try {
      if (_text.text.isNotEmpty) {
        final choice = await showDialog<_DraftExit>(
          context: context,
          barrierDismissible: false,
          builder: (context) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Kaydedilmemiş değişiklikler var'),
              content: const Text(
                'Bu sayfayı çıkmadan önce kaydetmek ister misin?',
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_DraftExit.keepEditing),
                  child: const Text('Düzenlemeye devam et'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_DraftExit.discard),
                  child: const Text('Kaydetmeden çık'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_DraftExit.save),
                  child: const Text('Kaydet ve çık'),
                ),
              ],
            ),
          ),
        );
        if (!mounted || choice == null || choice == _DraftExit.keepEditing) {
          return;
        }
        if (choice == _DraftExit.save) {
          _allowSaveDuringExit = true;
          try {
            await _save();
          } finally {
            _allowSaveDuringExit = false;
          }
          return;
        }
      }
      await _close(false);
    } finally {
      _exiting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _importing;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestExit());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sayfa ekle'),
          leading: BackButton(onPressed: () => unawaited(_requestExit())),
          actions: [
            TextButton(
              key: const ValueKey('save-page'),
              onPressed: busy ? null : _save,
              child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.documentTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _importOcr,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Görselden metin çıkar'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('new-page-text'),
                    controller: _text,
                    enabled: !busy,
                    minLines: 10,
                    maxLines: null,
                    textAlign: TextAlign.start,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Sayfa metni',
                      hintText: 'Metin yaz veya yapıştır.',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Sayfa metni boş olamaz.'
                        : null,
                  ),
                  if (_saving) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(
                      semanticsLabel: 'Sayfa kaydediliyor',
                    ),
                  ],
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

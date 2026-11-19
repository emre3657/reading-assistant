import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../library/data/document_store.dart';
import '../../library/presentation/save_document_dialog.dart';
import '../../listening/services/speech_service.dart';
import '../services/image_picker_service.dart';
import '../services/image_rotation_service.dart';
import '../services/text_recognition_service.dart';
import 'image_import_controller.dart';
import 'image_import_screen.dart';

class MultiPageScreen extends StatefulWidget {
  const MultiPageScreen({
    super.key,
    required this.files,
    required this.pickerService,
    required this.textRecognitionService,
    required this.rotationService,
    required this.previewImageBuilder,
    this.speechService,
    this.store,
    this.onSavePages,
    this.documentTitle,
  });

  final List<XFile> files;
  final ImagePickerService pickerService;
  final TextRecognitionService textRecognitionService;
  final ImageRotationService rotationService;
  final PreviewImageBuilder previewImageBuilder;
  final SpeechService? speechService;
  final DocumentStore? store;
  final Future<void> Function(List<String>)? onSavePages;
  final String? documentTitle;

  @override
  State<MultiPageScreen> createState() => _MultiPageScreenState();
}

class _PageDraft {
  _PageDraft(this.id, this.controller);
  final int id;
  final ImageImportController controller;
}

class _MultiPageScreenState extends State<MultiPageScreen> {
  late final List<_PageDraft> _pages;
  bool _processing = false;
  bool _saving = false;
  bool _allowPop = false;
  bool _confirmingExit = false;
  int _current = 0;
  int _total = 0;
  String? _error;
  Set<int> _emptyIds = {};
  bool get _busy =>
      _processing || _saving || _pages.any((p) => p.controller.isBusy);

  @override
  void initState() {
    super.initState();
    _pages = [
      for (var i = 0; i < widget.files.length; i++)
        _PageDraft(
          i,
          ImageImportController(
            pickerService: widget.pickerService,
            textRecognitionService: widget.textRecognitionService,
            rotationService: widget.rotationService,
            previewImageBuilder: widget.previewImageBuilder,
            initialFile: widget.files[i],
          )..addListener(_changed),
        ),
    ];
  }

  void _changed() {
    if (mounted) {
      setState(_refreshEmptyPages);
    }
  }

  void _refreshEmptyPages() {
    _emptyIds.removeWhere(
      (id) => !_pages.any(
        (page) =>
            page.id == id && page.controller.textController.text.trim().isEmpty,
      ),
    );
    if (_error?.startsWith('Boş sayfalar:') ?? false) {
      final numbers = [
        for (var i = 0; i < _pages.length; i++)
          if (_emptyIds.contains(_pages[i].id)) i + 1,
      ];
      _error = numbers.isEmpty
          ? null
          : 'Boş sayfalar: ${numbers.join(', ')}. Metin ekleyin.';
    }
  }

  @override
  void dispose() {
    for (final page in _pages) {
      page.controller.removeListener(_changed);
      page.controller.dispose();
    }
    super.dispose();
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _exit() async {
    if (_saving || _confirmingExit) return;
    _confirmingExit = true;
    final confirm =
        _pages.isEmpty ||
        await _confirm(
          'Taslaklardan çıkılsın mı?',
          'Kaydedilmemiş sayfa taslakları kaybolacak.',
          'Kaydetmeden çık',
        );
    if (!mounted) return;
    _confirmingExit = false;
    if (!confirm) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove(_PageDraft page) async {
    if (_busy) return;
    if (page.controller.textController.text.isNotEmpty &&
        !await _confirm(
          'Sayfa kaldırılsın mı?',
          'Bu sayfanın metin taslağı da silinecek.',
          'Sayfayı kaldır',
        )) {
      return;
    }
    if (!mounted || _busy) return;
    setState(() {
      _pages.remove(page);
      _emptyIds.remove(page.id);
      _refreshEmptyPages();
    });
    page.controller.removeListener(_changed);
    page.controller.dispose();
  }

  Future<void> _open(_PageDraft page) async {
    if (_busy) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ImageImportScreen(
          batchController: page.controller,
          batchPageNumber: _pages.indexOf(page) + 1,
          batchEmptyTextError: _emptyIds.contains(page.id),
          pickerService: widget.pickerService,
          textRecognitionService: widget.textRecognitionService,
          rotationService: widget.rotationService,
          previewImageBuilder: widget.previewImageBuilder,
          speechService: widget.speechService,
        ),
      ),
    );
    if (mounted) setState(_refreshEmptyPages);
  }

  Future<void> _recognizeAll() async {
    if (_busy) return;
    final pending = _pages
        .where(
          (p) =>
              !p.controller.hasRecognizedText &&
              p.controller.textController.text.isEmpty,
        )
        .toList();
    if (pending.isEmpty) {
      setState(() => _error = 'İşlenecek yeni sayfa yok.');
      return;
    }
    setState(() {
      _processing = true;
      _current = 0;
      _total = pending.length;
      _error = null;
    });
    try {
      for (final page in pending) {
        if (!mounted) return;
        setState(() => _current++);
        await page.controller.extractText(
          expectedRevision: page.controller.revision,
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _retry(_PageDraft page) async {
    if (_busy || page.controller.textController.text.isNotEmpty) return;
    await page.controller.extractText(
      expectedRevision: page.controller.revision,
    );
  }

  Future<void> _save() async {
    if (_busy || _pages.isEmpty) return;
    final empty = _pages
        .where((p) => p.controller.textController.text.trim().isEmpty)
        .toList();
    if (empty.isNotEmpty) {
      setState(() {
        _emptyIds = empty.map((p) => p.id).toSet();
        _error =
            'Boş sayfalar: ${empty.map((p) => _pages.indexOf(p) + 1).join(', ')}. Metin ekleyin.';
      });
      await _open(empty.first);
      return;
    }
    final texts = _pages.map((p) => p.controller.textController.text).toList();
    setState(() {
      _saving = true;
      _error = null;
      _emptyIds.clear();
    });
    try {
      if (widget.onSavePages case final save?) {
        await save(texts);
      } else {
        final saved = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => SaveDocumentDialog(
            text: texts.first,
            pages: texts,
            store: widget.store,
          ),
        );
        if (!mounted || saved != true) return;
      }
      if (!mounted) return;
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop(texts.length);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Sayfalar eklenemedi. Taslaklar korundu; tekrar deneyebilirsin.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_exit());
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Sayfa taslakları'),
        leading: BackButton(
          onPressed: _saving ? null : () => unawaited(_exit()),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.documentTitle != null)
              Text(
                widget.documentTitle!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            FilledButton.icon(
              onPressed: _busy || _pages.isEmpty ? null : _recognizeAll,
              icon: const Icon(Icons.text_snippet_outlined),
              label: const Text('Tüm sayfalardan metin çıkar'),
            ),
            if (_processing)
              Semantics(
                liveRegion: true,
                child: Text('$_current / $_total işleniyor'),
              ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (var i = 0; i < _pages.length; i++) _pageTile(_pages[i], i),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('save-batch'),
              onPressed: _busy || _pages.isEmpty ? null : _save,
              child: Text(
                _saving ? 'Kaydediliyor…' : '${_pages.length} sayfayı ekle',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _pageTile(_PageDraft page, int index) {
    final controller = page.controller;
    final image = controller.selection?.image;
    return Card(
      key: ValueKey('draft-${page.id}'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: _busy ? null : () => _open(page),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: image == null
                        ? const Icon(Icons.broken_image_outlined)
                        : RotatedBox(
                            quarterTurns: controller.quarterTurns,
                            child: Image(
                              image: ResizeImage.resizeIfNeeded(
                                controller.quarterTurns.isEven
                                    ? (64 *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .round()
                                    : null,
                                controller.quarterTurns.isOdd
                                    ? (64 *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .round()
                                    : null,
                                image,
                              ),
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${index + 1}. sayfa — Görseli ve metni düzenle',
                    ),
                  ),
                ],
              ),
            ),
            if (_emptyIds.contains(page.id))
              Text(
                'Sayfa metni boş.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (controller.errorMessage != null)
              Text(
                controller.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (controller.infoMessage != null) Text(controller.infoMessage!),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _busy || index == 0
                      ? null
                      : () => setState(() {
                          final p = _pages.removeAt(index);
                          _pages.insert(index - 1, p);
                          _refreshEmptyPages();
                        }),
                  icon: const Icon(Icons.arrow_upward),
                  label: const Text('Yukarı'),
                ),
                TextButton.icon(
                  onPressed: _busy || index == _pages.length - 1
                      ? null
                      : () => setState(() {
                          final p = _pages.removeAt(index);
                          _pages.insert(index + 1, p);
                          _refreshEmptyPages();
                        }),
                  icon: const Icon(Icons.arrow_downward),
                  label: const Text('Aşağı'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _remove(page),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Kaldır'),
                ),
                if (controller.errorMessage != null ||
                    controller.infoMessage != null)
                  TextButton(
                    onPressed:
                        _busy || controller.textController.text.isNotEmpty
                        ? null
                        : () => _retry(page),
                    child: const Text('Yeniden dene'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

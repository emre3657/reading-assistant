import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../listening/presentation/listening_controller.dart';
import '../../listening/presentation/listening_controls.dart';
import '../../listening/presentation/reading_settings_dialog.dart';
import '../../listening/presentation/reading_preferences.dart';
import '../../listening/presentation/reading_page_surface.dart';
import '../../listening/presentation/sentence_follow.dart';
import '../../listening/services/speech_service.dart';

import '../../library/presentation/library_screen.dart';
import '../../library/presentation/backup_screen.dart';
import '../../library/presentation/save_document_dialog.dart';
import '../../library/data/document_store.dart';

import '../services/image_picker_service.dart';
import '../services/image_rotation_service.dart';
import '../services/text_recognition_service.dart';

import 'image_import_controller.dart';
import 'multi_page_screen.dart';
import 'widgets/add_page_source.dart';
import 'widgets/image_preview.dart';

export 'image_import_controller.dart'
    show PreviewImageBuilder, fileImageProvider;

/// UI and dialogs of the image import flow. Controllers own processing state.
class ImageImportScreen extends StatefulWidget {
  const ImageImportScreen({
    super.key,
    this.pickerService = const ImagePickerService(),
    this.textRecognitionService = const TextRecognitionService(),
    this.rotationService = const ImageRotationService(),
    this.previewImageBuilder = fileImageProvider,
    this.speechService,
    this.returnText = false,
    this.onSavePage,
    this.pageDocumentTitle,
    this.store,
    this.onSavePages,
    this.batchController,
    this.batchPageNumber,
    this.batchTextValidated = false,
    this.backupFileService = const BackupFileService(),
  });

  final ImagePickerService pickerService;
  final TextRecognitionService textRecognitionService;
  final ImageRotationService rotationService;
  final PreviewImageBuilder previewImageBuilder;

  /// An injected service remains owned by its caller.
  final SpeechService? speechService;

  /// When true, returns the visible text to the calling page editor.
  final bool returnText;

  /// Appends the visible text to an existing content. The caller owns storage.
  final Future<void> Function(String text)? onSavePage;
  final String? pageDocumentTitle;
  final DocumentStore? store;
  final Future<void> Function(List<String> texts)? onSavePages;
  final ImageImportController? batchController;
  final int? batchPageNumber;
  final bool batchTextValidated;
  final BackupFileService backupFileService;

  @override
  State<ImageImportScreen> createState() => _ImageImportScreenState();
}

class _ImageImportScreenState extends State<ImageImportScreen>
    with WidgetsBindingObserver {
  late final ImageImportController _controller;
  late final ListeningController _listening;
  ReadingPreferences? _preferences;
  int _preferencesErrorRevision = 0;

  SpeechService? _ownedSpeechService;

  final _joinSectionKey = GlobalKey();
  final _batchErrorKey = GlobalKey();
  final _followKey = GlobalKey<SentenceFollowState>();
  final _followTextKey = GlobalKey();
  final _contentScrollController = ScrollController();

  int _lastRecognitionId = 0;
  int _scrollToken = 0;
  bool _panelExpanded = true;

  OverlayEntry? _editLockNotice;
  Timer? _editLockNoticeTimer;

  bool _saveDialogOpen = false;
  bool _openingBackup = false;
  bool _pickingBatch = false;
  bool _pickerActive = false;
  bool _manualEntry = false;
  bool _pageSaving = false;
  bool _pageExitInProgress = false;
  bool _allowPagePop = false;
  String? _pageError;
  bool _pageHasHadValidText = false;
  bool _pageTextError = false;
  bool _validationScrollPending = false;
  int? _readyPreviewId;
  bool get _batchEmptyTextError =>
      widget.batchController != null &&
      (widget.batchTextValidated || _controller.hasEncounteredEmptyOcr) &&
      _controller.textController.text.trim().isEmpty;

  bool get _addingPage => widget.onSavePage != null;
  bool get _pageLocked =>
      _pageSaving || _pageExitInProgress || _pickingBatch || _openingBackup;

  @override
  void initState() {
    super.initState();

    _controller =
        widget.batchController ??
        ImageImportController(
          pickerService: widget.pickerService,
          textRecognitionService: widget.textRecognitionService,
          rotationService: widget.rotationService,
          previewImageBuilder: widget.previewImageBuilder,
        );
    if (widget.batchController != null) {
      _manualEntry = true;
      if (_batchEmptyTextError) _scheduleScrollToText();
    }
    if (!_addingPage && !widget.returnText && widget.batchController == null) {
      unawaited(_controller.recoverLostImage());
    }

    _controller.addListener(_onImportChanged);

    final speechService =
        widget.speechService ?? (_ownedSpeechService = SpeechService());

    _listening = ListeningController(speechService: speechService);
    _controller.textController.attachListening(_listening);
    _listening.addListener(_onListeningChanged);

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preferences = ReadingPreferencesScope.of(context);
    if (_preferences == preferences) return;
    _preferences?.removeListener(_onPreferencesChanged);
    _preferences = preferences;
    preferences.addListener(_onPreferencesChanged);
    if (preferences.ready) {
      unawaited(_listening.setSpeed(preferences.speed));
    } else {
      unawaited(preferences.load());
    }
  }

  void _onPreferencesChanged() {
    final preferences = _preferences!;
    if (preferences.ready && _listening.speed != preferences.speed) {
      unawaited(_listening.setSpeed(preferences.speed));
    }
    if (mounted) setState(() {});
    if (_preferencesErrorRevision != preferences.errorRevision) {
      _preferencesErrorRevision = preferences.errorRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPreferencesError();
      });
    }
  }

  void _showPreferencesError() {
    final preferences = _preferences;
    if (!mounted ||
        preferences == null ||
        ModalRoute.of(context)?.isCurrent != true ||
        !preferences.claimError(preferences.errorRevision)) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(preferences.errorMessage!)));
  }

  Future<void> _openReadingSettings() async {
    await showReadingSettings(context, preferences: _preferences!);
    if (mounted) _showPreferencesError();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideEditLockNotice();
    _scrollToken++;

    _controller.removeListener(_onImportChanged);
    if (widget.batchController == null) {
      _controller.dispose();
    } else {
      _controller.textController.detachListening();
    }
    _preferences?.removeListener(_onPreferencesChanged);
    _contentScrollController.dispose();

    _listening.removeListener(_onListeningChanged);
    _listening.dispose();
    _ownedSpeechService?.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Temporary inactive states, such as system dialogs, do not stop reading.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _hideEditLockNotice();
      _listening.stop();
    }
  }

  void _onListeningChanged() {
    if (!_listening.isActive) {
      _hideEditLockNotice();
    }
  }

  void _hideEditLockNotice() {
    _editLockNoticeTimer?.cancel();
    _editLockNoticeTimer = null;

    final notice = _editLockNotice;
    _editLockNotice = null;

    if (notice != null) {
      notice.remove();
      notice.dispose();
    }
  }

  void _showEditLockNotice() {
    if (!mounted || !_listening.isActive) return;

    // Repeated taps extend the notice instead of stacking messages.
    _editLockNoticeTimer?.cancel();

    if (_editLockNotice == null) {
      final overlay = Overlay.of(context);
      final colorScheme = Theme.of(context).colorScheme;

      _editLockNotice = OverlayEntry(
        builder: (overlayContext) => Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            minimum: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: IgnorePointer(
              child: Semantics(
                liveRegion: true,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  color: colorScheme.inverseSurface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      'Metni düzenlemek için okumayı durdur.',
                      style: TextStyle(color: colorScheme.onInverseSurface),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      overlay.insert(_editLockNotice!);
    }

    _editLockNoticeTimer = Timer(
      const Duration(seconds: 3),
      _hideEditLockNotice,
    );
  }

  Future<void> _selectImage({bool camera = false}) async {
    if (_listening.isActive) return;

    final candidate = await _controller.pickImage(
      camera: camera,
      recoverToHome:
          !_addingPage &&
          !widget.returnText &&
          widget.batchController == null &&
          !_controller.hasImage &&
          _controller.textController.text.isEmpty,
    );
    if (candidate == null) return;

    var applied = false;

    try {
      // A cancelled picker never asks for confirmation.
      if (_controller.hasEditedText) {
        if (!mounted) return;

        final confirmed = await _confirm(
          title: 'Düzenlediğin metin silinsin mi?',
          content:
              'Yeni görsel seçilirse düzenlediğin metin silinecek. '
              'Metin henüz kaydedilmedi.',
          confirmLabel: 'Metni sil ve değiştir',
        );

        if (!confirmed || !mounted) return;
      }

      applied = _controller.applyPick(candidate);
      if (applied && mounted) setState(() => _manualEntry = false);
    } finally {
      if (!applied) _controller.discardPick(candidate);
    }
  }

  Future<void> _selectMultipleImages() async {
    if (_pickingBatch ||
        _controller.isBusy ||
        _listening.isActive ||
        _pageLocked) {
      return;
    }
    setState(() {
      _pickingBatch = true;
      _pickerActive = true;
    });
    List<XFile> files;
    try {
      files = await widget.pickerService.pickMultipleFromGallery(
        recoverToHome: !_addingPage && _controller.textController.text.isEmpty,
        limit: maxImagesPerSession,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _pickingBatch = false;
          _pickerActive = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Görsel seçilemedi. Lütfen tekrar deneyin.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _pickerActive = false);
    if (files.isEmpty) {
      setState(() => _pickingBatch = false);
      return;
    }
    try {
      if (files.length > maxImagesPerSession) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tek seferde en fazla $maxImagesPerSession sayfa ekleyebilirsin.',
            ),
          ),
        );
        return;
      }
      if (files.length == 1) {
        if (_controller.hasEditedText) {
          final confirmed = await _confirm(
            title: 'Düzenlediğin metin silinsin mi?',
            content: 'Yeni görsel seçilirse düzenlediğin metin silinecek. Metin henüz kaydedilmedi.',
            confirmLabel: 'Metni sil ve değiştir',
          );
          if (!mounted || !confirmed) return;
        }
        _controller.applySelectedFile(files.single);
        setState(() => _manualEntry = false);
        return;
      }
      if (_addingPage &&
          (_controller.hasImage ||
              _controller.textController.text.isNotEmpty)) {
        final confirmed = await _confirm(
          title: 'Mevcut sayfa taslağı kapatılsın mı?',
          content:
              'Toplu kayıt tamamlanırsa mevcut sayfa taslağın kapatılacak. '
              'Toplu işlemden kaydetmeden çıkarsan taslağın korunur.',
          confirmLabel: 'Toplu işleme devam et',
        );
        if (!mounted || !confirmed) return;
      }
      await _openBatch(files);
    } finally {
      if (mounted) setState(() => _pickingBatch = false);
    }
  }

  Future<void> _addPages() async {
    if (_pickingBatch ||
        _controller.isBusy ||
        _listening.isActive ||
        _pageLocked) {
      return;
    }
    setState(() => _pickingBatch = true);
    try {
      final source = await chooseAddPageSource(context);
      if (!mounted || source == null) return;
      setState(() => _pickerActive = true);
      final List<XFile> files;
      try {
        if (source == AddPageSource.camera) {
          final file = await widget.pickerService.takePhoto(
            recoverToHome: false,
          );
          files = [?file];
        } else {
          files = await widget.pickerService.pickMultipleFromGallery(
            recoverToHome: false,
            limit: maxImagesPerSession - 1,
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Görseller eklenemedi. Tekrar deneyebilirsin.'),
            ),
          );
        }
        return;
      }
      if (!mounted || files.isEmpty) return;
      setState(() => _pickerActive = false);
      final remaining = maxImagesPerSession - 1;
      if (files.length > remaining) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bu taslağa en fazla $remaining sayfa daha ekleyebilirsin.',
            ),
          ),
        );
        return;
      }
      await _openBatch(files, initialController: _controller);
    } finally {
      if (mounted) {
        setState(() {
          _pickingBatch = false;
          _pickerActive = false;
        });
      }
    }
  }

  Future<void> _openBatch(
    List<XFile> files, {
    ImageImportController? initialController,
  }) async {
    final savedCount = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => MultiPageScreen(
          files: files,
          pickerService: widget.pickerService,
          textRecognitionService: widget.textRecognitionService,
          rotationService: widget.rotationService,
          previewImageBuilder: widget.previewImageBuilder,
          speechService: widget.speechService,
          store: widget.store,
          onSavePages: widget.onSavePages,
          documentTitle: widget.pageDocumentTitle,
          initialController: initialController,
        ),
      ),
    );
    if (!mounted || savedCount == null) return;
    if (_addingPage) {
      await _closePage(savedCount);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sayfalar kaydedildi.')));
    }
  }

  Future<void> _removeImage() async {
    if (_controller.isBusy || _listening.isActive) return;

    final revision = _controller.revision;

    if (_controller.hasEditedText) {
      final confirmed = await _confirm(
        title: 'Düzenlediğin metin silinsin mi?',
        content:
            'Görsel kaldırılırsa düzenlediğin metin de silinecek. '
            'Metin henüz kaydedilmedi.',
        confirmLabel: 'Metni sil ve kaldır',
      );

      if (!confirmed || !mounted) return;
    }

    _controller.removeImage(expectedRevision: revision);
  }

  Future<void> _setJoinLines(bool value) async {
    if (_controller.isPicking || _listening.isActive || !_controller.hasImage) {
      return;
    }

    final revision = _controller.revision;

    if (!_controller.isRecognizing &&
        _controller.hasOcrResult &&
        _controller.hasEditedText) {
      final confirmed = await _confirm(
        title: 'Düzenlediğin metin silinsin mi?',
        content:
            'Satır birleştirme ayarı değiştirilirse düzenlediğin metin '
            'ham OCR sonucundan yeniden oluşturulacak. Metin henüz '
            'kaydedilmedi.',
        confirmLabel: 'Metni sil ve uygula',
      );

      if (!confirmed || !mounted) return;
    }

    _controller.setJoinLines(value, expectedRevision: revision);
  }

  Future<void> _extractText() async {
    if (!_controller.hasImage || _controller.isBusy || _listening.isActive) {
      return;
    }

    final revision = _controller.revision;

    if (_controller.hasEditedText ||
        (widget.batchController != null &&
            _controller.textController.text.isNotEmpty)) {
      final confirmed = await _confirm(
        title: 'Metnin üzerine yazılsın mı?',
        content:
            'Düzenlediğin metin, yeniden çıkarılan metinle değiştirilecek.',
        confirmLabel: 'Üzerine yaz',
      );

      if (!confirmed || !mounted) return;
    }

    await _controller.extractText(expectedRevision: revision);
  }

  Future<void> _clearText({bool close = false}) async {
    if (_controller.isBusy || _listening.isActive || _pageLocked) return;
    final text = _controller.textController.text;
    final revision = _controller.revision;
    if (text.isNotEmpty) {
      final confirmed = await _confirm(
        title: 'Metin temizlensin mi?',
        content: close
            ? 'Metin temizlenecek ve yazma alanı kapatılacak.'
            : 'Metin temizlenecek.',
        confirmLabel: close ? 'Temizle ve kapat' : 'Temizle',
      );
      if (!mounted || !confirmed) return;
    }
    if (_controller.isBusy || _listening.isActive || _pageLocked) return;
    _scrollToken++;
    if (!_controller.clearText(
      expectedRevision: revision,
      expectedText: text,
    )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Metin değişti. Tekrar deneyebilirsin.'),
          ),
        );
      }
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (close && mounted) setState(() => _manualEntry = false);
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> _startListening() async {
    if (_controller.isBusy ||
        _listening.isActive ||
        !(_preferences?.ready ?? false)) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    _followKey.currentState?.newSession();
    await _listening.start(_controller.textController.text);
  }

  void _onImportChanged() {
    if (_addingPage) {
      final hasText = _controller.textController.text.trim().isNotEmpty;
      if (hasText) {
        _pageHasHadValidText = true;
        if (_pageTextError) {
          setState(() => _pageTextError = false);
          _validationScrollPending = false;
          _scrollToken++;
        }
      } else if (_pageHasHadValidText && !_pageTextError) {
        setState(() => _pageTextError = true);
        _scheduleValidationScroll();
      }
    }
    final recovered = _controller.takeRecoveredBatch();
    if (recovered != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openBatch(recovered));
      });
    }
    final id = _controller.recognitionId;
    if (id == _lastRecognitionId) return;

    _lastRecognitionId = id;
    _scheduleScrollToText();
  }

  /// Scrolls to formatting options without requesting input focus.
  void _scheduleScrollToText() {
    if (_batchEmptyTextError || _pageTextError) {
      _scheduleValidationScroll();
      return;
    }
    _validationScrollPending = false;
    final token = ++_scrollToken;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _scrollToken) return;

      final sectionContext = _batchEmptyTextError
          ? _batchErrorKey.currentContext
          : _joinSectionKey.currentContext;
      if (sectionContext == null) return;

      final animate = !MediaQuery.disableAnimationsOf(context);

      Scrollable.ensureVisible(
        sectionContext,
        alignment: 0,
        duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
        curve: Curves.easeOut,
      );
    });
  }

  void _scheduleValidationScroll() {
    _validationScrollPending = true;
    _queueValidationScroll(++_scrollToken);
  }

  void _queueValidationScroll(int token) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _scrollToken || !_validationScrollPending) {
        return;
      }
      if (!_batchEmptyTextError && !_pageTextError) {
        _validationScrollPending = false;
        return;
      }
      final selection = _controller.selection;
      if (selection != null && selection.id != _readyPreviewId) return;
      final target = _batchErrorKey.currentContext;
      if (target == null ||
          !_contentScrollController.hasClients ||
          !_contentScrollController.position.hasContentDimensions) {
        return;
      }
      _validationScrollPending = false;
      Scrollable.ensureVisible(
        target,
        alignment: 0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _onPreviewReady(int selectionId) {
    if (_controller.selection?.id != selectionId) return;
    _readyPreviewId = selectionId;
    if (_validationScrollPending) _queueValidationScroll(_scrollToken);
  }

  Future<void> _saveDocument() async {
    if (_saveDialogOpen ||
        _controller.isBusy ||
        _listening.isActive ||
        _pageLocked) {
      return;
    }

    if (_addingPage) {
      await _persistPage();
      return;
    }

    final text = _controller.textController.text;
    if (text.trim().isEmpty) return;

    if (widget.returnText) {
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context).pop(text);
      return;
    }

    _saveDialogOpen = true;

    try {
      FocusManager.instance.primaryFocus?.unfocus();

      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            SaveDocumentDialog(text: text, store: widget.store),
      );

      if (!mounted || saved != true) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Metin kaydedildi.')));
    } finally {
      _saveDialogOpen = false;
    }
  }

  Future<void> _closePage(int? savedCount) async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _allowPagePop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(savedCount);
  }

  Future<void> _persistPage() async {
    if (!_addingPage ||
        _pageSaving ||
        _controller.isBusy ||
        _listening.isActive) {
      return;
    }
    final text = _controller.textController.text;
    if (text.trim().isEmpty) {
      setState(() => _pageTextError = true);
      _scheduleValidationScroll();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _pageSaving = true;
      _pageError = null;
    });
    try {
      await widget.onSavePage!(text);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pageSaving = false;
        _pageError = 'Sayfa eklenemedi. Metnin korundu; tekrar deneyebilirsin.';
      });
      return;
    }
    if (mounted) await _closePage(1);
  }

  Future<void> _requestPageExit() async {
    if (!_addingPage || _pageLocked || _controller.isBusy || _allowPagePop) {
      return;
    }
    setState(() => _pageExitInProgress = true);
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      if (_listening.isActive) {
        await _listening.stop();
        if (!mounted) return;
        if (_listening.status == ListeningStatus.failed) {
          setState(
            () => _pageError = _listening.message ?? 'Okuma durdurulamadı.',
          );
          return;
        }
      }
      if (_controller.textController.text.isNotEmpty) {
        final choice = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Kaydedilmemiş değişiklikler var'),
              content: const Text(
                'Bu sayfayı çıkmadan önce kaydetmek ister misin?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop('continue'),
                  child: const Text('Düzenlemeye devam et'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop('discard'),
                  child: const Text('Kaydetmeden çık'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop('save'),
                  child: const Text('Kaydet ve çık'),
                ),
              ],
            ),
          ),
        );
        if (!mounted || choice == null || choice == 'continue') return;
        if (choice == 'save') {
          await _persistPage();
          return;
        }
      }
      await _closePage(null);
    } finally {
      if (mounted) setState(() => _pageExitInProgress = false);
    }
  }

  Future<void> _openLibrary() async {
    if (_controller.isBusy ||
        _listening.isActive ||
        _saveDialogOpen ||
        _pageLocked) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            LibraryScreen(speechService: _listening.speechService),
      ),
    );
  }

  Future<void> _openBackup() async {
    if (_openingBackup ||
        _controller.isBusy ||
        _saveDialogOpen ||
        _pageLocked ||
        _listening.status == ListeningStatus.stopping) {
      return;
    }
    setState(() => _openingBackup = true);
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      if (_listening.isActive) {
        await _listening.stop();
        if (!mounted) return;
        if (_listening.status == ListeningStatus.failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_listening.message ?? 'Okuma durdurulamadı.'),
            ),
          );
          return;
        }
      }
      final restored = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => BackupScreen(
            store: widget.store ?? DocumentStore.instance,
            preferences: _preferences!,
            files: widget.backupFileService,
          ),
        ),
      );
      if (mounted && restored == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Yedek geri yüklendi.')));
      }
    } finally {
      if (mounted) setState(() => _openingBackup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _listening]),
      builder: (context, _) {
        final screen = _buildScreen(context);
        if (!_addingPage) return screen;
        return PopScope(
          canPop: _allowPagePop,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_requestPageExit());
          },
          child: screen,
        );
      },
    );
  }

  Widget _buildListeningPanel(BuildContext context) {
    if (_pageLocked) return const SizedBox.shrink();
    final hasText = _controller.textController.text.trim().isNotEmpty;

    if (!hasText) return const SizedBox.shrink();

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final visible = !(keyboardOpen && !_listening.isActive);

    return _AnimatedPanel(
      visible: visible,
      child: ListeningSurface(
        child: ListeningControls(
          key: const ValueKey('listening-panel'),
          listening: _listening,
          canStart:
              !_listening.isActive &&
              !_controller.isBusy &&
              (_preferences?.ready ?? false),
          onStart: _startListening,
          expanded: _panelExpanded,
          onToggleExpanded: () =>
              setState(() => _panelExpanded = !_panelExpanded),
        ),
      ),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final controller = _controller;
    final selection = controller.selection;
    final hasImage = selection != null;
    final colorScheme = Theme.of(context).colorScheme;
    final errorMessage = controller.errorMessage;
    final infoMessage = controller.infoMessage;
    final listeningActive = _listening.isActive;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.inversePrimary,
        title: Text(
          widget.batchController != null
              ? '${widget.batchPageNumber}. sayfa'
              : _addingPage
              ? 'Sayfa ekle'
              : widget.returnText
              ? 'Metin Çıkar'
              : 'Okuma Asistanı',
        ),
        leading: _addingPage
            ? BackButton(
                onPressed: _pageSaving || _controller.isBusy
                    ? null
                    : () => unawaited(_requestPageExit()),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Görünüm ve sesli okuma',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _pageLocked ? null : _openReadingSettings,
          ),
          if (widget.batchController != null)
            const SizedBox.shrink()
          else if (_addingPage)
            TextButton(
              key: const ValueKey('save-page'),
              onPressed:
                  _pageLocked ||
                      controller.isBusy ||
                      listeningActive ||
                      controller.textController.text.trim().isEmpty
                  ? null
                  : _saveDocument,
              child: Text(_pageSaving ? 'Kaydediliyor…' : 'Kaydet'),
            )
          else if (widget.returnText)
            TextButton(
              key: const ValueKey('use-ocr-text'),
              onPressed:
                  controller.isBusy ||
                      listeningActive ||
                      controller.textController.text.trim().isEmpty
                  ? null
                  : _saveDocument,
              child: const Text('Metni kullan'),
            )
          else
            IconButton(
              tooltip: 'Metni kaydet',
              icon: const Icon(Icons.save_outlined),
              onPressed:
                  controller.isBusy ||
                      listeningActive ||
                      _openingBackup ||
                      controller.textController.text.trim().isEmpty
                  ? null
                  : _saveDocument,
            ),
          if (!widget.returnText &&
              !_addingPage &&
              widget.batchController == null)
            IconButton(
              tooltip: 'Kayıtlarım',
              icon: const Icon(Icons.library_books_outlined),
              onPressed: controller.isBusy || listeningActive || _openingBackup
                  ? null
                  : _openLibrary,
            ),
          if (!widget.returnText &&
              !_addingPage &&
              widget.batchController == null)
            PopupMenuButton<String>(
              tooltip: 'Diğer seçenekler',
              enabled:
                  !_openingBackup && !controller.isBusy && !_saveDialogOpen,
              onSelected: (_) => _openBackup(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'backup',
                  child: Text('Yedekle ve geri yükle'),
                ),
              ],
            ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _pageLocked || _pickingBatch,
        child: SafeArea(
          child: SentenceFollow(
            key: _followKey,
            listening: _listening,
            preferences: _preferences!,
            textController: controller.textController,
            textKey: _followTextKey,
            scrollController: _contentScrollController,
            followTextSizeChanges: true,
            child: NotificationListener<ScrollStartNotification>(
              onNotification: (notification) {
                if (notification.depth == 0 &&
                    notification.dragDetails != null &&
                    _validationScrollPending) {
                  _validationScrollPending = false;
                  _scrollToken++;
                }
                return false;
              },
              child: SingleChildScrollView(
                key: const ValueKey('content-scroll'),
                controller: _contentScrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_addingPage) ...[
                      Text(
                        widget.pageDocumentTitle ?? '',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_pageError != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _pageError!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_pageSaving) ...[
                      const LinearProgressIndicator(
                        semanticsLabel: 'Sayfa kaydediliyor',
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (selection != null)
                      ImagePreview(
                        key: ValueKey(selection.id),
                        image: selection.image,
                        quarterTurns: controller.quarterTurns,
                        onReady: () => _onPreviewReady(selection.id),
                        onError: () {
                          controller.onPreviewError(selection.id);
                          if (_validationScrollPending) {
                            _queueValidationScroll(_scrollToken);
                          }
                        },
                      )
                    else
                      const _EmptyState(),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          errorMessage,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                    ],
                    if (infoMessage != null) ...[
                      const SizedBox(height: 16),
                      Semantics(liveRegion: true, child: Text(infoMessage)),
                    ],
                    const SizedBox(height: 16),
                    if (controller.isBusy || _pickerActive)
                      Center(
                        child: Column(
                          children: [
                            const CircularProgressIndicator(
                              semanticsLabel: 'Yükleniyor',
                            ),
                            if (controller.isRecognizing) ...[
                              const SizedBox(height: 8),
                              const Text('Metin çıkarılıyor…'),
                            ],
                          ],
                        ),
                      )
                    else ...[
                      if (hasImage) ...[
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: listeningActive
                                  ? null
                                  : () => controller.rotate(3),
                              icon: const Icon(Icons.rotate_left),
                              label: const Text('Sola döndür'),
                            ),
                            OutlinedButton.icon(
                              onPressed: listeningActive
                                  ? null
                                  : () => controller.rotate(1),
                              icon: const Icon(Icons.rotate_right),
                              label: const Text('Sağa döndür'),
                            ),
                          ],
                        ),
                        if (controller.quarterTurns != 0) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              'Görsel saat yönünde '
                              '${controller.quarterTurns * 90}° döndürüldü. '
                              'Metin çıkarma bu yönle yapılır.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: listeningActive ? null : _extractText,
                          icon: const Icon(Icons.text_snippet),
                          label: const Text('Metni çıkar'),
                        ),
                        ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: listeningActive
                                ? null
                                : () => _selectImage(),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Görseli değiştir'),
                          ),
                          if (widget.batchController == null) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: listeningActive ? null : _removeImage,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Görseli kaldır'),
                            ),
                          ],
                        ],
                      ] else
                        FilledButton.icon(
                          key: const ValueKey('pick-multiple'),
                          onPressed: listeningActive
                              ? null
                              : (widget.returnText ||
                                        widget.batchController != null
                                    ? () => _selectImage()
                                    : _selectMultipleImages),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Galeriden görsel seç'),
                        ),
                      if (widget.batchController == null) ...[
                        if (hasImage &&
                            !widget.returnText &&
                            (!_addingPage || widget.onSavePages != null)) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const ValueKey('add-draft-pages'),
                            onPressed: listeningActive || _pickingBatch
                                ? null
                                : _addPages,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: const Text('Sayfa ekle'),
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: listeningActive
                              ? null
                              : () => _selectImage(camera: true),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Fotoğraf çek'),
                        ),
                      ],
                    ],
                    if (!widget.returnText &&
                        !hasImage &&
                        !controller.hasRecognizedText &&
                        !_manualEntry) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const ValueKey('create-text'),
                        onPressed: controller.isBusy || listeningActive
                            ? null
                            : () {
                                setState(() => _manualEntry = true);
                                _scheduleScrollToText();
                              },
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Metin yaz veya yapıştır'),
                      ),
                    ],
                    if (hasImage) ...[
                      const SizedBox(height: 24),
                      SwitchListTile(
                        key: _joinSectionKey,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Satırları birleştir'),
                        subtitle: const Text(
                          'Satırları birleştirir; paragraf ve başlık ayrımlarını '
                          'tahmin eder.',
                        ),
                        value: controller.joinLines,
                        onChanged: controller.isPicking || listeningActive
                            ? null
                            : _setJoinLines,
                      ),
                    ],
                    if (controller.hasRecognizedText || _manualEntry) ...[
                      if (!hasImage) const SizedBox(height: 24),
                      const SizedBox(height: 8),
                      ListenableBuilder(
                        listenable: controller.textController,
                        builder: (context, _) => Wrap(
                          key: hasImage ? null : _joinSectionKey,
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _addingPage
                                  ? 'Sayfa metni'
                                  : controller.hasRecognizedText
                                  ? 'Çıkarılan metin'
                                  : 'Metin',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (listeningActive) const _EditLockIcon(),
                            if (controller.textController.text.isNotEmpty)
                              TextButton(
                                onPressed:
                                    controller.isBusy ||
                                        listeningActive ||
                                        _pageLocked
                                    ? null
                                    : _clearText,
                                child: const Text('Temizle'),
                              ),
                            if (_manualEntry &&
                                !controller.hasRecognizedText &&
                                widget.batchController == null)
                              TextButton(
                                onPressed:
                                    controller.isBusy ||
                                        listeningActive ||
                                        _pageLocked
                                    ? null
                                    : () => _clearText(close: true),
                                child: const Text('Kapat'),
                              ),
                          ],
                        ),
                      ),
                      if (_batchEmptyTextError || _pageTextError) ...[
                        const SizedBox(height: 4),
                        Semantics(
                          key: _batchErrorKey,
                          liveRegion: true,
                          child: Text(
                            _pageTextError ? 'Sayfa metni boş olamaz.' : 'Bu sayfanın metni boş. Metni çıkarın veya yazın.',
                            style: TextStyle(color: colorScheme.error),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      ReadingPageSurface(
                        view: _preferences!.pageView,
                        child: Semantics(
                          label: listeningActive
                              ? 'Metin, düzenleme kilitli. '
                                    'Düzenlemek için okumayı durdur'
                              : (controller.hasRecognizedText
                                    ? 'Çıkarılan metin'
                                    : 'Metin'),
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: listeningActive ? _showEditLockNotice : null,
                            child: KeyedSubtree(
                              key: _followTextKey,
                              child: TextField(
                                key: ValueKey(
                                  _addingPage ? 'new-page-text' : 'import-text',
                                ),
                                controller: controller.textController,
                                style: readingInputTextStyle(
                                  context,
                                  _preferences!.textSize,
                                  _preferences!.lineSpacing,
                                ),
                                textAlign:
                                    _preferences!.textAlignment.textAlign,
                                readOnly:
                                    controller.isRecognizing ||
                                    listeningActive ||
                                    _pageLocked,
                                canRequestFocus: !listeningActive,
                                enableInteractiveSelection: !listeningActive,
                                // While locked, the parent handles taps.
                                ignorePointers: listeningActive,
                                minLines: 6,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                decoration: InputDecoration(
                                  hintText: controller.hasRecognizedText
                                      ? null
                                      : 'Metnini yaz veya buraya yapıştır.',
                                  alignLabelWithHint: true,
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
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
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _controller.textController,
        builder: (context, _) => _buildListeningPanel(context),
      ),
    );
  }
}

/// Original lock icon and tap-triggered tooltip.
class _EditLockIcon extends StatelessWidget {
  const _EditLockIcon();

  static const message = 'Düzenlemek için okumayı durdur';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Düzenleme kilitli. $message',
      excludeSemantics: true,
      child: Tooltip(
        message: message,
        triggerMode: TooltipTriggerMode.tap,
        excludeFromSemantics: true,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.lock_outline, size: 20),
        ),
      ),
    );
  }
}

/// Animates keyboard-driven visibility while immediately disabling interaction.
class _AnimatedPanel extends StatelessWidget {
  const _AnimatedPanel({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animate = !MediaQuery.disableAnimationsOf(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(end: visible ? 1.0 : 0.0),
      duration: animate ? const Duration(milliseconds: 220) : Duration.zero,
      curve: Curves.easeOut,
      child: child,
      builder: (context, factor, child) {
        if (factor == 0 && !visible) return const SizedBox.shrink();

        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: factor,
            child: IgnorePointer(
              key: const ValueKey('listening-panel-guard'),
              ignoring: !visible,
              child: ExcludeFocus(
                excluding: !visible,
                child: ExcludeSemantics(excluding: !visible, child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Text(
        'Görselden metin çıkarabilir '
        'ya da kendin yazıp yapıştırabilirsin.',
        textAlign: TextAlign.center,
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../listening/presentation/listening_controller.dart';
import '../../listening/presentation/listening_controls.dart';
import '../../listening/presentation/reading_settings_dialog.dart';
import '../../listening/presentation/reading_preferences.dart';
import '../../listening/presentation/sentence_follow.dart';
import '../../listening/services/speech_service.dart';

import '../../library/presentation/library_screen.dart';
import '../../library/presentation/save_document_dialog.dart';
import '../../library/data/document_store.dart';

import '../services/image_picker_service.dart';
import '../services/image_rotation_service.dart';
import '../services/text_recognition_service.dart';

import 'image_import_controller.dart';
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
  final _followKey = GlobalKey<SentenceFollowState>();
  final _followTextKey = GlobalKey();
  final _contentScrollController = ScrollController();

  int _lastRecognitionId = 0;
  int _scrollToken = 0;
  bool _panelExpanded = true;

  OverlayEntry? _editLockNotice;
  Timer? _editLockNoticeTimer;

  bool _saveDialogOpen = false;
  bool _manualEntry = false;
  bool _pageSaving = false;
  bool _pageExitInProgress = false;
  bool _allowPagePop = false;
  String? _pageError;

  bool get _addingPage => widget.onSavePage != null;
  bool get _pageLocked => _pageSaving || _pageExitInProgress;

  @override
  void initState() {
    super.initState();

    _controller = ImageImportController(
      pickerService: widget.pickerService,
      textRecognitionService: widget.textRecognitionService,
      rotationService: widget.rotationService,
      previewImageBuilder: widget.previewImageBuilder,
    );
    if (!_addingPage && !widget.returnText) {
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
    _controller.dispose();
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
      recoverToHome: !_addingPage && !widget.returnText,
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
    if (_controller.isBusy ||
        _listening.isActive ||
        !_controller.hasRecognizedText) {
      return;
    }

    final revision = _controller.revision;

    if (_controller.hasEditedText) {
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

    if (_controller.hasEditedText) {
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

  Future<bool> _confirm({
    required String title,
    required String content,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
    final id = _controller.recognitionId;
    if (id == _lastRecognitionId) return;

    _lastRecognitionId = id;
    _scheduleScrollToText();
  }

  /// Scrolls to formatting options without requesting input focus.
  void _scheduleScrollToText() {
    final token = ++_scrollToken;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _scrollToken) return;

      final sectionContext = _joinSectionKey.currentContext;
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

  Future<void> _closePage(bool saved) async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _allowPagePop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(saved);
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
      setState(() => _pageError = 'Sayfa metni boş olamaz.');
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
    if (mounted) await _closePage(true);
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
      await _closePage(false);
    } finally {
      if (mounted) setState(() => _pageExitInProgress = false);
    }
  }

  Future<void> _openLibrary() async {
    if (_controller.isBusy || _listening.isActive || _saveDialogOpen) return;

    FocusManager.instance.primaryFocus?.unfocus();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            LibraryScreen(speechService: _listening.speechService),
      ),
    );
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
          _addingPage
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
            tooltip: 'Okuma ayarları',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _pageLocked ? null : _openReadingSettings,
          ),
          if (_addingPage)
            TextButton(
              key: const ValueKey('save-page'),
              onPressed: _pageLocked || controller.isBusy || listeningActive
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
                      controller.textController.text.trim().isEmpty
                  ? null
                  : _saveDocument,
            ),
          if (!widget.returnText && !_addingPage)
            IconButton(
              tooltip: 'Kayıtlarım',
              icon: const Icon(Icons.library_books_outlined),
              onPressed: controller.isBusy || listeningActive
                  ? null
                  : _openLibrary,
            ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _pageLocked,
        child: SafeArea(
          child: SentenceFollow(
            key: _followKey,
            listening: _listening,
            preferences: _preferences!,
            textController: controller.textController,
            textKey: _followTextKey,
            scrollController: _contentScrollController,
            followTextSizeChanges: true,
            child: SingleChildScrollView(
              key: const ValueKey('content-scroll'),
              controller: _contentScrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                      onError: () => controller.onPreviewError(selection.id),
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
                  if (controller.isBusy)
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
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: listeningActive
                            ? null
                            : () => _selectImage(),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Görseli değiştir'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: listeningActive ? null : _removeImage,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Görseli kaldır'),
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: listeningActive
                            ? null
                            : () => _selectImage(),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Galeriden görsel seç'),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: listeningActive
                          ? null
                          : () => _selectImage(camera: true),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Fotoğraf çek'),
                    ),
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
                  if (controller.hasRecognizedText || _manualEntry) ...[
                    const SizedBox(height: 24),
                    if (controller.hasRecognizedText)
                      SwitchListTile(
                        key: _joinSectionKey,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Satırları birleştir'),
                        subtitle: const Text(
                          'Satırları birleştirir; paragraf ve başlık ayrımlarını '
                          'tahmin eder.',
                        ),
                        value: controller.joinLines,
                        onChanged: controller.isBusy || listeningActive
                            ? null
                            : _setJoinLines,
                      ),
                    const SizedBox(height: 8),
                    Row(
                      key: controller.hasRecognizedText
                          ? null
                          : _joinSectionKey,
                      children: [
                        Flexible(
                          child: Text(
                            _addingPage
                                ? 'Sayfa metni'
                                : controller.hasRecognizedText
                                ? 'Çıkarılan metin'
                                : 'Metin',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (listeningActive) const _EditLockIcon(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Semantics(
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
                            style:
                                _preferences!.textSize == ReadingTextSize.normal
                                ? null
                                : TextStyle(
                                    fontSize:
                                        ((Theme.of(context).useMaterial3
                                                    ? Theme.of(context)
                                                          .textTheme
                                                          .bodyLarge
                                                    : Theme.of(context)
                                                          .textTheme
                                                          .titleMedium)
                                                ?.fontSize ??
                                            16) *
                                        _preferences!.textSize.multiplier,
                                  ),
                            textAlign: _addingPage
                                ? TextAlign.start
                                : TextAlign.justify,
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
                  ],
                ],
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

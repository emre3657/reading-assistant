import 'package:flutter/material.dart';

import '../../listening/presentation/listening_controller.dart';
import '../../listening/services/speech_service.dart';
import '../services/image_picker_service.dart';
import '../services/image_rotation_service.dart';
import '../services/text_recognition_service.dart';
import 'image_import_controller.dart';
import 'widgets/image_preview.dart';

export 'image_import_controller.dart'
    show PreviewImageBuilder, fileImageProvider;

/// UI and dialogs of the image import flow. State and async flows live in
/// [ImageImportController]; confirmations are asked here, with the controller
/// revision read before asking, so a stale answer is ignored.
///
/// Reading aloud lives in [ListeningController]. The two controllers do not
/// know each other; this screen keeps them apart: while one is busy, the
/// other's actions are disabled.
class ImageImportScreen extends StatefulWidget {
  const ImageImportScreen({
    super.key,
    this.pickerService = const ImagePickerService(),
    this.textRecognitionService = const TextRecognitionService(),
    this.rotationService = const ImageRotationService(),
    this.previewImageBuilder = fileImageProvider,
    this.speechService,
  });

  final ImagePickerService pickerService;
  final TextRecognitionService textRecognitionService;
  final ImageRotationService rotationService;
  final PreviewImageBuilder previewImageBuilder;

  /// When null the screen creates (and disposes) the device speech service;
  /// an injected one stays owned by the caller.
  final SpeechService? speechService;

  @override
  State<ImageImportScreen> createState() => _ImageImportScreenState();
}

class _ImageImportScreenState extends State<ImageImportScreen>
    with WidgetsBindingObserver {
  late final ImageImportController _controller;
  late final ListeningController _listening;
  SpeechService? _ownedSpeechService;

  @override
  void initState() {
    super.initState();
    _controller = ImageImportController(
      pickerService: widget.pickerService,
      textRecognitionService: widget.textRecognitionService,
      rotationService: widget.rotationService,
      previewImageBuilder: widget.previewImageBuilder,
    )..recoverLostImage();
    final speechService =
        widget.speechService ?? (_ownedSpeechService = SpeechService());
    _listening = ListeningController(speechService: speechService);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // A running OCR call is not cancelled; the controller drops its result
    // and still deletes the run's temporary copy.
    _controller.dispose();
    // Stops reading if it is active; the owned service is released after.
    _listening.dispose();
    _ownedSpeechService?.dispose();
    super.dispose();
  }

  // `inactive` is not handled: system dialogs and the notification shade
  // cause it, and reading may go on there. Leaving the app (hidden/paused)
  // stops it, because the first version has no background listening.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _listening.stop();
    }
  }

  Future<void> _selectImage() async {
    if (_listening.isActive) return;
    final candidate = await _controller.pickImage();
    if (candidate == null) return;
    var applied = false;
    try {
      // The picker is opened first, so a cancelled pick never asks anything.
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
    if (_controller.isBusy || _listening.isActive) return;
    // The text currently shown in the field, not the raw OCR result.
    await _listening.start(_controller.textController.text);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _listening]),
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildListeningControls(BuildContext context) {
    final listening = _listening;
    final colorScheme = Theme.of(context).colorScheme;
    final message = listening.message;
    final status = listening.status;
    final statusText = switch (status) {
      ListeningStatus.starting => 'Okuma hazırlanıyor…',
      ListeningStatus.speaking => 'Okunuyor…',
      ListeningStatus.paused => 'Duraklatıldı.',
      ListeningStatus.stopping => 'Durduruluyor…',
      _ => null,
    };
    final canStart = !listening.isActive && !_controller.isBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: canStart ? _startListening : null,
              icon: const Icon(Icons.volume_up),
              label: const Text('Sesli oku'),
            ),
            if (listening.canResume)
              OutlinedButton.icon(
                onPressed: _listening.resume,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Devam et'),
              )
            else
              OutlinedButton.icon(
                onPressed: listening.canPause ? _listening.pause : null,
                icon: const Icon(Icons.pause),
                label: const Text('Duraklat'),
              ),
            OutlinedButton.icon(
              onPressed: listening.canGoPrevious
                  ? _listening.previousSentence
                  : null,
              icon: const Icon(Icons.skip_previous),
              label: const Text('Önceki cümle'),
            ),
            OutlinedButton.icon(
              onPressed: listening.canGoNext ? _listening.nextSentence : null,
              icon: const Icon(Icons.skip_next),
              label: const Text('Sonraki cümle'),
            ),
            OutlinedButton.icon(
              onPressed: listening.canRestart
                  ? _listening.restartFromBeginning
                  : null,
              icon: const Icon(Icons.first_page),
              label: const Text('Başa dön'),
            ),
            OutlinedButton.icon(
              onPressed: listening.canStop ? _listening.stop : null,
              icon: const Icon(Icons.stop),
              label: const Text('Durdur'),
            ),
          ],
        ),
        if (listening.sentenceCount > 0) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              'Cümle ${listening.currentSentence} / ${listening.sentenceCount}',
              textAlign: TextAlign.center,
            ),
          ),
          Text(
            'Devam et, mevcut cümlenin başından okur.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (statusText != null || message != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              statusText ?? message!,
              textAlign: TextAlign.center,
              style: status == ListeningStatus.failed
                  ? TextStyle(color: colorScheme.error)
                  : null,
            ),
          ),
        ],
      ],
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
        title: const Text('Reading Assistant'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                        'Görsel saat yönünde ${controller.quarterTurns * 90}° döndürüldü. '
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
                    onPressed: listeningActive ? null : _selectImage,
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
                    onPressed: listeningActive ? null : _selectImage,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Galeriden görsel seç'),
                  ),
              ],
              if (controller.hasRecognizedText) ...[
                const SizedBox(height: 24),
                SwitchListTile(
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
                TextField(
                  controller: controller.textController,
                  textAlign: TextAlign.justify,
                  readOnly: controller.isRecognizing || listeningActive,
                  minLines: 6,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Çıkarılan metin',
                    helperText: 'Bu metin henüz kaydedilmedi. Gerekirse düzeltebilirsin.',
                    helperMaxLines: 3,
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _buildListeningControls(context),
              ],
            ],
          ),
        ),
      ),
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
        'Metnini okumak istediğin sayfanın fotoğrafını galeriden seç.',
        textAlign: TextAlign.center,
      ),
    );
  }
}

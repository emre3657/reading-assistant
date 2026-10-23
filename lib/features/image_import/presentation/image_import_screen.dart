import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/image_picker_service.dart';
import '../services/text_recognition_service.dart';
import 'widgets/image_preview.dart';

/// Creates the image used to preview a picked file.
typedef PreviewImageBuilder = ImageProvider Function(XFile file);

ImageProvider fileImageProvider(XFile file) => FileImage(File(file.path));

/// One successful pick or recovery. The id tells apart two selections of the
/// same file.
class _Selection {
  const _Selection(this.id, this.file, this.image);

  final int id;
  final XFile file;
  final ImageProvider image;
}

class ImageImportScreen extends StatefulWidget {
  const ImageImportScreen({
    super.key,
    this.pickerService = const ImagePickerService(),
    this.textRecognitionService = const TextRecognitionService(),
    this.previewImageBuilder = fileImageProvider,
  });

  final ImagePickerService pickerService;
  final TextRecognitionService textRecognitionService;
  final PreviewImageBuilder previewImageBuilder;

  @override
  State<ImageImportScreen> createState() => _ImageImportScreenState();
}

class _ImageImportScreenState extends State<ImageImportScreen> {
  final _textController = TextEditingController();
  _Selection? _selection;
  int _lastSelectionId = 0;
  bool _isPicking = false;
  bool _isRecognizing = false;

  /// Last text produced by OCR; null when there is no OCR result. Used to tell
  /// whether the user has edited the text.
  String? _recognizedText;
  String? _errorMessage;
  String? _infoMessage;

  bool get _isBusy => _isPicking || _isRecognizing;

  @override
  void initState() {
    super.initState();
    if (widget.pickerService.canRecoverLostImage) {
      _isPicking = true;
      _recoverLostImage();
    }
  }

  @override
  void dispose() {
    // A running OCR call is not cancelled; its result is ignored because the
    // screen is no longer mounted.
    _textController.dispose();
    super.dispose();
  }

  /// Replaces the current image and drops everything tied to the old one.
  /// Must be called inside setState.
  void _applySelection(XFile file) {
    _selection = _Selection(
      ++_lastSelectionId,
      file,
      widget.previewImageBuilder(file),
    );
    _recognizedText = null;
    _textController.clear();
  }

  Future<void> _recoverLostImage() async {
    XFile? recovered;
    String? error;
    try {
      recovered = await widget.pickerService.retrieveLostImage();
    } catch (_) {
      error = 'Önceki fotoğraf seçimi kurtarılamadı. Lütfen tekrar seçin.';
    }
    if (!mounted) return;
    setState(() {
      _isPicking = false;
      if (recovered != null) _applySelection(recovered);
      _errorMessage = error;
    });
  }

  Future<void> _selectImage() async {
    if (_isBusy) return;
    setState(() {
      _isPicking = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    XFile? picked;
    String? error;
    try {
      picked = await widget.pickerService.pickFromGallery();
    } catch (_) {
      error = 'Görsel seçilemedi. Lütfen tekrar deneyin.';
    }
    if (!mounted) return;
    setState(() {
      _isPicking = false;
      // A cancelled pick (null) keeps the current image and text.
      if (picked != null) _applySelection(picked);
      _errorMessage = error;
    });
  }

  void _removeImage() {
    if (_isBusy) return;
    // Only drops the reference. File ownership and cleanup are not managed
    // yet, so nothing is deleted.
    setState(() {
      _selection = null;
      _recognizedText = null;
      _textController.clear();
      _errorMessage = null;
      _infoMessage = null;
    });
  }

  void _onPreviewError(int selectionId) {
    // Ignore errors that belong to a selection that is no longer active.
    if (!mounted || _selection?.id != selectionId) return;
    // The text is kept: the user may have edited it.
    setState(() {
      _selection = null;
      _errorMessage = 'Görsel görüntülenemedi. Lütfen başka bir görsel seçin.';
      _infoMessage = null;
    });
  }

  Future<bool> _confirmOverwrite() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Metnin üzerine yazılsın mı?'),
        content: const Text(
          'Düzenlediğin metin, yeniden çıkarılan metinle değiştirilecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Üzerine yaz'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _extractText() async {
    final selection = _selection;
    if (selection == null || _isBusy) return;

    final currentText = _textController.text;
    if (currentText.isNotEmpty && currentText != _recognizedText) {
      final confirmed = await _confirmOverwrite();
      if (!confirmed || !mounted || _isBusy || _selection?.id != selection.id) {
        return;
      }
    }

    setState(() {
      _isRecognizing = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    String? text;
    String? error;
    try {
      // The original picked file is used, not the downscaled preview.
      text = await widget.textRecognitionService.recognizeText(
        selection.file.path,
      );
    } catch (_) {
      error = 'Metin çıkarılamadı. Tekrar denemek için "Metni çıkar" düğmesine bas.';
    }
    if (!mounted) return;
    if (_selection?.id != selection.id) {
      // The image went away while OCR was running; drop the result.
      setState(() => _isRecognizing = false);
      return;
    }
    setState(() {
      _isRecognizing = false;
      _errorMessage = error;
      if (text != null) {
        if (text.trim().isEmpty) {
          _infoMessage =
              'Görselde metin bulunamadı. Daha net veya daha yakın bir '
              'fotoğrafla "Metni çıkar" düğmesine tekrar basabilirsin.';
        } else {
          _recognizedText = text;
          _textController.value = TextEditingValue(text: text);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    final hasImage = selection != null;
    final colorScheme = Theme.of(context).colorScheme;

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
                  onError: () => _onPreviewError(selection.id),
                )
              else
                const _EmptyState(),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
              ],
              if (_infoMessage != null) ...[
                const SizedBox(height: 16),
                Semantics(liveRegion: true, child: Text(_infoMessage!)),
              ],
              const SizedBox(height: 16),
              if (_isBusy)
                Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(
                        semanticsLabel: 'Yükleniyor',
                      ),
                      if (_isRecognizing) ...[
                        const SizedBox(height: 8),
                        const Text('Metin çıkarılıyor…'),
                      ],
                    ],
                  ),
                )
              else ...[
                if (hasImage) ...[
                  FilledButton.icon(
                    onPressed: _extractText,
                    icon: const Icon(Icons.text_snippet),
                    label: const Text('Metni çıkar'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _selectImage,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Görseli değiştir'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _removeImage,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Görseli kaldır'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: _selectImage,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Galeriden görsel seç'),
                  ),
              ],
              if (_recognizedText != null) ...[
                const SizedBox(height: 24),
                TextField(
                  controller: _textController,
                  readOnly: _isRecognizing,
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

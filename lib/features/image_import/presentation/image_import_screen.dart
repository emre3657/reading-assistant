import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/image_picker_service.dart';
import 'widgets/image_preview.dart';

/// Creates the image used to preview a picked file.
typedef PreviewImageBuilder = ImageProvider Function(XFile file);

ImageProvider fileImageProvider(XFile file) => FileImage(File(file.path));

/// One successful pick or recovery. The id tells apart two selections of the
/// same file.
class _Selection {
  const _Selection(this.id, this.image);

  final int id;
  final ImageProvider image;
}

class ImageImportScreen extends StatefulWidget {
  const ImageImportScreen({
    super.key,
    this.pickerService = const ImagePickerService(),
    this.previewImageBuilder = fileImageProvider,
  });

  final ImagePickerService pickerService;
  final PreviewImageBuilder previewImageBuilder;

  @override
  State<ImageImportScreen> createState() => _ImageImportScreenState();
}

class _ImageImportScreenState extends State<ImageImportScreen> {
  _Selection? _selection;
  int _lastSelectionId = 0;
  bool _isPicking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.pickerService.canRecoverLostImage) {
      _isPicking = true;
      _recoverLostImage();
    }
  }

  _Selection _newSelection(XFile file) =>
      _Selection(++_lastSelectionId, widget.previewImageBuilder(file));

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
      if (recovered != null) _selection = _newSelection(recovered);
      _errorMessage = error;
    });
  }

  Future<void> _selectImage() async {
    if (_isPicking) return;
    setState(() {
      _isPicking = true;
      _errorMessage = null;
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
      // A cancelled pick (null) keeps the current image.
      if (picked != null) _selection = _newSelection(picked);
      _errorMessage = error;
    });
  }

  void _removeImage() {
    if (_isPicking) return;
    // Only drops the reference. File ownership and cleanup are not managed
    // yet, so nothing is deleted.
    setState(() {
      _selection = null;
      _errorMessage = null;
    });
  }

  void _onPreviewError(int selectionId) {
    // Ignore errors that belong to a selection that is no longer active.
    if (!mounted || _selection?.id != selectionId) return;
    setState(() {
      _selection = null;
      _errorMessage = 'Görsel görüntülenemedi. Lütfen başka bir görsel seçin.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    final hasImage = selection != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Reading Assistant'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_isPicking)
                const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Yükleniyor',
                  ),
                )
              else ...[
                FilledButton.icon(
                  onPressed: _selectImage,
                  icon: const Icon(Icons.photo_library),
                  label: Text(
                    hasImage ? 'Görseli değiştir' : 'Galeriden görsel seç',
                  ),
                ),
                if (hasImage) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _removeImage,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Görseli kaldır'),
                  ),
                ],
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

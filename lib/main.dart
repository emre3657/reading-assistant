import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const ReadingAssistantApp());
}

/// Opens the system photo picker. Returns null when the user cancels.
typedef PickImage = Future<XFile?> Function();

/// Returns an image picked before Android killed the activity, if any.
typedef RetrieveLostImage = Future<XFile?> Function();

Future<XFile?> pickImageFromGallery() {
  // Full metadata is not needed and would request extra photo permissions.
  return ImagePicker().pickImage(
    source: ImageSource.gallery,
    requestFullMetadata: false,
  );
}

Future<XFile?> retrieveLostImageFromPicker() async {
  final response = await ImagePicker().retrieveLostData();
  if (response.isEmpty) return null;
  if (response.exception != null) throw response.exception!;
  return response.file ?? response.files?.firstOrNull;
}

class ReadingAssistantApp extends StatelessWidget {
  const ReadingAssistantApp({
    super.key,
    this.pickImage = pickImageFromGallery,
    this.retrieveLostImage = retrieveLostImageFromPicker,
  });

  final PickImage pickImage;
  final RetrieveLostImage retrieveLostImage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reading Assistant',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: HomePage(
        pickImage: pickImage,
        retrieveLostImage: retrieveLostImage,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.pickImage,
    required this.retrieveLostImage,
  });

  final PickImage pickImage;
  final RetrieveLostImage retrieveLostImage;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  XFile? _image;
  bool _isPicking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Lost picker results only exist on Android.
    if (defaultTargetPlatform == TargetPlatform.android) {
      _isPicking = true;
      _recoverLostImage();
    }
  }

  Future<void> _recoverLostImage() async {
    XFile? recovered;
    String? error;
    try {
      recovered = await widget.retrieveLostImage();
    } catch (_) {
      error = 'Önceki fotoğraf seçimi kurtarılamadı. Lütfen tekrar seçin.';
    }
    if (!mounted) return;
    setState(() {
      _isPicking = false;
      if (recovered != null) _image = recovered;
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
      picked = await widget.pickImage();
    } catch (_) {
      error = 'Görsel seçilemedi. Lütfen tekrar deneyin.';
    }
    if (!mounted) return;
    setState(() {
      _isPicking = false;
      // A cancelled pick (null) keeps the current image.
      if (picked != null) _image = picked;
      _errorMessage = error;
    });
  }

  void _removeImage() {
    if (_isPicking) return;
    // Only drops the reference. The file is not deleted here because the
    // picker's copy may still be needed by later steps.
    setState(() {
      _image = null;
      _errorMessage = null;
    });
  }

  void _onPreviewError() {
    if (!mounted) return;
    setState(() {
      _image = null;
      _errorMessage = 'Görsel görüntülenemedi. Lütfen başka bir görsel seçin.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final hasImage = image != null;

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
              if (hasImage)
                _ImagePreview(
                  key: ValueKey(image.path),
                  path: image.path,
                  onError: _onPreviewError,
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

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({super.key, required this.path, required this.onError});

  final String path;
  final VoidCallback onError;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      semanticLabel: 'Seçilen görselin önizlemesi',
      errorBuilder: (context, error, stackTrace) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onError());
        return const SizedBox.shrink();
      },
    );
  }
}

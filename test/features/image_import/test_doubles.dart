import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/features/image_import/services/image_picker_service.dart';
import 'package:reading_assistant/features/image_import/services/image_rotation_service.dart';
import 'package:reading_assistant/features/image_import/services/ocr_result.dart';
import 'package:reading_assistant/features/image_import/services/text_recognition_service.dart';

class FakeTextRecognitionService implements TextRecognitionService {
  FakeTextRecognitionService(Future<String> Function(String path) onRecognize)
    : _onRecognize = ((path) async => OcrResult(await onRecognize(path)));

  /// Returns text together with a line layout.
  FakeTextRecognitionService.withLayout(this._onRecognize);

  final Future<OcrResult> Function(String path) _onRecognize;
  final List<String> paths = [];

  @override
  Future<OcrResult> recognizeText(String imagePath) {
    paths.add(imagePath);
    return _onRecognize(imagePath);
  }
}

/// Image provider whose load never finishes until the test fails it.
class ControlledImageProvider extends ImageProvider<ControlledImageProvider> {
  final Completer<ui.Codec> codec = Completer<ui.Codec>();

  void fail() => codec.completeError(Exception('decode failed'));

  @override
  Future<ControlledImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    ControlledImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(codec: codec.future, scale: 1);
  }
}

class FakeImageRotationService implements ImageRotationService {
  FakeImageRotationService({this.onCreate, this.onDelete});

  final Future<String> Function(String sourcePath, int quarterTurns)? onCreate;
  final Future<void> Function(String path)? onDelete;

  /// Source path and turns of every copy request.
  final List<(String, int)> created = [];
  final List<String> deleted = [];

  @override
  Future<String> createRotatedCopy(String sourcePath, int quarterTurns) {
    created.add((sourcePath, quarterTurns));
    return onCreate?.call(sourcePath, quarterTurns) ??
        Future.value('/tmp/rotated_${created.length}.jpg');
  }

  @override
  Future<void> deleteCopy(String path) async {
    deleted.add(path);
    await onDelete?.call(path);
  }
}

class FakeImagePickerService implements ImagePickerService {
  FakeImagePickerService({
    this.onPick,
    this.onRetrieveLost,
    this.canRecoverLostImage = false,
  });

  final Future<XFile?> Function()? onPick;
  final Future<XFile?> Function()? onRetrieveLost;

  @override
  final bool canRecoverLostImage;

  @override
  Future<XFile?> pickFromGallery() async => onPick?.call();

  @override
  Future<XFile?> retrieveLostImage() async => onRetrieveLost?.call();
}

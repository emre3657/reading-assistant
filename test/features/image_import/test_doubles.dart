import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/features/image_import/services/image_picker_service.dart';

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

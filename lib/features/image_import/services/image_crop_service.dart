import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class OwnedCrop {
  OwnedCrop._(this.path, this._directory);

  final String path;
  final Directory _directory;
  int _references = 1;

  OwnedCrop retain() {
    if (_references <= 0) throw StateError('Crop has already been released');
    _references++;
    return this;
  }

  Future<void> release() async {
    if (_references <= 0) throw StateError('Crop has already been released');
    _references--;
    if (_references == 0) {
      try {
        await _directory.delete(recursive: true);
      } on FileSystemException catch (error, stack) {
        debugPrint('Kırpılmış görsel temizlenemedi: $error\n$stack');
      }
    }
  }
}

class ImageCropService {
  const ImageCropService();

  Future<OwnedCrop> createCrop(
    String sourcePath,
    int quarterTurns,
    Rect bounds,
  ) async {
    if (!bounds.left.isFinite ||
        !bounds.top.isFinite ||
        !bounds.right.isFinite ||
        !bounds.bottom.isFinite ||
        bounds.left < 0 ||
        bounds.top < 0 ||
        bounds.right > 1 ||
        bounds.bottom > 1 ||
        bounds.isEmpty) {
      throw ArgumentError.value(bounds, 'bounds');
    }
    final directory = await Directory.systemTemp.createTemp(
      'reading_assistant_crop_',
    );
    final path = '${directory.path}${Platform.pathSeparator}crop.png';
    try {
      await Isolate.run(
        () => _cropToFile(sourcePath, path, quarterTurns, bounds),
      );
      return OwnedCrop._(path, directory);
    } catch (error, stack) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException catch (cleanupError, cleanupStack) {
        debugPrint(
          'Kırpma dosyası temizlenemedi: $cleanupError\n$cleanupStack',
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }
}

void _cropToFile(String sourcePath, String path, int turns, Rect bounds) {
  final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (decoded == null) throw const FormatException('Unsupported image');
  final oriented = img.bakeOrientation(decoded);
  final rotated = turns % 4 == 0
      ? oriented
      : img.copyRotate(oriented, angle: (turns % 4) * 90);
  final left = (bounds.left * rotated.width).round().clamp(
    0,
    rotated.width - 1,
  );
  final top = (bounds.top * rotated.height).round().clamp(
    0,
    rotated.height - 1,
  );
  final right = (bounds.right * rotated.width).round().clamp(
    left + 1,
    rotated.width,
  );
  final bottom = (bounds.bottom * rotated.height).round().clamp(
    top + 1,
    rotated.height,
  );
  final cropped = img.copyCrop(
    rotated,
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );
  File(path).writeAsBytesSync(img.encodePng(cropped));
}

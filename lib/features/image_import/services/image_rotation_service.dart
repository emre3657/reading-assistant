import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

/// Creates rotated copies of picked images for OCR.
///
/// Every copy lives in its own temporary directory created by this service,
/// and only such directories are deleted by [deleteCopy]. The source file is
/// never modified or deleted.
class ImageRotationService {
  const ImageRotationService();

  static const _directoryPrefix = 'reading_assistant_ocr_';

  /// Writes a copy of [sourcePath] rotated clockwise by [quarterTurns] * 90
  /// degrees and returns its path.
  ///
  /// The copy is always made from the source file, so repeated rotations never
  /// recompress an earlier output. The EXIF orientation is applied exactly
  /// once (the decoder applies it; [img.bakeOrientation] covers decoders that
  /// do not) and the copy carries no orientation tag. Decoding, rotating and
  /// encoding run in a separate isolate.
  Future<String> createRotatedCopy(String sourcePath, int quarterTurns) async {
    final turns = quarterTurns % 4;
    final directory = await Directory.systemTemp.createTemp(_directoryPrefix);
    final outputPath = '${directory.path}${Platform.pathSeparator}rotated.jpg';
    try {
      await Isolate.run(() => _rotateToFile(sourcePath, outputPath, turns));
      return outputPath;
    } catch (_) {
      await _deleteDirectory(directory);
      rethrow;
    }
  }

  /// Deletes a copy made by [createRotatedCopy] together with its directory.
  /// Paths that were not created by this service are ignored.
  Future<void> deleteCopy(String path) async {
    final directory = File(path).parent;
    final name = directory.uri.pathSegments.lastWhere(
      (segment) => segment.isNotEmpty,
      orElse: () => '',
    );
    if (!name.startsWith(_directoryPrefix)) return;
    await _deleteDirectory(directory);
  }

  Future<void> _deleteDirectory(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // A leftover cache file is harmless; cleanup must not break the flow.
    }
  }
}

void _rotateToFile(String sourcePath, String outputPath, int turns) {
  final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (decoded == null) {
    throw const FormatException('Unsupported image format');
  }
  final rotated = img.copyRotate(
    img.bakeOrientation(decoded),
    angle: turns * 90,
  );
  File(outputPath).writeAsBytesSync(img.encodeJpg(rotated, quality: 95));
}

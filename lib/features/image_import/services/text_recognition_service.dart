import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Wraps on-device ML Kit text recognition (Latin script) so screens and tests
/// do not touch the platform plugin directly.
class TextRecognitionService {
  const TextRecognitionService();

  /// Recognizes text in the image file at [imagePath].
  ///
  /// The file is read as is; it is never resized or modified. The recognizer
  /// is closed only after native processing has finished.
  Future<String> recognizeText(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    var processingFailed = false;
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      if (kDebugMode) _logLayout(result);
      return result.text;
    } catch (_) {
      processingFailed = true;
      rethrow;
    } finally {
      try {
        await recognizer.close();
      } catch (_) {
        // A close failure must not replace the original processing error.
        if (!processingFailed) rethrow;
      }
    }
  }

  /// Debug-only layout diagnostic: indices and bounding boxes, never the
  /// recognized text. Not compiled into release behavior (kDebugMode is a
  /// constant false there).
  void _logLayout(RecognizedText result) {
    debugPrint('[OCR layout] blocks=${result.blocks.length}');
    for (var b = 0; b < result.blocks.length; b++) {
      final block = result.blocks[b];
      debugPrint(
        '[OCR layout] block $b lines=${block.lines.length} '
        'box=${_box(block.boundingBox)}',
      );
      for (var l = 0; l < block.lines.length; l++) {
        final line = block.lines[l];
        debugPrint(
          '[OCR layout]   line $b.$l chars=${line.text.length} '
          'box=${_box(line.boundingBox)} angle=${line.angle}',
        );
      }
    }
  }

  String _box(Rect r) =>
      'L${r.left.round()} T${r.top.round()} R${r.right.round()} '
      'B${r.bottom.round()}';
}

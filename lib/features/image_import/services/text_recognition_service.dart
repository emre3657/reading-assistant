import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_result.dart';

/// Wraps on-device ML Kit text recognition (Latin script) so screens and tests
/// do not touch the platform plugin directly.
class TextRecognitionService {
  const TextRecognitionService();

  /// Recognizes text in the image file at [imagePath].
  ///
  /// The file is read as is; it is never resized or modified. The recognizer
  /// is closed only after native processing has finished. Lines keep the
  /// native reading order; they are never re-sorted by position.
  Future<OcrResult> recognizeText(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    var processingFailed = false;
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      if (kDebugMode) _logLayout(result);
      return _toOcrResult(result);
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

  OcrResult _toOcrResult(RecognizedText result) {
    final lines = <OcrLine>[];
    for (var b = 0; b < result.blocks.length; b++) {
      for (final line in result.blocks[b].lines) {
        final box = line.boundingBox;
        lines.add(
          OcrLine(
            text: line.text,
            blockIndex: b,
            left: box.left,
            top: box.top,
            right: box.right,
            bottom: box.bottom,
          ),
        );
      }
    }
    return OcrResult(result.text, lines: lines);
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

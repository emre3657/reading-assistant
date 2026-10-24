/// One recognized text line with its position in the OCR image, in pixels.
///
/// Plain data so the UI and the formatter do not depend on the ML Kit types.
class OcrLine {
  const OcrLine({
    required this.text,
    required this.blockIndex,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;

  /// Index of the native OCR block the line belongs to (reading order).
  final int blockIndex;
  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// Unmodified OCR text plus the lines it was built from, in native reading
/// order. [lines] is empty when no layout is available.
class OcrResult {
  const OcrResult(this.text, {this.lines = const []});

  final String text;
  final List<OcrLine> lines;
}

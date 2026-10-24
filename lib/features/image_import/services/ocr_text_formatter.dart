import 'ocr_result.dart';

/// Turns printed line breaks in OCR output into reading text.
///
/// Heuristic, not exact:
/// - CRLF/CR/LF are treated alike.
/// - Blank lines separate paragraphs and are kept as one blank line. If OCR
///   already lost a paragraph boundary, it cannot be restored here.
/// - A single line break becomes a space, except before a line that starts
///   with a list marker (`-`, `•`, `*`, `–`, `1.`, `2)`), which stays on its
///   own line.
/// - A line ending with letter + hyphen followed by a line starting with a
///   lowercase letter is joined as one word without the hyphen. A real
///   hyphenated word split at the line end (for example "sosyo-\nekonomik")
///   is also joined; the two cases cannot always be told apart.
/// - Hyphens inside lines, list markers and punctuation are left alone, and
///   no characters are changed or guessed.
String joinOcrLines(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final paragraphs = normalized
      .split(RegExp(r'\n(?:[ \t]*\n)+'))
      .map(_joinParagraph)
      .where((paragraph) => paragraph.isNotEmpty);
  return paragraphs.join('\n\n');
}

/// Turns printed line breaks into reading text, using line positions to keep
/// paragraph and heading boundaries when the layout allows it.
///
/// Heuristic, never exact. Falls back to [joinOcrLines] on the raw text when
/// the layout is missing, too small, inconsistent with the text, or when the
/// text already contains blank lines. Lines keep their native reading order;
/// no text is removed, reordered or corrected. All thresholds are ratios of
/// the local column width (median left/right edge of the neighbouring lines),
/// never pixel constants, so image scale does not matter. Native OCR blocks
/// are not treated as paragraphs; vertical gaps, line angle and character
/// counts are not used (unreliable on skewed photos).
///
/// A paragraph break is inserted before a line when:
/// - it has a clear first-line indent (at least 3% of the column width right
///   of the local left edge) and the previous line ends a sentence or is
///   clearly short (at least 12% shorter than the local right edge). The
///   previous line must not end with a letter + hyphen; and
/// - it is a likely heading: a lone single-line block, at most 60% of the
///   column wide, centered on the column (within 8%), without a sentence end.
///   A break is also inserted after a heading. A heading is not a
///   continuation of a hyphen-split word.
/// Hyphen joining and list markers behave as in [joinOcrLines] within a
/// paragraph; no word is joined across a paragraph or heading break.
String joinOcrResult(OcrResult result) {
  final fallback = joinOcrLines(result.text);
  final lines = result.lines
      .where((line) => line.text.trim().isNotEmpty)
      .toList();
  if (lines.length < _minLayoutLines || !_layoutMatchesText(result, lines)) {
    return fallback;
  }

  final n = lines.length;
  final windowSize = n < _windowSize ? n : _windowSize;
  final blockLineCounts = <int, int>{};
  for (final line in lines) {
    blockLineCounts.update(line.blockIndex, (c) => c + 1, ifAbsent: () => 1);
  }
  final texts = [for (final line in lines) line.text.trim()];

  // Local column measures per line; null when no reliable column exists.
  final columns = <_Column?>[
    for (var i = 0; i < n; i++)
      _columnAround(
        lines,
        (i - _windowSize ~/ 2).clamp(0, n - windowSize),
        windowSize,
      ),
  ];

  bool isHeading(int i) {
    final column = columns[i];
    if (column == null) return false;
    final line = lines[i];
    final text = texts[i];
    if (blockLineCounts[line.blockIndex] != 1) return false;
    if (line.right - line.left > _headingMaxWidth * column.width) return false;
    final center = (line.left + line.right) / 2;
    if ((center - column.center).abs() >
        _headingCenterTolerance * column.width) {
      return false;
    }
    if (_endsSentence.hasMatch(text)) return false;
    final continuesSplitWord =
        i > 0 &&
        _endsWithSplitWord.hasMatch(texts[i - 1]) &&
        _startsLowercase.hasMatch(text);
    return !continuesSplitWord;
  }

  bool startsIndentedParagraph(int i) {
    final column = columns[i];
    if (i == 0 || column == null) return false;
    final previous = texts[i - 1];
    if (_endsWithSplitWord.hasMatch(previous)) return false;
    if (lines[i].left - column.left < _indentMin * column.width) return false;
    final previousIsShort =
        lines[i - 1].right <= column.right - _shortLineMin * column.width;
    return _endsSentence.hasMatch(previous) || previousIsShort;
  }

  final headings = [for (var i = 0; i < n; i++) isHeading(i)];
  final paragraphs = <List<String>>[];
  for (var i = 0; i < n; i++) {
    final startsNew =
        i == 0 || headings[i] || headings[i - 1] || startsIndentedParagraph(i);
    if (startsNew) paragraphs.add([]);
    paragraphs.last.add(texts[i]);
  }
  return paragraphs.map(_joinLineTexts).join('\n\n');
}

const _minLayoutLines = 6;
const _windowSize = 7;
const _indentMin = 0.03;
const _shortLineMin = 0.12;
const _headingMaxWidth = 0.6;
const _headingCenterTolerance = 0.08;

final _endsSentence = RegExp('[.!?…]["\'”»’)\\]]*\$');

class _Column {
  const _Column(this.left, this.right);

  final double left;
  final double right;

  double get width => right - left;
  double get center => (left + right) / 2;
}

/// Median left/right edge of the [size] lines starting at [start]. Null when
/// the lines do not look like a text column (fewer than half are about full
/// width), for example poetry or scattered fragments.
_Column? _columnAround(List<OcrLine> lines, int start, int size) {
  final window = lines.sublist(start, start + size);
  final column = _Column(
    _median([for (final line in window) line.left]),
    _median([for (final line in window) line.right]),
  );
  if (column.width <= 0) return null;
  final wide = window
      .where((line) => line.right - line.left >= 0.8 * column.width)
      .length;
  return wide * 2 >= size ? column : null;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// The layout is used only when it describes exactly the raw text (ignoring
/// whitespace), has valid boxes, and the text has no blank-line paragraphs
/// of its own (those are handled by [joinOcrLines]).
bool _layoutMatchesText(OcrResult result, List<OcrLine> lines) {
  final normalized = result.text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  if (RegExp(r'\n[ \t]*\n').hasMatch(normalized.trim())) return false;
  for (final line in lines) {
    final values = [line.left, line.top, line.right, line.bottom];
    if (values.any((v) => !v.isFinite) ||
        line.right <= line.left ||
        line.bottom <= line.top) {
      return false;
    }
  }
  String strip(String s) => s.replaceAll(RegExp(r'\s+'), '');
  return strip(result.text) == strip(lines.map((l) => l.text).join());
}

final _endsWithSplitWord = RegExp(r'\p{L}[-\u00AD\u2010]$', unicode: true);
final _startsLowercase = RegExp(r'^\p{Ll}', unicode: true);
final _startsListItem = RegExp(r'^(?:[-•*–]|\d+[.)])\s');

String _joinParagraph(String paragraph) {
  return _joinLineTexts(paragraph.split('\n'));
}

String _joinLineTexts(Iterable<String> rawLines) {
  final lines = rawLines
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);
  final buffer = StringBuffer();
  String? previous;
  for (final line in lines) {
    if (previous == null) {
      buffer.write(line);
    } else if (_endsWithSplitWord.hasMatch(previous) &&
        _startsLowercase.hasMatch(line)) {
      final text = buffer.toString();
      buffer
        ..clear()
        ..write(text.substring(0, text.length - 1))
        ..write(line);
    } else if (_startsListItem.hasMatch(line)) {
      buffer
        ..write('\n')
        ..write(line);
    } else {
      buffer
        ..write(' ')
        ..write(line);
    }
    previous = line;
  }
  return buffer.toString();
}

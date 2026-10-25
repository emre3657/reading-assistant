/// A sentence as a range of the source text: `text.substring(start, end)`.
///
/// The ranges are consecutive and cover the whole text, so nothing is dropped
/// or rewritten. Whitespace after a sentence belongs to that sentence.
class SentenceSpan {
  const SentenceSpan(this.start, this.end);

  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is SentenceSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'SentenceSpan($start, $end)';
}

/// Splits [text] into sentences with simple Turkish-friendly rules. This is a
/// heuristic, not language analysis; some boundaries will be wrong.
///
/// A boundary follows `.` `!` `?` `…` (and runs of them) plus closing quotes
/// or brackets when whitespace comes next, and after a blank line (paragraph).
/// A boundary is skipped when the next text starts with a lowercase letter, or
/// for a single period after a number ("5. sınıf"), an initial ("M. Kemal"),
/// a dotted abbreviation ("a.ş.") or a common abbreviation ("Dr.", "Prof.").
/// Decimal numbers never split because no whitespace follows their separator.
/// A single line break does not split: printed lines often wrap mid-sentence.
List<SentenceSpan> splitSentences(String text) {
  final spans = <SentenceSpan>[];
  final length = text.length;
  var start = 0;
  var i = 0;

  bool hasContent(int end) => text.substring(start, end).trim().isNotEmpty;

  while (i < length) {
    final unit = text.codeUnitAt(i);

    if (_isTerminator(unit)) {
      var runEnd = i + 1;
      while (runEnd < length && _isTerminator(text.codeUnitAt(runEnd))) {
        runEnd++;
      }
      var afterClosers = runEnd;
      while (afterClosers < length &&
          _isCloser(text.codeUnitAt(afterClosers))) {
        afterClosers++;
      }
      if (afterClosers < length &&
          !_isWhitespace(text.codeUnitAt(afterClosers))) {
        i = afterClosers;
        continue;
      }
      var next = afterClosers;
      var newlines = 0;
      while (next < length && _isWhitespace(text.codeUnitAt(next))) {
        if (text.codeUnitAt(next) == 0x0A) newlines++;
        next++;
      }
      if (next >= length) break;
      if (hasContent(i) &&
          (newlines >= 2 || _isBoundary(text, i, runEnd, next))) {
        spans.add(SentenceSpan(start, next));
        start = next;
      }
      i = next;
      continue;
    }

    if (_isWhitespace(unit)) {
      var next = i;
      var newlines = 0;
      while (next < length && _isWhitespace(text.codeUnitAt(next))) {
        if (text.codeUnitAt(next) == 0x0A) newlines++;
        next++;
      }
      if (newlines >= 2 && next < length && hasContent(i)) {
        spans.add(SentenceSpan(start, next));
        start = next;
      }
      i = next;
      continue;
    }

    i++;
  }

  if (start < length) spans.add(SentenceSpan(start, length));
  return spans;
}

bool _isBoundary(String text, int punctuationStart, int runEnd, int next) {
  final nextLetter = _firstLetterAfter(text, next);
  if (nextLetter != null && _isLower(nextLetter)) return false;

  final isSinglePeriod =
      runEnd - punctuationStart == 1 &&
      text.codeUnitAt(punctuationStart) == 0x2E;
  if (!isSinglePeriod) return true;

  var tokenStart = punctuationStart;
  while (tokenStart > 0 && !_isWhitespace(text.codeUnitAt(tokenStart - 1))) {
    tokenStart--;
  }
  while (tokenStart < punctuationStart &&
      _isOpener(text.codeUnitAt(tokenStart))) {
    tokenStart++;
  }
  final token = text.substring(tokenStart, punctuationStart);
  if (token.isEmpty) return true;
  if (_isAllDigits(token)) return false;

  final lower = token.toLowerCase();
  if (_nonBreakingAbbreviations.contains(lower)) return false;
  if (_sentenceFinalAbbreviations.contains(lower)) {
    return nextLetter != null && _isUpper(nextLetter);
  }
  if (token.length == 1 && _isUpper(token)) return false;
  if (token.contains('.')) {
    final parts = token.split('.');
    if (parts.every((p) => p.isNotEmpty && p.length <= 2)) return false;
  }
  return true;
}

/// Abbreviations that are almost never the end of a sentence.
const _nonBreakingAbbreviations = {
  'dr',
  'prof',
  'doç',
  'yrd',
  'öğr',
  'gör',
  'uzm',
  'sn',
  'av',
  'müh',
  'bkz',
  'no',
  'tel',
  'cad',
  'sok',
  'mah',
  'apt',
  'mr',
  'mrs',
  'ms',
  'st',
};

/// Abbreviations that may end a sentence; split only before a capital letter.
const _sentenceFinalAbbreviations = {
  'vb',
  'vs',
  'vd',
  'örn',
  'yy',
  'krş',
  'ör',
};

String? _firstLetterAfter(String text, int from) {
  for (var i = from; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (_isOpener(unit)) continue;
    final char = text[i];
    final isLetter = char.toLowerCase() != char.toUpperCase();
    return isLetter ? char : null;
  }
  return null;
}

bool _isLower(String char) =>
    char == char.toLowerCase() && char != char.toUpperCase();

bool _isUpper(String char) =>
    char == char.toUpperCase() && char != char.toLowerCase();

bool _isAllDigits(String text) =>
    text.codeUnits.every((u) => u >= 0x30 && u <= 0x39);

bool _isTerminator(int unit) =>
    unit == 0x2E || unit == 0x21 || unit == 0x3F || unit == 0x2026;

bool _isWhitespace(int unit) =>
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0A ||
    unit == 0x0D ||
    unit == 0xA0;

// ' " ) ] } » ’ ”
bool _isCloser(int unit) =>
    unit == 0x27 ||
    unit == 0x22 ||
    unit == 0x29 ||
    unit == 0x5D ||
    unit == 0x7D ||
    unit == 0xBB ||
    unit == 0x2019 ||
    unit == 0x201D;

// ' " ( [ { « ‘ “
bool _isOpener(int unit) =>
    unit == 0x27 ||
    unit == 0x22 ||
    unit == 0x28 ||
    unit == 0x5B ||
    unit == 0x7B ||
    unit == 0xAB ||
    unit == 0x2018 ||
    unit == 0x201C;

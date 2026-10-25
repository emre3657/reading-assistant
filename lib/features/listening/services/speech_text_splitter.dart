/// Splits [text] into consecutive pieces of at most [maxLength] UTF-16 code
/// units. Joining the result gives back exactly [text]: nothing is trimmed,
/// dropped or reordered.
///
/// Cut points, in order of preference: after a line break, after a sentence
/// end followed by whitespace, after whitespace. Without any of these in the
/// window the text is cut at [maxLength], but never between the two halves of
/// a surrogate pair. Combining marks are not treated specially, so a hard cut
/// can separate a base letter from its accent (only for very long words).
List<String> splitSpeechText(String text, {required int maxLength}) {
  if (maxLength < 2) {
    throw ArgumentError.value(maxLength, 'maxLength', 'must be at least 2');
  }
  final chunks = <String>[];
  var start = 0;
  while (start < text.length) {
    if (text.length - start <= maxLength) {
      chunks.add(text.substring(start));
      break;
    }
    final end = _findCut(text, start, start + maxLength);
    chunks.add(text.substring(start, end));
    start = end;
  }
  return chunks;
}

int _findCut(String text, int start, int limit) {
  // Very short pieces make the speech choppy, so early boundaries are skipped.
  final minEnd = start + (limit - start) ~/ 4;

  for (var end = limit; end > minEnd; end--) {
    if (text.codeUnitAt(end - 1) == 0x0A) return end;
  }
  for (var end = limit; end > minEnd; end--) {
    if (end < text.length &&
        _isSentenceEnd(text.codeUnitAt(end - 1)) &&
        _isWhitespace(text.codeUnitAt(end))) {
      return end;
    }
  }
  for (var end = limit; end > minEnd; end--) {
    if (_isWhitespace(text.codeUnitAt(end - 1))) return end;
  }

  final isSplitPair = _isHighSurrogate(text.codeUnitAt(limit - 1));
  return isSplitPair ? limit - 1 : limit;
}

bool _isSentenceEnd(int unit) =>
    unit == 0x2E || unit == 0x21 || unit == 0x3F || unit == 0x2026;

bool _isWhitespace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

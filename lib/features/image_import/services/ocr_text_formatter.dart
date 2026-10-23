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

final _endsWithSplitWord = RegExp(r'\p{L}[-\u00AD\u2010]$', unicode: true);
final _startsLowercase = RegExp(r'^\p{Ll}', unicode: true);
final _startsListItem = RegExp(r'^(?:[-•*–]|\d+[.)])\s');

String _joinParagraph(String paragraph) {
  final lines = paragraph
      .split('\n')
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

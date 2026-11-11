import 'package:flutter/material.dart';

import '../services/sentence_splitter.dart';
import 'listening_controller.dart';

TextSpan sentenceHighlightSpan({
  required BuildContext context,
  required String text,
  required TextStyle? style,
  required SentenceSpan? sentence,
  SentenceSpan? word,
  SentenceSpan? selectedSentence,
  bool neutralReading = false,
  TextRange? composing,
}) {
  (int, int)? contentRange(SentenceSpan? span) {
    if (span == null ||
        span.start < 0 ||
        span.end > text.length ||
        span.start >= span.end) {
      return null;
    }
    final content = text.substring(span.start, span.end);
    final start = span.start + content.length - content.trimLeft().length;
    final end = span.start + content.trimRight().length;
    return start < end ? (start, end) : null;
  }

  final highlight = contentRange(sentence);
  final spokenWord = contentRange(word);
  final selected = contentRange(selectedSentence);
  if (highlight == null && selected == null) {
    return TextSpan(text: text, style: style);
  }
  final scheme = Theme.of(context).colorScheme;
  final readingColor = (neutralReading ? scheme.onSurface : scheme.primary)
      .withValues(alpha: 0.12);
  final selectionColor = scheme.primary.withValues(alpha: 0.18);
  final wordColor = Colors.amber.withValues(alpha: 0.24);
  final boundaries = <int>{
    0,
    text.length,
    if (highlight != null) ...[highlight.$1, highlight.$2],
    if (spokenWord != null) ...[spokenWord.$1, spokenWord.$2],
    if (selected != null) ...[selected.$1, selected.$2],
  };
  if (composing != null &&
      composing.isValid &&
      composing.isNormalized &&
      composing.end <= text.length) {
    boundaries.add(composing.start);
    boundaries.add(composing.end);
  }
  final points = boundaries.toList()..sort();
  return TextSpan(
    style: style,
    children: [
      for (var i = 0; i < points.length - 1; i++)
        TextSpan(
          text: text.substring(points[i], points[i + 1]),
          style: TextStyle(
            backgroundColor:
                spokenWord != null &&
                    highlight != null &&
                    points[i] >= spokenWord.$1 &&
                    points[i + 1] <= spokenWord.$2 &&
                    points[i] >= highlight.$1 &&
                    points[i + 1] <= highlight.$2
                ? wordColor
                : highlight != null &&
                      points[i] >= highlight.$1 &&
                      points[i + 1] <= highlight.$2
                ? readingColor
                : selected != null &&
                      points[i] >= selected.$1 &&
                      points[i + 1] <= selected.$2
                ? selectionColor
                : null,
            decoration:
                composing != null &&
                    points[i] >= composing.start &&
                    points[i + 1] <= composing.end
                ? TextDecoration.underline
                : null,
          ),
        ),
    ],
  );
}

class HighlightingTextEditingController extends TextEditingController {
  HighlightingTextEditingController({this.neutralReading = false});

  final bool neutralReading;
  ListeningController? _listening;
  SentenceSpan? _lastSentence;
  SentenceSpan? _selectedSentence;
  String? _selectedText;

  void selectSentence(SentenceSpan? sentence) {
    if (_selectedSentence == sentence && _selectedText == text) return;
    _selectedSentence = sentence;
    _selectedText = sentence == null ? null : text;
    notifyListeners();
  }

  void attachListening(ListeningController listening) {
    if (_listening == listening) return;
    _listening?.removeListener(_onListeningChanged);
    _listening?.wordProgress.removeListener(_onWordChanged);
    _listening = listening;
    _lastSentence = listening.sentenceForText(text);
    listening.addListener(_onListeningChanged);
    listening.wordProgress.addListener(_onWordChanged);
  }

  void _onWordChanged() => notifyListeners();

  void _onListeningChanged() {
    final sentence = _listening?.sentenceForText(text);
    if (sentence == _lastSentence) return;
    _lastSentence = sentence;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final sentence = _listening?.sentenceForText(text);
    final selected = _selectedText == text ? _selectedSentence : null;
    if (sentence == null && selected == null) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return sentenceHighlightSpan(
      context: context,
      text: text,
      style: style,
      sentence: sentence,
      word: _listening?.wordForText(text),
      selectedSentence: selected,
      neutralReading: neutralReading,
      composing: withComposing && value.isComposingRangeValid
          ? value.composing
          : null,
    );
  }

  @override
  void dispose() {
    _listening?.removeListener(_onListeningChanged);
    _listening?.wordProgress.removeListener(_onWordChanged);
    super.dispose();
  }
}

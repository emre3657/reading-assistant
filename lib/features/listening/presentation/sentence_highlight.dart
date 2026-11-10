import 'package:flutter/material.dart';

import '../services/sentence_splitter.dart';
import 'listening_controller.dart';

TextSpan sentenceHighlightSpan({
  required BuildContext context,
  required String text,
  required TextStyle? style,
  required SentenceSpan? sentence,
  TextRange? composing,
}) {
  if (sentence == null ||
      sentence.start < 0 ||
      sentence.end > text.length ||
      sentence.start >= sentence.end) {
    return TextSpan(text: text, style: style);
  }

  final start = sentence.start;
  final end = sentence.end;
  final highlighted = text.substring(start, end);
  final leading = highlighted.length - highlighted.trimLeft().length;
  final trailing = highlighted.trimRight().length;
  if (leading >= trailing) return TextSpan(text: text, style: style);
  final highlightStart = start + leading;
  final highlightEnd = start + trailing;
  final color = Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);
  final boundaries = <int>{0, highlightStart, highlightEnd, text.length};
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
                points[i] >= highlightStart && points[i + 1] <= highlightEnd
                ? color
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
  ListeningController? _listening;
  SentenceSpan? _lastSentence;

  void attachListening(ListeningController listening) {
    if (_listening == listening) return;
    _listening?.removeListener(_onListeningChanged);
    _listening = listening;
    _lastSentence = listening.sentenceForText(text);
    listening.addListener(_onListeningChanged);
  }

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
    if (sentence == null) {
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
      composing: withComposing && value.isComposingRangeValid
          ? value.composing
          : null,
    );
  }

  @override
  void dispose() {
    _listening?.removeListener(_onListeningChanged);
    super.dispose();
  }
}

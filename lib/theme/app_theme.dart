import 'package:material_ui/material_ui.dart';

enum AppPalette {
  turquoise('Turkuaz', Color(0xff007e80)),
  blue('Mavi', Color(0xff315da8)),
  purple('Mor', Color(0xff7252a3)),
  green('Yeşil', Color(0xff397444));

  const AppPalette(this.label, this.seed);
  final String label;
  final Color seed;
}

@immutable
class ReadingColors extends ThemeExtension<ReadingColors> {
  const ReadingColors({
    required this.bookPaper,
    required this.bookText,
    required this.sentenceHighlight,
    required this.neutralHighlight,
    required this.selectedSentence,
    required this.wordHighlight,
  });

  final Color bookPaper;
  final Color bookText;
  final Color sentenceHighlight;
  final Color neutralHighlight;
  final Color selectedSentence;
  final Color wordHighlight;

  factory ReadingColors.fromScheme(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return ReadingColors(
      bookPaper: dark ? const Color(0xff302b25) : const Color(0xfffff9ec),
      bookText: dark ? const Color(0xfff5eadc) : const Color(0xff201b15),
      sentenceHighlight: scheme.primary.withValues(alpha: 0.12),
      neutralHighlight: scheme.onSurface.withValues(alpha: 0.12),
      selectedSentence: scheme.primary.withValues(alpha: 0.18),
      wordHighlight: (dark ? const Color(0xffffca75) : const Color(0xffffc107))
          .withValues(alpha: 0.24),
    );
  }

  static ReadingColors of(BuildContext context) =>
      Theme.of(context).extension<ReadingColors>() ??
      ReadingColors.fromScheme(Theme.of(context).colorScheme);

  @override
  ReadingColors copyWith({
    Color? bookPaper,
    Color? bookText,
    Color? sentenceHighlight,
    Color? neutralHighlight,
    Color? selectedSentence,
    Color? wordHighlight,
  }) => ReadingColors(
    bookPaper: bookPaper ?? this.bookPaper,
    bookText: bookText ?? this.bookText,
    sentenceHighlight: sentenceHighlight ?? this.sentenceHighlight,
    neutralHighlight: neutralHighlight ?? this.neutralHighlight,
    selectedSentence: selectedSentence ?? this.selectedSentence,
    wordHighlight: wordHighlight ?? this.wordHighlight,
  );

  @override
  ReadingColors lerp(ReadingColors? other, double t) {
    if (other == null) return this;
    return ReadingColors(
      bookPaper: Color.lerp(bookPaper, other.bookPaper, t)!,
      bookText: Color.lerp(bookText, other.bookText, t)!,
      sentenceHighlight: Color.lerp(
        sentenceHighlight,
        other.sentenceHighlight,
        t,
      )!,
      neutralHighlight: Color.lerp(
        neutralHighlight,
        other.neutralHighlight,
        t,
      )!,
      selectedSentence: Color.lerp(
        selectedSentence,
        other.selectedSentence,
        t,
      )!,
      wordHighlight: Color.lerp(wordHighlight, other.wordHighlight, t)!,
    );
  }
}

ThemeData appTheme(AppPalette palette, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.seed,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    extensions: [ReadingColors.fromScheme(scheme)],
  );
}

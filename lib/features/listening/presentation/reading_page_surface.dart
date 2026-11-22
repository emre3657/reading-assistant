import 'package:material_ui/material_ui.dart';

import '../../../theme/app_theme.dart';
import 'reading_preferences.dart';

Color readingPagePaperColor(BuildContext context, ReadingPageView view) {
  final theme = Theme.of(context);
  if (view == ReadingPageView.plain) return theme.scaffoldBackgroundColor;
  return ReadingColors.of(context).bookPaper;
}

class ReadingPageSurface extends StatelessWidget {
  const ReadingPageSurface({
    super.key,
    required this.view,
    required this.child,
  });

  final ReadingPageView view;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final book = view == ReadingPageView.book;
    final theme = Theme.of(context);
    final colors = ReadingColors.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: book ? 720 : double.infinity),
        child: Container(
          padding: book ? const EdgeInsets.all(12) : EdgeInsets.zero,
          decoration: book
              ? BoxDecoration(
                  color: readingPagePaperColor(context, view),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: book
              ? Theme(
                  data: theme.copyWith(
                    colorScheme: theme.colorScheme.copyWith(
                      onSurface: colors.bookText,
                    ),
                    textTheme: theme.textTheme.apply(
                      bodyColor: colors.bookText,
                      displayColor: colors.bookText,
                    ),
                  ),
                  child: child,
                )
              : child,
        ),
      ),
    );
  }
}

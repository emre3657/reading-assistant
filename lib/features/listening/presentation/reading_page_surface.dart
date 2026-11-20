import 'package:flutter/material.dart';

import 'reading_preferences.dart';

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
    final dark = theme.brightness == Brightness.dark;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: book ? 720 : double.infinity),
        child: Container(
          padding: book ? const EdgeInsets.all(12) : EdgeInsets.zero,
          decoration: book
              ? BoxDecoration(
                  color: dark
                      ? const Color(0xff302b25)
                      : const Color(0xfffff9ec),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: child,
        ),
      ),
    );
  }
}

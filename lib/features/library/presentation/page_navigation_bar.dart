import 'package:flutter/material.dart';

/// Compact page navigation row shown above the listening panel. It is visually
/// and semantically separate from the sentence controls. It only reports
/// taps; the screen decides when a move is allowed.
class PageNavigationBar extends StatelessWidget {
  const PageNavigationBar({
    super.key,
    required this.current,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  /// 1-based number of the open page.
  final int current;
  final int total;

  /// Null disables the control (first/last page or a move in progress).
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indicator = Text(
      'Sayfa $current / $total',
      key: const ValueKey('page-indicator'),
      style: theme.textTheme.titleSmall,
    );

    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Sayfa gezinme',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: total <= 1
              ? ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(heightFactor: 1, child: indicator),
                )
              : Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('previous-page'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: onPrevious,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Önceki sayfa'),
                    ),
                    Semantics(liveRegion: true, child: indicator),
                    TextButton.icon(
                      key: const ValueKey('next-page'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: onNext,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Sonraki sayfa'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

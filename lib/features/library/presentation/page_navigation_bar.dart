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
    required this.onGoToPage,
  });

  /// 1-based number of the open page.
  final int current;
  final int total;

  /// Null disables the control (first/last page or a move in progress).
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onGoToPage;

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
              : Row(
                  children: [
                    IconButton(
                      key: const ValueKey('previous-page'),
                      tooltip: 'Önceki sayfa',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: onPrevious,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Center(
                        heightFactor: 1,
                        child: Semantics(
                          label: 'Sayfaya git. Sayfa $current / $total',
                          button: true,
                          enabled: onGoToPage != null,
                          onTap: onGoToPage,
                          liveRegion: true,
                          excludeSemantics: true,
                          child: TextButton(
                            key: const ValueKey('go-to-page'),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            onPressed: onGoToPage,
                            child: indicator,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('next-page'),
                      tooltip: 'Sonraki sayfa',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: onNext,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

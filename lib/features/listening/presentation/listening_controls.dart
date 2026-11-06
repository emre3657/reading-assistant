import 'package:flutter/material.dart';

import 'listening_controller.dart';

class ListeningControls extends StatelessWidget {
  const ListeningControls({
    super.key,
    required this.listening,
    required this.canStart,
    required this.onStart,
    required this.expanded,
    required this.onToggleExpanded,
    this.nextPagePending = false,
    this.onCancelNextPage,
  });

  final ListeningController listening;
  final bool canStart;
  final VoidCallback onStart;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final bool nextPagePending;
  final VoidCallback? onCancelNextPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = listening.status;
    final message = nextPagePending
        ? 'Sonraki sayfa açılıyor…'
        : switch (status) {
            ListeningStatus.starting => 'Okuma hazırlanıyor…',
            ListeningStatus.speaking => 'Okunuyor…',
            ListeningStatus.paused => 'Duraklatıldı.',
            ListeningStatus.stopping => 'Durduruluyor…',
            _ => listening.message,
          };

    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(child: Divider(indent: 16, endIndent: 8)),
                  Semantics(
                    expanded: expanded,
                    child: IconButton(
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      tooltip: expanded ? 'Paneli küçült' : 'Paneli genişlet',
                      onPressed: onToggleExpanded,
                      icon: Icon(
                        expanded ? Icons.expand_more : Icons.expand_less,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(indent: 8, endIndent: 16)),
                ],
              ),
              Semantics(
                container: true,
                label: 'Oynatma kontrolleri',
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (listening.canResume)
                      Semantics(
                        hint: 'Mevcut cümlenin başından okur.',
                        child: Tooltip(
                          message: 'Devam et, mevcut cümlenin başından okur.',
                          child: FilledButton.icon(
                            onPressed: listening.resume,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Devam et'),
                          ),
                        ),
                      )
                    else if (listening.canPause)
                      FilledButton.icon(
                        onPressed: listening.pause,
                        icon: const Icon(Icons.pause),
                        label: const Text('Duraklat'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: canStart ? onStart : null,
                        icon: const Icon(Icons.volume_up),
                        label: const Text('Sesli oku'),
                      ),
                    OutlinedButton.icon(
                      onPressed: nextPagePending
                          ? onCancelNextPage
                          : listening.canStop
                          ? listening.stop
                          : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Durdur'),
                    ),
                  ],
                ),
              ),
              if (expanded) ...[
                Semantics(
                  container: true,
                  label: 'Cümle gezinme kontrolleri',
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        onPressed: listening.canGoPrevious
                            ? listening.previousSentence
                            : null,
                        icon: const Icon(Icons.skip_previous),
                        label: const Text('Önceki cümle'),
                      ),
                      OutlinedButton.icon(
                        onPressed: listening.canGoNext
                            ? listening.nextSentence
                            : null,
                        icon: const Icon(Icons.skip_next),
                        label: const Text('Sonraki cümle'),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: listening.canRestart
                      ? listening.restartFromBeginning
                      : null,
                  icon: const Icon(Icons.first_page),
                  label: const Text('Başa dön'),
                ),
                if (listening.sentenceCount > 0)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Cümle ${listening.currentSentence} / '
                      '${listening.sentenceCount}',
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
              if (message != null &&
                  (expanded ||
                      nextPagePending ||
                      status == ListeningStatus.failed))
                Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: status == ListeningStatus.failed
                        ? TextStyle(color: theme.colorScheme.error)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps the bottom surface at its natural height unless it exceeds the
/// screen space available beneath the app bar.
class ListeningSurface extends StatelessWidget {
  const ListeningSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final available =
        (media.size.height -
                media.padding.top -
                media.viewInsets.bottom -
                kToolbarHeight -
                48)
            .clamp(0.0, double.infinity);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: available),
      child: SingleChildScrollView(
        primary: false,
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

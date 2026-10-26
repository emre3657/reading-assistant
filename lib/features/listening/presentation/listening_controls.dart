import 'package:flutter/material.dart';

import 'listening_controller.dart';

/// Fixed listening panel: a compact main row (play/pause/resume, stop, more),
/// a short position/speed line and a collapsible section with navigation and
/// speed choices. All logic stays in [ListeningController]; the screen decides when
/// the panel is shown and whether reading may start.
class ListeningControls extends StatelessWidget {
  const ListeningControls({
    super.key,
    required this.listening,
    required this.canStart,
    required this.onStart,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final ListeningController listening;

  /// Whether the secondary section is open; owned by the screen so it
  /// survives the panel being hidden (e.g. while the keyboard is open).
  final bool expanded;
  final VoidCallback onToggleExpanded;

  /// Whether "Sesli oku" is enabled (the screen knows about other busy flows).
  final bool canStart;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = listening.status;
    final message = listening.message;
    final statusText = switch (status) {
      ListeningStatus.starting => 'Okuma hazırlanıyor…',
      ListeningStatus.speaking => 'Okunuyor…',
      ListeningStatus.paused => 'Duraklatıldı.',
      ListeningStatus.stopping => 'Durduruluyor…',
      _ => null,
    };
    // A tall panel (large text, narrow screen) scrolls inside its own limit
    // instead of squeezing the text above it.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.45;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  container: true,
                  explicitChildNodes: true,
                  label: 'Oynatma kontrolleri',
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (listening.canResume)
                        FilledButton.icon(
                          onPressed: listening.resume,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Devam et'),
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
                        onPressed: listening.canStop ? listening.stop : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Durdur'),
                      ),
                      Semantics(
                        expanded: expanded,
                        child: OutlinedButton.icon(
                          onPressed: onToggleExpanded,
                          icon: Icon(
                            expanded ? Icons.expand_more : Icons.expand_less,
                          ),
                          label: const Text('Diğer kontroller'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16,
                    children: [
                      if (listening.sentenceCount > 0)
                        Text(
                          'Cümle ${listening.currentSentence} / '
                          '${listening.sentenceCount}',
                        ),
                      Text('Hız ${listening.speed.label}'),
                    ],
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    container: true,
                    explicitChildNodes: true,
                    label: 'Cümle gezinme kontrolleri',
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
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
                        OutlinedButton.icon(
                          onPressed: listening.canRestart
                              ? listening.restartFromBeginning
                              : null,
                          icon: const Icon(Icons.first_page),
                          label: const Text('Başa dön'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    container: true,
                    explicitChildNodes: true,
                    label: 'Okuma hızı',
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        const Text('Okuma hızı'),
                        for (final speed in ReadingSpeed.values)
                          ChoiceChip(
                            label: Text(speed.label),
                            tooltip: 'Okuma hızı ${speed.label}',
                            selected: listening.speed == speed,
                            onSelected: (_) => listening.setSpeed(speed),
                          ),
                      ],
                    ),
                  ),
                  if (listening.sentenceCount > 0)
                    Text(
                      'Devam et, mevcut cümlenin başından okur.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
                if (statusText != null || message != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      statusText ?? message!,
                      textAlign: TextAlign.center,
                      style: status == ListeningStatus.failed
                          ? TextStyle(color: theme.colorScheme.error)
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

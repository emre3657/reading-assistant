import 'package:flutter/material.dart';

import 'listening_controller.dart';
import 'reading_preferences.dart';

Future<void> showReadingSettings(
  BuildContext context, {
  required ReadingPreferences preferences,
  Listenable? pageChanges,
  bool Function()? showAutoNextPage,
  bool appearanceOnly = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: Listenable.merge([preferences, pageChanges]),
      builder: (context, _) => AlertDialog(
        scrollable: true,
        title: Text(appearanceOnly ? 'Görünüm' : 'Görünüm ve sesli okuma'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _settingsGroup(
              context,
              title: appearanceOnly ? null : 'Görünüm',
              icon: Icons.text_fields,
              children: [
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Yazı boyutu'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ReadingTextSize>(
                      key: const ValueKey('reading-text-size'),
                      value: preferences.textSize,
                      isExpanded: true,
                      items: [
                        for (final size in ReadingTextSize.values)
                          DropdownMenuItem(
                            value: size,
                            child: Text(size.label),
                          ),
                      ],
                      onChanged: preferences.ready
                          ? (size) {
                              if (size != null) preferences.setTextSize(size);
                            }
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Metin hizalaması',
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ReadingTextAlignment>(
                      key: const ValueKey('reading-text-alignment'),
                      value: preferences.textAlignment,
                      isExpanded: true,
                      items: [
                        for (final alignment in ReadingTextAlignment.values)
                          DropdownMenuItem(
                            value: alignment,
                            child: Text(alignment.label),
                          ),
                      ],
                      onChanged: preferences.ready
                          ? (alignment) {
                              if (alignment != null) {
                                preferences.setTextAlignment(alignment);
                              }
                            }
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            if (!appearanceOnly) ...[
              const SizedBox(height: 12),
              _settingsGroup(
                context,
                title: 'Sesli okuma',
                icon: Icons.volume_up_outlined,
                children: [
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Okuma hızı'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ReadingSpeed>(
                        key: const ValueKey('reading-speed'),
                        value: preferences.speed,
                        isExpanded: true,
                        items: [
                          for (final speed in ReadingSpeed.values)
                            DropdownMenuItem(
                              value: speed,
                              child: Text(speed.label),
                            ),
                        ],
                        onChanged: preferences.ready
                            ? (speed) {
                                if (speed != null) preferences.setSpeed(speed);
                              }
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const ValueKey('follow-sentence'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Okunan cümleyi takip et'),
                    value: preferences.followSentence,
                    onChanged: preferences.ready
                        ? preferences.setFollowSentence
                        : null,
                  ),
                  if (showAutoNextPage?.call() ?? false) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const ValueKey('auto-next-page'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sonraki sayfayı otomatik oku'),
                      value: preferences.autoNextPage,
                      onChanged: preferences.ready
                          ? preferences.setAutoNextPage
                          : null,
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    ),
  );
}

Widget _settingsGroup(
  BuildContext context, {
  required String? title,
  required IconData icon,
  required List<Widget> children,
}) {
  final theme = Theme.of(context);

  return DecoratedBox(
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Semantics(
              header: true,
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      icon,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    ),
  );
}

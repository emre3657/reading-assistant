import 'package:flutter/material.dart';

import 'listening_controller.dart';
import 'reading_preferences.dart';

Future<void> showReadingSettings(
  BuildContext context, {
  required ReadingPreferences preferences,
  Listenable? pageChanges,
  bool Function()? showAutoNextPage,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: Listenable.merge([preferences, pageChanges]),
      builder: (context, _) => AlertDialog(
        title: const Text('Okuma ayarları'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                SwitchListTile(
                  key: const ValueKey('auto-next-page'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sonraki sayfayı otomatik oku'),
                  subtitle: const Text(
                    'Sayfa bitince sonraki sayfadan okumaya devam eder.',
                  ),
                  value: preferences.autoNextPage,
                  onChanged: preferences.ready
                      ? preferences.setAutoNextPage
                      : null,
                ),
              ],
            ],
          ),
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

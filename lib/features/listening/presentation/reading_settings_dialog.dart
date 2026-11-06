import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'listening_controller.dart';

Future<void> showReadingSettings(
  BuildContext context, {
  required ListeningController listening,
  ValueListenable<bool>? autoNextPage,
  ValueChanged<bool>? onAutoNextPageChanged,
  Listenable? pageChanges,
  bool Function()? showAutoNextPage,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: Listenable.merge([listening, autoNextPage, pageChanges]),
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
                    value: listening.speed,
                    isExpanded: true,
                    items: [
                      for (final speed in ReadingSpeed.values)
                        DropdownMenuItem(
                          value: speed,
                          child: Text(speed.label),
                        ),
                    ],
                    onChanged: (speed) {
                      if (speed != null) listening.setSpeed(speed);
                    },
                  ),
                ),
              ),
              if (autoNextPage != null &&
                  onAutoNextPageChanged != null &&
                  (showAutoNextPage?.call() ?? false)) ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  key: const ValueKey('auto-next-page'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sonraki sayfayı otomatik oku'),
                  subtitle: const Text(
                    'Sayfa bitince sonraki sayfadan okumaya devam eder.',
                  ),
                  value: autoNextPage.value,
                  onChanged: onAutoNextPageChanged,
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

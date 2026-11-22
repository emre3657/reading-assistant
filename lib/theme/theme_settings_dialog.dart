import 'package:flutter/material.dart';

import '../features/listening/presentation/reading_preferences.dart';
import 'app_theme.dart';

Future<void> showThemeSettings(
  BuildContext context,
  ReadingPreferences preferences,
) => showDialog<void>(
  context: context,
  builder: (context) => AnimatedBuilder(
    animation: preferences,
    builder: (context, _) => AlertDialog(
      title: const Text('Tema'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Görünüm modu',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final (mode, label) in [
              (ThemeMode.system, 'Sistem'),
              (ThemeMode.light, 'Açık'),
              (ThemeMode.dark, 'Koyu'),
            ])
              ListTile(
                title: Text(label),
                selected: preferences.themeMode == mode,
                trailing: preferences.themeMode == mode
                    ? const Icon(Icons.check, semanticLabel: 'Seçili')
                    : null,
                onTap: () => preferences.setThemeMode(mode),
              ),
            Text('Renk paleti', style: Theme.of(context).textTheme.titleMedium),
            for (final palette in AppPalette.values)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: palette.seed,
                  radius: 16,
                ),
                title: Text(palette.label),
                selected: preferences.themePalette == palette,
                trailing: preferences.themePalette == palette
                    ? const Icon(Icons.check, semanticLabel: 'Seçili')
                    : null,
                onTap: () => preferences.setThemePalette(palette),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    ),
  ),
);

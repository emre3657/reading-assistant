import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/app.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';
import 'package:reading_assistant/theme/app_theme.dart';

import '../image_import/test_doubles.dart';
import 'fake_preferences_store.dart';
import 'fake_speech_service.dart';

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return ((first > second ? first : second) + 0.05) /
      ((first < second ? first : second) + 0.05);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('all palettes keep reading text and highlights legible', () {
    for (final palette in AppPalette.values) {
      for (final brightness in Brightness.values) {
        final theme = appTheme(palette, brightness);
        final colors = theme.extension<ReadingColors>()!;
        for (final (background, text) in [
          (theme.scaffoldBackgroundColor, theme.colorScheme.onSurface),
          (colors.bookPaper, colors.bookText),
        ]) {
          expect(_contrast(text, background), greaterThanOrEqualTo(4.5));
          for (final overlay in [
            colors.sentenceHighlight,
            colors.neutralHighlight,
            colors.selectedSentence,
            colors.wordHighlight,
          ]) {
            expect(
              _contrast(text, Color.alphaBlend(overlay, background)),
              greaterThanOrEqualTo(4.5),
              reason: '$palette $brightness $overlay',
            );
          }
        }
        expect(
          _contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(theme.colorScheme.onError, theme.colorScheme.error),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(
            theme.colorScheme.onSurfaceVariant,
            theme.colorScheme.surface,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(
            theme.colorScheme.onSurface,
            theme.colorScheme.surfaceContainerHigh,
          ),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  testWidgets('system follows device and explicit modes apply immediately', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ReadingAssistantApp(readingPreferences: preferences),
    );
    await tester.pumpAndSettle();
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness;
    expect(brightness(), Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    preferences.setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    preferences.setThemeMode(ThemeMode.system);
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    await tester.pumpWidget(const SizedBox.shrink());
    preferences.dispose();
  });

  testWidgets(
    'all palette selections apply and restoration updates the theme',
    (tester) async {
      final store = FakePreferencesStore();
      final preferences = ReadingPreferences(store: store);
      await preferences.load();
      await tester.pumpWidget(
        ReadingAssistantApp(readingPreferences: preferences),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('Diğer seçenekler'));
      await _tap(tester, find.text('Tema'));
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await _tap(
          tester,
          find.text(mode == ThemeMode.light ? 'Açık' : 'Koyu'),
        );
        for (final palette in AppPalette.values) {
          await _tap(tester, find.text(palette.label));
          final tile = tester.widget<ListTile>(
            find.ancestor(
              of: find.text(palette.label),
              matching: find.byType(ListTile),
            ),
          );
          expect(tile.selected, isTrue);
          final context = tester.element(find.byType(AlertDialog));
          expect(
            Theme.of(context).colorScheme.primary,
            appTheme(
              palette,
              mode == ThemeMode.light ? Brightness.light : Brightness.dark,
            ).colorScheme.primary,
          );
        }
      }
      await preferences.pendingWrites;
      final reopened = ReadingPreferences(store: store);
      await reopened.load();
      expect(reopened.themeMode, ThemeMode.dark);
      expect(reopened.themePalette, AppPalette.green);
      reopened.dispose();
      preferences.applyRestored({
        'theme_mode': 'light',
        'theme_palette': 'purple',
      });
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.primary,
        appTheme(AppPalette.purple, Brightness.light).colorScheme.primary,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      preferences.dispose();
    },
  );

  testWidgets(
    'theme dialog keeps draft and active speech while applying choices',
    (tester) async {
      final store = FakePreferencesStore();
      final preferences = ReadingPreferences(store: store);
      final speech = FakeSpeechService();
      await preferences.load();
      await tester.pumpWidget(
        ReadingAssistantApp(
          readingPreferences: preferences,
          pickerService: FakeImagePickerService(),
          speechService: speech,
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Metin yaz veya yapıştır'));
      final field = find.byKey(const ValueKey('import-text'));
      final text = List.filled(30, 'Bir cümle.').join('\n');
      await tester.enterText(field, text);
      final controller = tester.widget<TextField>(field).controller!;
      controller.selection = const TextSelection.collapsed(offset: 3);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Sesli oku'));
      expect(speech.isSpeaking, isTrue);
      await _tap(tester, find.byTooltip('Diğer seçenekler'));
      await _tap(tester, find.text('Tema'));
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('content-scroll')),
          )
          .controller!;
      final offset = scroll.offset;
      final selection = controller.selection;
      await _tap(tester, find.text('Koyu'));
      await _tap(tester, find.text('Mavi'));
      expect(preferences.themeMode, ThemeMode.dark);
      expect(preferences.themePalette, AppPalette.blue);
      expect(speech.isSpeaking, isTrue);
      expect(speech.spoken, hasLength(1));
      await _tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Kapat'),
        ),
      );
      expect(tester.widget<TextField>(field).controller, same(controller));
      expect(controller.text, text);
      expect(controller.selection, selection);
      expect(scroll.offset, offset);
      expect(Theme.of(tester.element(field)).brightness, Brightness.dark);
      await preferences.pendingWrites;
      expect(store.values!['theme_mode'], 'dark');
      expect(store.values!['theme_palette'], 'blue');
      await tester.pumpWidget(const SizedBox.shrink());
      preferences.dispose();
    },
  );

  testWidgets('theme dialog remains usable at large text size', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    await tester.pumpWidget(
      ReadingAssistantApp(readingPreferences: preferences),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Diğer seçenekler'));
    await _tap(tester, find.text('Tema'));
    await _tap(tester, find.text('Yeşil'));
    expect(preferences.themePalette, AppPalette.green);
    expect(find.text('Kapat').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    preferences.dispose();
  });

  testWidgets('initial screen waits for preferences and handles load failure', (
    tester,
  ) async {
    final store = FakePreferencesStore()
      ..loadGate = Completer<void>()
      ..loadError = StateError('failed');
    await tester.pumpWidget(ReadingAssistantApp(store: store));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Galeriden görsel seç'), findsNothing);
    store.loadGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Galeriden görsel seç'), findsOneWidget);
    expect(find.textContaining('tercihleri yüklenemedi'), findsOneWidget);
  });

  testWidgets('theme save failure is reported after closing the dialog', (
    tester,
  ) async {
    final store = FakePreferencesStore()..saveError = StateError('failed');
    final preferences = ReadingPreferences(store: store);
    await preferences.load();
    await tester.pumpWidget(
      ReadingAssistantApp(readingPreferences: preferences),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Diğer seçenekler'));
    await _tap(tester, find.text('Tema'));
    await _tap(tester, find.text('Koyu'));
    await preferences.pendingWrites;
    await _tap(tester, find.text('Kapat'));
    expect(
      find.textContaining('tercihleri kalıcı kaydedilemedi'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    preferences.dispose();
  });
}

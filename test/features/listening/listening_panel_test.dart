import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/app.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
import 'package:reading_assistant/features/listening/presentation/listening_controller.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';

import '../image_import/test_doubles.dart';
import 'fake_preferences_store.dart';
import 'fake_speech_service.dart';
import 'reader_controls_test_utils.dart';

// Fake engine and fake OCR: these tests cover layout and UI wiring only.
// Real speech speed and the scrolling feel need manual verification.
final _panel = find.byKey(const ValueKey('listening-panel'));
final _field = find.byType(TextField);
final _scroll = find.byKey(const ValueKey('content-scroll'));

class _Harness {
  _Harness(this.speech, this.results);
  final FakeSpeechService speech;
  final List<Object> results; // String result or an Exception to throw
  int calls = 0;
}

Future<_Harness> _open(
  WidgetTester tester,
  List<Object> results, {
  Size size = const Size(800, 2400),
  double textScale = 1,
  bool addingPage = false,
}) async {
  final harness = _Harness(FakeSpeechService(), results);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(tester.view.resetViewInsets);
  final preferences = ReadingPreferences(store: FakePreferencesStore());
  await tester.pumpWidget(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Builder(
          builder: (context) {
            final picker = FakeImagePickerService(
              onPick: () async => XFile('/tmp/a.jpg'),
            );
            final recognition = FakeTextRecognitionService((_) async {
              final r = harness.results[harness.calls++];
              if (r is String) return r;
              throw r;
            });
            if (addingPage) {
              return ReadingPreferencesScope(
                preferences: preferences,
                child: MaterialApp(
                  home: ImageImportScreen(
                    onSavePage: (_) async {},
                    pickerService: picker,
                    textRecognitionService: recognition,
                    previewImageBuilder: (file) => ControlledImageProvider(),
                    speechService: harness.speech,
                  ),
                ),
              );
            }
            return ReadingAssistantApp(
              readingPreferences: preferences,
              pickerService: picker,
              textRecognitionService: recognition,
              previewImageBuilder: (file) => ControlledImageProvider(),
              speechService: harness.speech,
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.ensureVisible(find.text('Galeriden görsel seç'));
  await tester.tap(find.text('Galeriden görsel seç'));
  await tester.pump();
  return harness;
}

Future<void> _extract(WidgetTester tester) async {
  final button = find.text('Metni çıkar');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

final _long = List.generate(
  80,
  (i) => 'Satır $i burada devam ediyor.',
).join(' ');

void main() {
  testWidgets('panel is hidden without text and visible with text', (
    tester,
  ) async {
    await _open(tester, ['Merhaba dünya.']);
    expect(_panel, findsNothing);
    await _extract(tester);
    expect(_panel, findsOneWidget);
  });

  for (final addingPage in [false, true]) {
    testWidgets(
      'compact controls preserve playback on rotation for ${addingPage ? 'added page' : 'home'}',
      (tester) async {
        final h = await _open(
          tester,
          ['Bir. İki.'],
          size: const Size(400, 800),
          textScale: 2,
          addingPage: addingPage,
        );
        await _extract(tester);
        final read = find.byTooltip('Sesli oku');
        expect(tester.getCenter(read).dx, closeTo(200, 1));
        expect(find.byTooltip('Paneli küçült'), findsNothing);
        await tapReadingControl(tester, 'Sesli oku');
        await tester.pumpAndSettle();
        await tapReadingControl(tester, 'Sonraki cümle');
        await tester.pumpAndSettle();
        expect(h.speech.spoken, ['Bir. ', 'İki.']);

        tester.view.physicalSize = const Size(720, 360);
        await tester.pumpAndSettle();
        expect(h.speech.isSpeaking, isTrue);
        expect(h.speech.spoken, hasLength(2));
        expect(
          tester.getCenter(find.byTooltip('Duraklat')).dx,
          closeTo(360, 1),
        );
        expect(tester.getSize(_panel).height, lessThanOrEqualTo(48));
        await tapReadingControl(tester, 'Duraklat');
        await tester.pumpAndSettle();
        expect(find.text('Duraklatıldı.'), findsNothing);
        tester.view.physicalSize = const Size(400, 800);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Devam et'), findsOneWidget);
        await tapReadingControl(tester, 'Devam et');
        await tester.pumpAndSettle();
        expect(h.speech.spoken.last, 'İki.');
        await tapReadingControl(tester, 'Başa dön');
        await tester.pumpAndSettle();
        expect(h.speech.spoken.last, 'Bir. ');
        await tapReadingControl(tester, 'Durdur');
        await tester.pumpAndSettle();
        expect(h.speech.isSpeaking, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'speech errors remain visible for ${addingPage ? 'added page' : 'home'}',
      (tester) async {
        final h = await _open(tester, ['Bir.'], addingPage: addingPage);
        await _extract(tester);
        await tapReadingControl(tester, 'Sesli oku');
        await tester.pumpAndSettle();
        h.speech.failCurrent();
        await tester.pump();
        await tester.pump();
        expect(
          find.text(
            'Sesli okuma sırasında bir hata oluştu. Tekrar deneyebilirsin.',
          ),
          findsOneWidget,
        );
        expect(find.byTooltip('Sesli oku'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('panel does not cover the end of the text', (tester) async {
    await _open(tester, [_long], size: const Size(400, 600));
    await _extract(tester);

    final position = tester
        .state<ScrollableState>(
          find.descendant(of: _scroll, matching: find.byType(Scrollable)).first,
        )
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    final panelTop = tester.getTopLeft(_panel).dy;
    final bodyBottom = tester.getBottomLeft(_scroll).dy;
    expect(bodyBottom, lessThanOrEqualTo(panelTop + 0.5));
    expect(tester.getBottomLeft(_field).dy, lessThanOrEqualTo(panelTop + 0.5));
  });

  testWidgets('panel hides while the keyboard is open and returns after', (
    tester,
  ) async {
    await _open(tester, ['Merhaba dünya.']);
    await _extract(tester);
    expect(_panel, findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_panel, findsNothing);

    tester.view.resetViewInsets();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_panel, findsOneWidget);
  });

  testWidgets(
    'hiding closes interaction and semantics at once, then animates',
    (tester) async {
      await _open(tester, ['Merhaba dünya.']);
      await _extract(tester);
      final guard = find.byKey(const ValueKey('listening-panel-guard'));
      expect(tester.widget<IgnorePointer>(guard).ignoring, isFalse);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Still animating (built), but already not interactive.
      expect(_panel, findsOneWidget);
      expect(tester.widget<IgnorePointer>(guard).ignoring, isTrue);
      expect(
        tester
            .widget<ExcludeSemantics>(
              find
                  .descendant(
                    of: guard,
                    matching: find.byType(ExcludeSemantics),
                  )
                  .first,
            )
            .excluding,
        isTrue,
      );
      expect(
        tester
            .widget<ExcludeFocus>(
              find
                  .descendant(of: guard, matching: find.byType(ExcludeFocus))
                  .first,
            )
            .excluding,
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(_panel, findsNothing);
    },
  );

  testWidgets('reduced motion: the panel hides without an animation', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _open(tester, ['Merhaba dünya.']);
    await _extract(tester);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump();
    expect(_panel, findsNothing);
  });

  testWidgets('compact controls survive rebuild and keyboard hiding', (
    tester,
  ) async {
    await _open(tester, ['Bir. İki.']);
    await _extract(tester);
    expect(find.byTooltip('Önceki cümle'), findsOneWidget);
    expect(find.text('Hız 1×'), findsNothing);
    expect(find.byTooltip('Paneli küçült'), findsNothing);
    await tester.enterText(_field, 'Bir. İki. Üç.');
    await tester.pump();
    expect(find.byTooltip('Önceki cümle'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_panel, findsNothing);
    tester.view.resetViewInsets();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_panel, findsOneWidget);
    expect(find.byTooltip('Önceki cümle'), findsOneWidget);
  });

  testWidgets('playback and stop menu remain available', (tester) async {
    final harness = await _open(tester, ['Bir. İki.']);
    await _extract(tester);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();
    expect(harness.speech.isSpeaking, isTrue);
    expect(harness.speech.stopCalls, 0);
    expect(find.byTooltip('Önceki cümle'), findsOneWidget);
    expect(find.byTooltip('Duraklat'), findsOneWidget);
    await tapReadingControl(tester, 'Duraklat');
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Devam et'), findsOneWidget);
    await tapReadingControl(tester, 'Durdur');
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Sesli oku'), findsOneWidget);
  });

  testWidgets('compact controls are centered and accessible', (tester) async {
    await _open(tester, ['Bir. İki.']);
    await _extract(tester);
    final read = find.byTooltip('Sesli oku');
    final previous = find.byTooltip('Önceki cümle');
    final next = find.byTooltip('Sonraki cümle');
    final more = playbackMenu;
    expect(tester.getCenter(read).dx, closeTo(400, 1));
    expect(tester.getCenter(previous).dy, tester.getCenter(read).dy);
    expect(tester.getCenter(next).dy, tester.getCenter(read).dy);
    expect(tester.getCenter(more).dx, greaterThan(tester.getCenter(next).dx));
    for (final control in [read, previous, next, more]) {
      expect(tester.getSize(control).shortestSide, greaterThanOrEqualTo(48));
    }
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('Cümle 1 / 2'), findsNothing);
    expect(find.text('Durdur'), findsOneWidget);
    expect(find.text('Başa dön'), findsOneWidget);
  });

  testWidgets('starting to read removes the text field focus', (tester) async {
    await _open(tester, ['Bir. İki.']);
    await _extract(tester);
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.widget.focusNode.requestFocus();
    await tester.pump();
    expect(editable.widget.focusNode.hasFocus, isTrue);

    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();
    expect(editable.widget.focusNode.hasFocus, isFalse);
  });

  testWidgets('panel stays during reading when the keyboard inset is shown', (
    tester,
  ) async {
    await _open(tester, ['Bir. İki.']);
    await _extract(tester);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(playbackMenu, findsOneWidget);
  });

  testWidgets('narrow screen with large text: no overflow, controls usable', (
    tester,
  ) async {
    final h = await _open(
      tester,
      ['Merhaba dünya.'],
      size: const Size(320, 568),
      textScale: 2,
    );
    await _extract(tester);
    expect(tester.takeException(), isNull);

    final read = find.byTooltip('Sesli oku');
    await tester.ensureVisible(read);
    await tester.tap(read);
    await tester.pump();
    await tester.pump();
    expect(h.speech.spoken, ['Merhaba dünya.']);

    final next = find.byTooltip('Sonraki cümle');
    await tester.ensureVisible(next);
    expect(next.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(playbackMenu);
    await tester.pumpAndSettle();
    final restart = find.text('Başa dön');
    await tester.ensureVisible(restart);
    expect(restart.hitTestable(), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await openHomeReadingSettings(tester);
    expect(find.byKey(const ValueKey('reading-speed')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('speed dialog: default, selection updates and is applied', (
    tester,
  ) async {
    final h = await _open(tester, ['Bir. İki.']);
    await _extract(tester);

    Future<void> openSettings() async {
      await openHomeReadingSettings(tester);
    }

    Future<void> selectSpeed(String value) async {
      await tester.ensureVisible(find.byKey(const ValueKey('reading-speed')));
      await tester.tap(find.byKey(const ValueKey('reading-speed')));
      await tester.pumpAndSettle();
      for (final label in ['0.75×', '0.8×', '0.9×', '1×', '1.25×', '1.5×']) {
        expect(find.text(label), findsWidgets);
      }
      await tester.tap(find.text(value).last);
      await tester.pumpAndSettle();
      expect(find.text(value), findsOneWidget);
    }

    await openSettings();
    expect(find.text('1×'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<ReadingSpeed>>(
            find.byKey(const ValueKey('reading-speed')),
          )
          .items!
          .map((item) => item.value),
      ReadingSpeed.values,
    );
    expect(find.text('Sonraki sayfayı otomatik oku'), findsNothing);
    await selectSpeed('1.25×');
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();

    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();
    expect(h.speech.spokenRates, [1.25]);

    await openSettings();
    expect(h.speech.stopCalls, 0);
    await selectSpeed('0.8×');
    expect(h.speech.spokenRates, [1.25, 0.8]);
    expect(h.speech.spoken.last, h.speech.spoken.first);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();

    await tapReadingControl(tester, 'Duraklat');
    await tester.pump();
    await tester.pump();
    final spoken = h.speech.spoken.length;
    await openSettings();
    await selectSpeed('0.9×');
    expect(h.speech.spoken.length, spoken);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    await tapReadingControl(tester, 'Devam et');
    await tester.pump();
    await tester.pump();
    expect(h.speech.spokenRates.last, 0.9);
  });

  group('auto-scroll after OCR', () {
    Future<void> openLong(WidgetTester tester, List<Object> results) async {
      await _open(tester, results, size: const Size(400, 600));
    }

    ScrollPosition position(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(of: _scroll, matching: find.byType(Scrollable)).first,
        )
        .position;

    testWidgets('scrolls to the field after a new successful result', (
      tester,
    ) async {
      await openLong(tester, [_long]);
      await tester.pump();
      expect(position(tester).pixels, 0);
      await _extract(tester);
      await tester.pumpAndSettle();
      expect(position(tester).pixels, greaterThan(0));
      final switchTop = tester.getTopLeft(find.byType(SwitchListTile)).dy;
      final viewportTop = tester.getTopLeft(_scroll).dy;
      expect(switchTop, closeTo(viewportTop, 1));
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      expect(editable.widget.focusNode.hasFocus, isFalse);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNotNull,
      );
    });

    testWidgets('does not scroll on error or empty result', (tester) async {
      await openLong(tester, [Exception('ocr'), '   ']);
      await tester.ensureVisible(find.text('Metni çıkar'));
      await tester.pumpAndSettle();
      final beforeError = position(tester).pixels;
      await _extract(tester);
      expect(position(tester).pixels, beforeError);
      await tester.ensureVisible(find.text('Metni çıkar'));
      await tester.pumpAndSettle();
      final beforeEmpty = position(tester).pixels;
      await _extract(tester);
      expect(position(tester).pixels, beforeEmpty);
    });

    testWidgets('does not scroll on a switch change or rebuild', (
      tester,
    ) async {
      await openLong(tester, [_long]);
      await _extract(tester);
      await tester.pumpAndSettle();

      position(tester).jumpTo(position(tester).maxScrollExtent);
      await tester.pump();
      final before = position(tester).pixels;
      tester
          .widget<SwitchListTile>(find.byType(SwitchListTile))
          .onChanged
          ?.call(false);
      await tester.pumpAndSettle();
      expect(position(tester).pixels, before);
    });

    testWidgets('a second successful result scrolls again; dispose is safe', (
      tester,
    ) async {
      await openLong(tester, [_long, '$_long fazladan.']);
      await _extract(tester);
      await tester.pumpAndSettle();
      position(tester).jumpTo(position(tester).maxScrollExtent);
      await tester.pump();
      final far = position(tester).pixels;

      await _extract(tester);
      await tester.pumpAndSettle();
      expect(position(tester).pixels, lessThan(far));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });
}

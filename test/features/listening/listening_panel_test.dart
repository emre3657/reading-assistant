import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/app.dart';

import '../image_import/test_doubles.dart';
import 'fake_speech_service.dart';

// Fake engine and fake OCR: these tests cover layout and UI wiring only.
// Real speech speed and the scrolling feel need manual verification.
final _panel = find.byKey(const ValueKey('listening-panel'));
final _field = find.byType(TextField);
final _scroll = find.byKey(const ValueKey('content-scroll'));

Finder _chip(String label) => find.widgetWithText(ChoiceChip, label);

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
}) async {
  final harness = _Harness(FakeSpeechService(), results);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: ReadingAssistantApp(
          pickerService: FakeImagePickerService(
            onPick: () async => XFile('/tmp/a.jpg'),
          ),
          textRecognitionService: FakeTextRecognitionService((_) async {
            final r = harness.results[harness.calls++];
            if (r is String) return r;
            throw r;
          }),
          previewImageBuilder: (file) => ControlledImageProvider(),
          speechService: harness.speech,
        ),
      ),
    ),
  );
  await tester.pump();
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

  testWidgets(
    'more-controls section: default closed, toggles, survives rebuild '
    'and the panel being hidden by the keyboard',
    (tester) async {
      await _open(tester, ['Bir. İki.']);
      await _extract(tester);
      expect(find.text('Önceki cümle'), findsNothing);
      expect(find.text('Hız 1×'), findsOneWidget);

      await tester.tap(find.text('Diğer kontroller'));
      await tester.pump();
      expect(find.text('Önceki cümle'), findsOneWidget);
      expect(find.text('Başa dön'), findsOneWidget);
      expect(_chip('1.5×'), findsOneWidget);

      // Ordinary rebuild (text edit) keeps it open.
      await tester.enterText(_field, 'Bir. İki. Üç.');
      await tester.pump();
      expect(find.text('Önceki cümle'), findsOneWidget);

      // Keyboard hides the whole panel; it returns with the same state.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_panel, findsNothing);
      tester.view.resetViewInsets();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_panel, findsOneWidget);
      expect(find.text('Önceki cümle'), findsOneWidget);

      await tester.tap(find.text('Diğer kontroller'));
      await tester.pump();
      expect(find.text('Önceki cümle'), findsNothing);
    },
  );

  testWidgets('main controls stay available and Stop is not hidden in the '
      'collapsed section', (tester) async {
    await _open(tester, ['Bir. İki.']);
    await _extract(tester);
    expect(find.text('Durdur'), findsOneWidget);
    expect(find.text('Diğer kontroller'), findsOneWidget);

    await tester.tap(find.text('Sesli oku'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Önceki cümle'), findsNothing);
    expect(find.text('Duraklat'), findsOneWidget);
    await tester.tap(find.text('Duraklat'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Devam et'), findsOneWidget);
    await tester.tap(find.text('Durdur'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Sesli oku'), findsOneWidget);

    // Reachable and at least 48 px high, with tooltips/semantics labels.
    for (final label in ['Sesli oku', 'Durdur', 'Diğer kontroller']) {
      final size = tester.getSize(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
    }
  });

  testWidgets('starting to read removes the text field focus', (tester) async {
    await _open(tester, ['Bir. İki.']);
    await _extract(tester);
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.widget.focusNode.requestFocus();
    await tester.pump();
    expect(editable.widget.focusNode.hasFocus, isTrue);

    await tester.tap(find.text('Sesli oku'));
    await tester.pump();
    await tester.pump();
    expect(editable.widget.focusNode.hasFocus, isFalse);
  });

  testWidgets('panel stays during reading when the keyboard inset is shown', (
    tester,
  ) async {
    await _open(tester, ['Bir. İki.']);
    await _extract(tester);
    await tester.tap(find.text('Sesli oku'));
    await tester.pump();
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(find.text('Durdur'), findsOneWidget);
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

    final read = find.text('Sesli oku');
    await tester.ensureVisible(read);
    await tester.tap(read);
    await tester.pump();
    await tester.pump();
    expect(h.speech.spoken, ['Merhaba dünya.']);

    final more = find.text('Diğer kontroller');
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pump();
    final next = find.text('Sonraki cümle');
    await tester.ensureVisible(next);
    expect(tester.takeException(), isNull);
    final chip = _chip('1.5×');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('speed chips: 1× default, selection updates and is applied', (
    tester,
  ) async {
    final h = await _open(tester, ['Bir. İki.']);
    await _extract(tester);

    expect(_chip('1×'), findsNothing, reason: 'collapsed by default');
    await tester.tap(find.text('Diğer kontroller'));
    await tester.pump();

    bool selected(String l) => tester.widget<ChoiceChip>(_chip(l)).selected;
    for (final l in ['0.75×', '1×', '1.25×', '1.5×']) {
      expect(_chip(l), findsOneWidget);
    }
    expect(selected('1×'), isTrue);

    await tester.tap(_chip('1.25×'));
    await tester.pump();
    expect(selected('1.25×'), isTrue);
    expect(selected('1×'), isFalse);

    await tester.tap(find.text('Sesli oku'));
    await tester.pump();
    await tester.pump();
    expect(h.speech.spokenRates, [1.25]);

    await tester.tap(_chip('1.5×'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(h.speech.spokenRates, [1.25, 1.5]);
    expect(h.speech.spoken.last, h.speech.spoken.first);

    await tester.tap(find.text('Duraklat'));
    await tester.pump();
    await tester.pump();
    final spoken = h.speech.spoken.length;
    await tester.tap(_chip('0.75×'));
    await tester.pump();
    await tester.pump();
    expect(h.speech.spoken.length, spoken);
    expect(selected('0.75×'), isTrue);
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
      await _extract(tester);
      expect(position(tester).pixels, 0);
      await _extract(tester);
      expect(position(tester).pixels, 0);
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
          ?.call(true);
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

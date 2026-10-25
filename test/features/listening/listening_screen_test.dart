import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/app.dart';
import 'package:reading_assistant/features/listening/services/speech_service.dart';

import '../image_import/test_doubles.dart';
import 'fake_speech_service.dart';

// A fake engine is used: these tests cover the screen's controls and the
// blocking rules, not real speech output.
const _readLabel = 'Sesli oku';
const _stopLabel = 'Durdur';

final _fieldFinder = find.widgetWithText(TextField, 'Çıkarılan metin');

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(_button(label)).onPressed != null;

Future<FakeSpeechService> _openWithText(
  WidgetTester tester, {
  String text = 'Okunacak metin.',
  FakeSpeechService? speech,
}) async {
  speech ??= FakeSpeechService();
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ReadingAssistantApp(
      pickerService: FakeImagePickerService(
        onPick: () async => XFile('/tmp/a.jpg'),
      ),
      textRecognitionService: FakeTextRecognitionService((_) async => text),
      previewImageBuilder: (file) => ControlledImageProvider(),
      speechService: speech,
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Galeriden görsel seç'));
  await tester.pump();
  await tester.tap(find.text('Metni çıkar'));
  await tester.pump();
  await tester.pump();
  return speech;
}

void main() {
  testWidgets('controls appear with the text; stop is disabled when idle', (
    tester,
  ) async {
    await _openWithText(tester);
    expect(find.text(_readLabel), findsOneWidget);
    expect(find.text(_stopLabel), findsOneWidget);
    expect(_enabled(tester, _readLabel), isTrue);
    expect(_enabled(tester, _stopLabel), isFalse);
  });

  testWidgets('reads the visible, edited text, not the raw OCR result', (
    tester,
  ) async {
    final speech = await _openWithText(tester, text: 'ham metin');
    // Edit confirmation applies only to replacing the text, not to speaking.
    await tester.enterText(_fieldFinder, 'düzenlenmiş metin');
    await tester.tap(find.text(_readLabel));
    await tester.pump();
    await tester.pump();

    expect(speech.spoken, ['düzenlenmiş metin']);
    expect(find.text('Okunuyor…'), findsOneWidget);
  });

  testWidgets('blocks editing and image actions while reading; stop works', (
    tester,
  ) async {
    final speech = await _openWithText(tester);
    await tester.tap(find.text(_readLabel));
    await tester.pump();
    await tester.pump();

    expect(_enabled(tester, _readLabel), isFalse);
    expect(_enabled(tester, _stopLabel), isTrue);
    expect(tester.widget<TextField>(_fieldFinder).readOnly, isTrue);
    for (final label in [
      'Metni çıkar',
      'Görseli değiştir',
      'Görseli kaldır',
      'Sola döndür',
      'Sağa döndür',
    ]) {
      expect(_enabled(tester, label), isFalse, reason: label);
    }
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );

    await tester.tap(find.text(_stopLabel));
    await tester.pump();
    await tester.pump();

    expect(speech.stopCalls, 1);
    expect(_enabled(tester, _readLabel), isTrue);
    expect(_enabled(tester, 'Metni çıkar'), isTrue);
    expect(tester.widget<TextField>(_fieldFinder).readOnly, isFalse);
  });

  testWidgets('shows completion and allows reading again', (tester) async {
    final speech = await _openWithText(tester);
    await tester.tap(find.text(_readLabel));
    await tester.pump();
    await tester.pump();
    speech.finishCurrent();
    await tester.pump();
    await tester.pump();

    expect(find.text('Okuma tamamlandı.'), findsOneWidget);
    expect(_enabled(tester, _readLabel), isTrue);
  });

  testWidgets('tells the user to install a Turkish voice', (tester) async {
    final speech = await _openWithText(
      tester,
      speech: FakeSpeechService(
        setup: const SpeechSetup(SpeechAvailability.noOfflineTurkishVoice),
      ),
    );
    await tester.tap(find.text(_readLabel));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Türkçe sesi yükleyin'), findsOneWidget);
    expect(speech.spoken, isEmpty);
    expect(_enabled(tester, _readLabel), isTrue);
  });

  testWidgets('does not read whitespace-only text', (tester) async {
    final speech = await _openWithText(tester, text: 'x');
    await tester.enterText(_fieldFinder, '   ');
    await tester.tap(find.text(_readLabel));
    await tester.pump();

    expect(speech.prepareCalls, 0);
    expect(find.text('Okunacak metin yok.'), findsOneWidget);
  });

  testWidgets('stops reading when the app goes to the background', (
    tester,
  ) async {
    final speech = await _openWithText(tester);
    await tester.tap(find.text(_readLabel));
    await tester.pump();
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(speech.stopCalls, 0, reason: 'inactive keeps reading');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();
    expect(speech.stopCalls, 1);
    expect(_enabled(tester, _readLabel), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('closing the screen stops reading without errors', (
    tester,
  ) async {
    final speech = await _openWithText(tester);
    await tester.tap(find.text(_readLabel));
    await tester.pump();
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    speech.finishCurrent();
    await tester.pump();

    expect(speech.stopCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stays usable with large text', (tester) async {
    await _openWithText(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(_readLabel));
    expect(find.text(_readLabel), findsOneWidget);
  });
}

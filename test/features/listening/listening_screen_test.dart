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

final _fieldFinder = find.byType(TextField);

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

    expect(find.text(_readLabel), findsNothing, reason: 'replaced by Duraklat');
    expect(_enabled(tester, 'Duraklat'), isTrue);
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

  testWidgets('lock icon shows only during a session and explains itself', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _openWithText(tester);
    const message = 'Düzenlemek için okumayı durdur';
    final lock = find.byIcon(Icons.lock_outline);
    expect(lock, findsNothing);

    await tester.tap(find.text(_readLabel));
    await tester.pump();
    await tester.pump();
    expect(lock, findsOneWidget);
    // Right next to the label, not inside the field.
    final label = tester.getRect(find.text('Çıkarılan metin'));
    final icon = tester.getRect(lock);
    expect(icon.left, greaterThanOrEqualTo(label.right));
    expect((icon.center.dy - label.center.dy).abs(), lessThan(30));
    expect(
      tester
          .getSize(
            find.ancestor(of: lock, matching: find.byType(SizedBox)).first,
          )
          .shortestSide,
      greaterThanOrEqualTo(48),
    );
    expect(find.byTooltip(message), findsOneWidget);
    expect(
      tester.getSemantics(lock),
      matchesSemantics(label: 'Düzenleme kilitli. $message'),
    );

    // Touch: tapping the icon shows the explanation.
    await tester.tap(lock);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(message), findsWidgets);
    // Tapping does not stop reading.
    expect(find.text('Duraklat'), findsOneWidget);

    await tester.tap(find.text(_stopLabel));
    await tester.pump();
    await tester.pump();
    expect(lock, findsNothing);
    handle.dispose();
  });

  testWidgets('the old "not saved" helper text is gone', (tester) async {
    await _openWithText(tester);
    expect(find.textContaining('kaydedilmedi'), findsNothing);
    expect(find.textContaining('düzeltebilirsin'), findsNothing);
  });

  Future<void> expectNoFocusAfter(
    WidgetTester tester,
    Future<void> Function() endSession,
  ) async {
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    // Touching the locked field neither focuses it nor stops the reading.
    await tester.tap(_fieldFinder);
    await tester.pump();
    expect(editable.widget.focusNode.hasFocus, isFalse);
    expect(
      find.text('Okunuyor…').evaluate().isNotEmpty ||
          find.text('Duraklatıldı.').evaluate().isNotEmpty,
      isTrue,
    );

    await endSession();
    expect(editable.widget.focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  }

  testWidgets('touching the locked field then Stop does not focus or open '
      'the keyboard; editing works again afterwards', (tester) async {
    await _openWithText(tester);
    await tester.tap(find.text(_readLabel));
    await tester.pump();
    await tester.pump();

    await expectNoFocusAfter(tester, () async {
      await tester.tap(find.text(_stopLabel));
      await tester.pump();
      await tester.pump();
    });

    // After the session a new tap edits normally.
    await tester.tap(_fieldFinder);
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('same behaviour while paused', (tester) async {
    await _openWithText(tester);
    await tester.tap(find.text(_readLabel));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Duraklat'));
    await tester.pump();
    await tester.pump();

    await expectNoFocusAfter(tester, () async {
      await tester.tap(find.text(_stopLabel));
      await tester.pump();
      await tester.pump();
    });
  });

  testWidgets('no auto focus after completion or an error', (tester) async {
    final speech = await _openWithText(tester);
    await tester.tap(find.text(_readLabel));
    await tester.pump();
    await tester.pump();
    await tester.tap(_fieldFinder);
    await tester.pump();
    speech.finishCurrent();
    await tester.pump();
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('starting to read removes an existing focus', (tester) async {
    await _openWithText(tester);
    await tester.tap(_fieldFinder);
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasFocus, isTrue);

    await tester.tap(find.text(_readLabel));
    await tester.pump();
    await tester.pump();
    expect(editable.widget.focusNode.hasFocus, isFalse);
  });

  testWidgets('sentence controls: states, indicator and pause lock', (
    tester,
  ) async {
    final speech = await _openWithText(tester, text: 'Bir. İki. Üç.');
    expect(find.text('Duraklat'), findsNothing);
    expect(find.text('Devam et'), findsNothing);
    expect(find.text('Önceki cümle'), findsNothing, reason: 'collapsed');
    await tester.tap(find.text('Diğer kontroller'));
    await tester.pump();
    for (final label in ['Önceki cümle', 'Sonraki cümle', 'Başa dön']) {
      expect(_enabled(tester, label), isFalse, reason: label);
    }
    expect(find.textContaining('Cümle 1'), findsNothing);

    await tester.tap(find.text(_readLabel));
    await tester.pump();
    await tester.pump();
    expect(find.text('Cümle 1 / 3'), findsOneWidget);
    expect(find.text('Hız 1×'), findsOneWidget);
    expect(
      find.text('Devam et, mevcut cümlenin başından okur.'),
      findsOneWidget,
    );
    expect(_enabled(tester, 'Duraklat'), isTrue);
    expect(_enabled(tester, 'Sonraki cümle'), isTrue);
    expect(_enabled(tester, 'Önceki cümle'), isFalse);
    expect(_enabled(tester, 'Başa dön'), isTrue);

    await tester.tap(find.text('Sonraki cümle'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Cümle 2 / 3'), findsOneWidget);
    expect(speech.spoken, ['Bir. ', 'İki. ']);
    expect(_enabled(tester, 'Önceki cümle'), isTrue);
    expect(_enabled(tester, 'Başa dön'), isTrue);

    await tester.tap(find.text('Duraklat'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Devam et'), findsOneWidget);
    expect(find.text('Duraklatıldı.'), findsOneWidget);
    expect(_enabled(tester, 'Devam et'), isTrue);
    expect(find.text(_readLabel), findsNothing);
    expect(tester.widget<TextField>(_fieldFinder).readOnly, isTrue);
    for (final label in ['Metni çıkar', 'Görseli değiştir', 'Görseli kaldır']) {
      expect(_enabled(tester, label), isFalse, reason: label);
    }

    await tester.tap(find.text('Başa dön'));
    await tester.pump();
    expect(find.text('Cümle 1 / 3'), findsOneWidget);
    expect(find.text('Devam et'), findsOneWidget, reason: 'still paused');

    await tester.tap(find.text('Devam et'));
    await tester.pump();
    await tester.pump();
    expect(speech.spoken.last, 'Bir. ');
    expect(find.text('Duraklat'), findsOneWidget);

    await tester.tap(find.text('Duraklat'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text(_stopLabel));
    await tester.pump();
    await tester.pump();
    expect(_enabled(tester, _readLabel), isTrue);
    expect(_enabled(tester, 'Metni çıkar'), isTrue);
    expect(tester.widget<TextField>(_fieldFinder).readOnly, isFalse);
    expect(find.textContaining('Cümle 1'), findsNothing);
  });

  testWidgets('a paused reading stops when the app goes to the background', (
    tester,
  ) async {
    final speech = await _openWithText(tester, text: 'Bir. İki.');
    await tester.tap(find.text(_readLabel));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Duraklat'));
    await tester.pump();
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();
    expect(speech.stopCalls, 2);
    expect(_enabled(tester, _readLabel), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/app.dart';

import 'test_doubles.dart';

const _extractLabel = 'Metni çıkar';
const _selectLabel = 'Galeriden görsel seç';
const _changeLabel = 'Görseli değiştir';
const _removeLabel = 'Görseli kaldır';
const _fieldLabel = 'Çıkarılan metin';
const _noTextMessage = 'Görselde metin bulunamadı',
    _errorPrefix = 'Metin çıkarılamadı';
const _ocrText = 'Çocuğun ĞÜŞİÖ ığüşö\nİkinci satır\n\nÜçüncü paragraf';

final _textField = find.widgetWithText(TextField, _fieldLabel);

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(_textField).controller!.text;

class _Harness {
  _Harness({required this.onRecognize, Future<XFile?> Function()? onPick})
    : picker = FakeImagePickerService(
        onPick: onPick ?? () async => XFile('/tmp/a.png'),
      );

  final Future<String> Function(String path) onRecognize;
  final FakeImagePickerService picker;
  final providers = <ControlledImageProvider>[];
  late final recognizer = FakeTextRecognitionService(onRecognize);

  Widget get app => ReadingAssistantApp(
    pickerService: picker,
    textRecognitionService: recognizer,
    previewImageBuilder: (file) {
      final provider = ControlledImageProvider();
      providers.add(provider);
      return provider;
    },
  );

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(app);
    await tester.pump();
    await tester.tap(find.text(_selectLabel));
    await tester.pump();
  }
}

Future<void> _extract(WidgetTester tester) async {
  await tester.tap(find.text(_extractLabel));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows the extract button only when an image is selected', (
    tester,
  ) async {
    final harness = _Harness(onRecognize: (_) async => _ocrText);
    await tester.pumpWidget(harness.app);
    await tester.pump();
    expect(find.text(_extractLabel), findsNothing);

    await tester.tap(find.text(_selectLabel));
    await tester.pump();
    expect(find.text(_extractLabel), findsOneWidget);
    expect(harness.recognizer.paths, isEmpty);
  });

  testWidgets('extracts text from the original file and lets it be edited', (
    tester,
  ) async {
    final harness = _Harness(onRecognize: (_) async => _ocrText);
    await harness.start(tester);
    await _extract(tester);

    expect(harness.recognizer.paths, ['/tmp/a.png']);
    expect(_fieldText(tester), _ocrText);
    expect(find.textContaining('henüz kaydedilmedi'), findsOneWidget);

    await tester.enterText(_textField, 'Düzeltilmiş\nmetin');
    await tester.pump();
    expect(_fieldText(tester), 'Düzeltilmiş\nmetin');
  });

  testWidgets('shows progress and blocks other actions while recognizing', (
    tester,
  ) async {
    final completer = Completer<String>();
    final harness = _Harness(onRecognize: (_) => completer.future);
    await harness.start(tester);

    await tester.tap(find.text(_extractLabel));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(_extractLabel), findsNothing);
    expect(find.text(_changeLabel), findsNothing);
    expect(find.text(_removeLabel), findsNothing);
    expect(harness.recognizer.paths, hasLength(1));

    completer.complete(_ocrText);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(harness.recognizer.paths, hasLength(1));
    expect(_fieldText(tester), _ocrText);
  });

  testWidgets('explains an empty result and allows retrying', (tester) async {
    var calls = 0;
    final harness = _Harness(
      onRecognize: (_) async => calls++ == 0 ? '  \n ' : _ocrText,
    );
    await harness.start(tester);
    await _extract(tester);

    expect(find.textContaining(_noTextMessage), findsOneWidget);
    expect(_textField, findsNothing);

    await _extract(tester);
    expect(find.textContaining(_noTextMessage), findsNothing);
    expect(_fieldText(tester), _ocrText);
  });

  testWidgets('shows an error, stays usable and allows retrying', (
    tester,
  ) async {
    var calls = 0;
    final harness = _Harness(
      onRecognize: (_) async {
        if (calls++ == 0) throw Exception('mlkit failed');
        return _ocrText;
      },
    );
    await harness.start(tester);
    await _extract(tester);

    expect(find.textContaining(_errorPrefix), findsOneWidget);
    expect(find.text(_extractLabel), findsOneWidget);
    expect(find.text(_changeLabel), findsOneWidget);

    await _extract(tester);
    expect(find.textContaining(_errorPrefix), findsNothing);
    expect(_fieldText(tester), _ocrText);
  });

  testWidgets('keeps image and edited text when picking is cancelled', (
    tester,
  ) async {
    var picks = 0;
    final harness = _Harness(
      onRecognize: (_) async => _ocrText,
      onPick: () async => picks++ == 0 ? XFile('/tmp/a.png') : null,
    );
    await harness.start(tester);
    await _extract(tester);
    await tester.enterText(_textField, 'Benim düzeltmem');

    await tester.tap(find.text(_changeLabel));
    await tester.pump();

    expect(picks, 2);
    expect(harness.providers, hasLength(1));
    expect(find.text(_removeLabel), findsOneWidget);
    expect(_fieldText(tester), 'Benim düzeltmem');
  });

  testWidgets('clears the text when a new image is picked', (tester) async {
    var picks = 0;
    final harness = _Harness(
      onRecognize: (_) async => _ocrText,
      onPick: () async => XFile('/tmp/${picks++ == 0 ? 'a' : 'b'}.png'),
    );
    await harness.start(tester);
    await _extract(tester);
    expect(_textField, findsOneWidget);

    await tester.tap(find.text(_changeLabel));
    await tester.pump();

    expect(harness.providers, hasLength(2));
    expect(_textField, findsNothing);

    await _extract(tester);
    expect(harness.recognizer.paths, ['/tmp/a.png', '/tmp/b.png']);
  });

  testWidgets('clears the text when the image is removed', (tester) async {
    final harness = _Harness(onRecognize: (_) async => _ocrText);
    await harness.start(tester);
    await _extract(tester);

    await tester.tap(find.text(_removeLabel));
    await tester.pump();

    expect(_textField, findsNothing);
    expect(find.text(_selectLabel), findsOneWidget);
  });

  group('re-running OCR over existing text', () {
    testWidgets('does not ask when the text was not edited', (tester) async {
      final harness = _Harness(onRecognize: (_) async => _ocrText);
      await harness.start(tester);
      await _extract(tester);
      await _extract(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(harness.recognizer.paths, hasLength(2));
    });

    testWidgets('keeps the edited text when the user declines', (tester) async {
      final harness = _Harness(onRecognize: (_) async => _ocrText);
      await harness.start(tester);
      await _extract(tester);
      await tester.enterText(_textField, 'Benim düzeltmem');

      await tester.tap(find.text(_extractLabel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      expect(harness.recognizer.paths, hasLength(1));
      expect(_fieldText(tester), 'Benim düzeltmem');
    });

    testWidgets('replaces the edited text after confirmation', (tester) async {
      final harness = _Harness(onRecognize: (_) async => _ocrText);
      await harness.start(tester);
      await _extract(tester);
      await tester.enterText(_textField, 'Benim düzeltmem');

      await tester.tap(find.text(_extractLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Üzerine yaz'));
      await tester.pumpAndSettle();

      expect(harness.recognizer.paths, hasLength(2));
      expect(_fieldText(tester), _ocrText);
    });

    testWidgets('keeps the edited text when the new result is empty', (
      tester,
    ) async {
      var calls = 0;
      final harness = _Harness(
        onRecognize: (_) async => calls++ == 0 ? _ocrText : '',
      );
      await harness.start(tester);
      await _extract(tester);
      await tester.enterText(_textField, 'Benim düzeltmem');

      await tester.tap(find.text(_extractLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Üzerine yaz'));
      await tester.pumpAndSettle();

      expect(find.textContaining(_noTextMessage), findsOneWidget);
      expect(_fieldText(tester), 'Benim düzeltmem');
    });
  });

  testWidgets('ignores a result that completes after the screen is closed', (
    tester,
  ) async {
    final completer = Completer<String>();
    final harness = _Harness(onRecognize: (_) => completer.future);
    await harness.start(tester);
    await tester.tap(find.text(_extractLabel));
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    completer.complete(_ocrText);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('ignores a failure that arrives after the screen is closed', (
    tester,
  ) async {
    final completer = Completer<String>();
    final harness = _Harness(onRecognize: (_) => completer.future);
    await harness.start(tester);
    await tester.tap(find.text(_extractLabel));
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    completer.completeError(Exception('late failure'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('drops a result when the image disappeared during OCR', (
    tester,
  ) async {
    final completer = Completer<String>();
    final harness = _Harness(onRecognize: (_) => completer.future);
    await harness.start(tester);
    await tester.tap(find.text(_extractLabel));
    await tester.pump();

    // The preview fails to decode while OCR is running.
    harness.providers.single.fail();
    await tester.pump();
    await tester.pump();
    completer.complete(_ocrText);
    await tester.pump();

    expect(_textField, findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(_selectLabel), findsOneWidget);
  });

  testWidgets('stays usable with large text and the keyboard open', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 3.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final harness = _Harness(onRecognize: (_) async => _ocrText * 20);
    await harness.start(tester);
    await _extract(tester);

    await tester.showKeyboard(_textField);
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}

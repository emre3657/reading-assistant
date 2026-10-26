import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/app.dart';
import 'package:reading_assistant/features/image_import/presentation/widgets/image_preview.dart';

import 'test_doubles.dart';

const _extractLabel = 'Metni çıkar';
const _selectLabel = 'Galeriden görsel seç';
const _changeLabel = 'Görseli değiştir';
const _removeLabel = 'Görseli kaldır';
const _leftLabel = 'Sola döndür';
const _rightLabel = 'Sağa döndür';

final _textField = find.byType(TextField);

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(_textField).controller!.text;

int _previewTurns(WidgetTester tester) => tester
    .widget<RotatedBox>(
      find.descendant(
        of: find.byType(ImagePreview),
        matching: find.byType(RotatedBox),
      ),
    )
    .quarterTurns;

class _Harness {
  _Harness({
    Future<String> Function(String path)? onRecognize,
    Future<XFile?> Function()? onPick,
    Future<String> Function(String, int)? onCreate,
  }) : picker = FakeImagePickerService(
         onPick: onPick ?? () async => XFile('/tmp/a.jpg'),
       ),
       recognizer = FakeTextRecognitionService(
         onRecognize ?? (_) async => 'Çıkarılan metin',
       ),
       rotation = FakeImageRotationService(onCreate: onCreate);

  final FakeImagePickerService picker;
  final FakeTextRecognitionService recognizer;
  final FakeImageRotationService rotation;

  Widget get app => ReadingAssistantApp(
    pickerService: picker,
    textRecognitionService: recognizer,
    rotationService: rotation,
    previewImageBuilder: (file) => ControlledImageProvider(),
  );

  Future<void> start(WidgetTester tester) async {
    // Tall surface so the longer layout keeps all controls on screen.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pump();
    await tester.tap(find.text(_selectLabel));
    await tester.pump();
  }
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
}

Future<void> _extract(WidgetTester tester) async {
  await _tap(tester, _extractLabel);
  await tester.pump();
}

// The progress indicator behind the dialog never settles.
Future<void> _showDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  group('rotation state', () {
    testWidgets('shows rotate controls only when an image is selected', (
      tester,
    ) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app);
      await tester.pump();
      expect(find.text(_leftLabel), findsNothing);
      expect(find.text(_rightLabel), findsNothing);

      await tester.tap(find.text(_selectLabel));
      await tester.pump();
      expect(find.text(_leftLabel), findsOneWidget);
      expect(find.text(_rightLabel), findsOneWidget);
      expect(_previewTurns(tester), 0);
    });

    testWidgets('computes the total angle from left and right turns', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.start(tester);

      await _tap(tester, _rightLabel);
      expect(_previewTurns(tester), 1);
      expect(find.textContaining('90°'), findsOneWidget);

      await _tap(tester, _rightLabel);
      expect(_previewTurns(tester), 2);
      expect(find.textContaining('180°'), findsOneWidget);

      await _tap(tester, _leftLabel);
      await _tap(tester, _leftLabel);
      expect(_previewTurns(tester), 0);
      expect(find.textContaining('°'), findsNothing);

      await _tap(tester, _leftLabel);
      expect(_previewTurns(tester), 3);
      expect(find.textContaining('270°'), findsOneWidget);

      await _tap(tester, _rightLabel);
      await _tap(tester, _rightLabel);
      await _tap(tester, _rightLabel);
      await _tap(tester, _rightLabel);
      expect(_previewTurns(tester), 3);
    });

    testWidgets('keeps the rotation when the gallery pick is cancelled', (
      tester,
    ) async {
      var picks = 0;
      final harness = _Harness(
        onPick: () async => picks++ == 0 ? XFile('/tmp/a.jpg') : null,
      );
      await harness.start(tester);
      await _tap(tester, _rightLabel);

      await _tap(tester, _changeLabel);
      await tester.pump();

      expect(_previewTurns(tester), 1);
    });

    testWidgets('resets the rotation for a new image, even the same file', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.start(tester);
      await _tap(tester, _rightLabel);
      expect(_previewTurns(tester), 1);

      await _tap(tester, _changeLabel);
      await tester.pump();

      expect(_previewTurns(tester), 0);
    });

    testWidgets('resets the rotation when the image is removed', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.start(tester);
      await _tap(tester, _rightLabel);

      await _tap(tester, _removeLabel);
      await tester.pump();
      await _tap(tester, _selectLabel);

      expect(_previewTurns(tester), 0);
    });

    testWidgets('hides rotate controls while picking or recognizing', (
      tester,
    ) async {
      final pick = Completer<XFile?>();
      var picks = 0;
      final recognition = Completer<String>();
      final harness = _Harness(
        onPick: () =>
            picks++ == 0 ? Future.value(XFile('/tmp/a.jpg')) : pick.future,
        onRecognize: (_) => recognition.future,
      );
      await harness.start(tester);

      await _tap(tester, _changeLabel);
      expect(find.text(_leftLabel), findsNothing);
      expect(find.text(_rightLabel), findsNothing);
      pick.complete(null);
      await tester.pump();
      expect(find.text(_leftLabel), findsOneWidget);

      await _extract(tester);
      expect(find.text(_leftLabel), findsNothing);
      expect(find.text(_rightLabel), findsNothing);
      recognition.complete('x');
      await tester.pump();
      expect(find.text(_leftLabel), findsOneWidget);
    });
  });

  group('rotation and text', () {
    testWidgets('rotating keeps the existing edited text without asking', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.start(tester);
      await _extract(tester);
      await tester.enterText(_textField, 'Benim düzeltmem');
      await tester.pump();

      await _tap(tester, _rightLabel);

      expect(find.byType(AlertDialog), findsNothing);
      expect(_fieldText(tester), 'Benim düzeltmem');
    });

    testWidgets('OCR over edited text after rotating uses the overwrite '
        'confirmation; declining keeps text and makes no copy', (tester) async {
      final harness = _Harness();
      await harness.start(tester);
      await _extract(tester);
      await tester.enterText(_textField, 'Benim düzeltmem');
      await tester.pump();
      await _tap(tester, _rightLabel);

      await tester.tap(find.text(_extractLabel));
      await _showDialog(tester);
      expect(find.text('Metnin üzerine yazılsın mı?'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await _showDialog(tester);

      expect(_fieldText(tester), 'Benim düzeltmem');
      expect(harness.rotation.created, isEmpty);
      expect(harness.recognizer.paths, ['/tmp/a.jpg']);
    });

    testWidgets('confirming overwrite runs OCR on the rotated copy', (
      tester,
    ) async {
      final harness = _Harness(
        onRecognize: (path) async => path.contains('rotated') ? 'yeni' : 'eski',
      );
      await harness.start(tester);
      await _extract(tester);
      await tester.enterText(_textField, 'Benim düzeltmem');
      await tester.pump();
      await _tap(tester, _rightLabel);

      await tester.tap(find.text(_extractLabel));
      await _showDialog(tester);
      await tester.tap(find.text('Üzerine yaz'));
      await _showDialog(tester);

      expect(_fieldText(tester), 'yeni');
      expect(harness.rotation.created, [('/tmp/a.jpg', 1)]);
    });
  });

  group('OCR input', () {
    testWidgets('without rotation OCR reads the original file, no copy', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.start(tester);
      await _extract(tester);

      expect(harness.recognizer.paths, ['/tmp/a.jpg']);
      expect(harness.rotation.created, isEmpty);
      expect(harness.rotation.deleted, isEmpty);
    });

    testWidgets('after full rotation back to zero OCR reads the original', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.start(tester);
      await _tap(tester, _rightLabel);
      await _tap(tester, _leftLabel);
      await _extract(tester);

      expect(harness.recognizer.paths, ['/tmp/a.jpg']);
      expect(harness.rotation.created, isEmpty);
    });

    testWidgets('OCR gets a copy made from the original and the total angle', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.start(tester);
      await _tap(tester, _leftLabel);
      await _tap(tester, _leftLabel);
      await _extract(tester);

      expect(harness.rotation.created, [('/tmp/a.jpg', 2)]);
      expect(harness.recognizer.paths, ['/tmp/rotated_1.jpg']);
    });

    testWidgets('a second rotated OCR starts again from the original file', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.start(tester);
      await _tap(tester, _rightLabel);
      await _extract(tester);
      await tester.enterText(_textField, 'x');
      await _tap(tester, _rightLabel);
      await tester.tap(find.text(_extractLabel));
      await _showDialog(tester);
      await tester.tap(find.text('Üzerine yaz'));
      await _showDialog(tester);

      expect(harness.rotation.created, [('/tmp/a.jpg', 1), ('/tmp/a.jpg', 2)]);
    });
  });

  group('temporary copy lifecycle', () {
    testWidgets('is kept while OCR runs and deleted after success', (
      tester,
    ) async {
      final recognition = Completer<String>();
      final harness = _Harness(onRecognize: (_) => recognition.future);
      await harness.start(tester);
      await _tap(tester, _rightLabel);
      await _extract(tester);

      expect(harness.rotation.created, hasLength(1));
      expect(harness.rotation.deleted, isEmpty);

      recognition.complete('metin');
      await tester.pump();
      await tester.pump();

      expect(harness.rotation.deleted, ['/tmp/rotated_1.jpg']);
      expect(_fieldText(tester), 'metin');
    });

    testWidgets('is deleted after an OCR failure and OCR can be retried', (
      tester,
    ) async {
      var calls = 0;
      final harness = _Harness(
        onRecognize: (_) async {
          if (calls++ == 0) throw Exception('boom');
          return 'metin';
        },
      );
      await harness.start(tester);
      await _tap(tester, _rightLabel);
      await _extract(tester);

      expect(find.textContaining('Metin çıkarılamadı'), findsOneWidget);
      expect(harness.rotation.deleted, ['/tmp/rotated_1.jpg']);

      await _extract(tester);
      expect(_fieldText(tester), 'metin');
      expect(harness.rotation.deleted, hasLength(2));
    });

    testWidgets('is deleted after OCR finishes when the screen was closed', (
      tester,
    ) async {
      final recognition = Completer<String>();
      final harness = _Harness(onRecognize: (_) => recognition.future);
      await harness.start(tester);
      await _tap(tester, _rightLabel);
      await _extract(tester);

      await tester.pumpWidget(const SizedBox());
      expect(harness.rotation.deleted, isEmpty);

      recognition.complete('metin');
      await tester.pump();
      await tester.pump();

      expect(harness.rotation.deleted, ['/tmp/rotated_1.jpg']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is not deleted before the copy exists, and a failed '
        'rotation shows an error without running OCR', (tester) async {
      final harness = _Harness(onCreate: (_, _) async => throw Exception('x'));
      await harness.start(tester);
      await _tap(tester, _rightLabel);
      await _extract(tester);

      expect(find.textContaining('Görsel döndürülemedi'), findsOneWidget);
      expect(harness.recognizer.paths, isEmpty);
      expect(harness.rotation.deleted, isEmpty);
      expect(find.text(_extractLabel), findsOneWidget);
    });

    testWidgets('slow rotation blocks conflicting actions', (tester) async {
      final copy = Completer<String>();
      final harness = _Harness(onCreate: (_, _) => copy.future);
      await harness.start(tester);
      await _tap(tester, _rightLabel);
      await _extract(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_extractLabel), findsNothing);
      expect(find.text(_leftLabel), findsNothing);
      expect(find.text(_changeLabel), findsNothing);

      copy.complete('/tmp/rotated_slow.jpg');
      await tester.pump();
      await tester.pump();
      expect(harness.rotation.deleted, ['/tmp/rotated_slow.jpg']);
    });
  });
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_controller.dart';
import 'package:reading_assistant/features/image_import/services/ocr_result.dart';

import 'test_doubles.dart';

ImageProvider _image(XFile file) => ControlledImageProvider();

void main() {
  late FakeTextRecognitionService ocr;
  late FakeImageRotationService rotation;
  late Future<XFile?> Function() onPick;

  ImageImportController create({bool canRecover = false}) {
    return ImageImportController(
      pickerService: FakeImagePickerService(
        onPick: () => onPick(),
        canRecoverLostImage: canRecover,
        onRetrieveLost: () async => XFile('/lost.jpg'),
      ),
      textRecognitionService: ocr,
      rotationService: rotation,
      previewImageBuilder: _image,
    );
  }

  setUp(() {
    ocr = FakeTextRecognitionService((_) async => 'ham metin');
    rotation = FakeImageRotationService();
    onPick = () async => XFile('/a.jpg');
  });

  Future<ImageImportController> withImage() async {
    final c = create();
    final candidate = await c.pickImage();
    c.applyPick(candidate!);
    return c;
  }

  test('pick, apply and remove reset everything tied to the image', () async {
    final c = await withImage();
    addTearDown(c.dispose);
    c.rotate(1);
    await c.extractText(expectedRevision: c.revision);
    expect(c.textController.text, 'ham metin');
    expect(c.hasRecognizedText, isTrue);

    c.removeImage(expectedRevision: c.revision);
    expect(c.selection, isNull);
    expect(c.quarterTurns, 0);
    expect(c.hasRecognizedText, isFalse);
    expect(c.joinLines, isFalse);
    expect(c.textController.text, isEmpty);
    expect(c.isBusy, isFalse);
  });

  test('recognitionId grows only for a new non-empty result', () async {
    var result = 'ham metin';
    ocr = FakeTextRecognitionService((_) async => result);
    final c = await withImage();
    addTearDown(c.dispose);
    expect(c.recognitionId, 0);

    await c.extractText(expectedRevision: c.revision);
    expect(c.recognitionId, 1);

    c.setJoinLines(true, expectedRevision: c.revision);
    c.textController.text = 'ham metin!';
    expect(c.recognitionId, 1, reason: 'toggles and edits are not results');

    result = '   ';
    await c.extractText(expectedRevision: c.revision);
    expect(c.recognitionId, 1, reason: 'empty result');

    result = 'ikinci metin';
    await c.extractText(expectedRevision: c.revision);
    expect(c.recognitionId, 2);
  });

  test('detects edits and notifies only when the state flips', () async {
    final c = await withImage();
    addTearDown(c.dispose);
    await c.extractText(expectedRevision: c.revision);
    var notified = 0;
    c.addListener(() => notified++);

    expect(c.hasEditedText, isFalse);
    c.textController.text = 'ham metin!';
    expect(c.hasEditedText, isTrue);
    expect(notified, 1);
    c.textController.text = 'ham metin!!';
    expect(notified, 1);
    c.textController.text = 'ham metin';
    expect(c.hasEditedText, isFalse);
    expect(notified, 2);
  });

  test('joining lines does not count as an edit', () async {
    ocr = FakeTextRecognitionService((_) async => 'a\nb');
    final c = await withImage();
    addTearDown(c.dispose);
    await c.extractText(expectedRevision: c.revision);
    c.setJoinLines(true, expectedRevision: c.revision);
    expect(c.joinLines, isTrue);
    expect(c.textController.text, 'a b');
    expect(c.hasEditedText, isFalse);
  });

  test('blocks a second pick and OCR while busy', () async {
    final gate = Completer<XFile?>();
    onPick = () => gate.future;
    final c = create();
    addTearDown(c.dispose);
    final first = c.pickImage();
    expect(c.isPicking, isTrue);
    expect(await c.pickImage(), isNull);
    gate.complete(XFile('/b.jpg'));
    final candidate = await first;
    expect(c.isBusy, isTrue);
    c.applyPick(candidate!);
    expect(c.isBusy, isFalse);
    expect(c.selection?.file.path, '/b.jpg');
  });

  test('a cancelled or failed pick keeps image and text', () async {
    final c = await withImage();
    addTearDown(c.dispose);
    await c.extractText(expectedRevision: c.revision);
    c.textController.text = 'düzenlendi';

    onPick = () async => null;
    expect(await c.pickImage(), isNull);
    expect(c.isBusy, isFalse);
    expect(c.selection?.file.path, '/a.jpg');
    expect(c.textController.text, 'düzenlendi');

    onPick = () async => throw Exception('boom');
    expect(await c.pickImage(), isNull);
    expect(c.isBusy, isFalse);
    expect(c.errorMessage, contains('Görsel seçilemedi'));
    expect(c.textController.text, 'düzenlendi');
  });

  test('discarding a candidate releases busy and keeps state', () async {
    final c = await withImage();
    addTearDown(c.dispose);
    onPick = () async => XFile('/c.jpg');
    final candidate = await c.pickImage();
    c.discardPick(candidate!);
    expect(c.isBusy, isFalse);
    expect(c.selection?.file.path, '/a.jpg');
    expect(c.applyPick(candidate), isFalse);
    expect(c.selection?.file.path, '/a.jpg');
  });

  test('rejects a confirmation made against an older revision', () async {
    final c = await withImage();
    addTearDown(c.dispose);
    await c.extractText(expectedRevision: c.revision);
    final stale = c.revision;
    c.rotate(1);

    c.removeImage(expectedRevision: stale);
    expect(c.selection, isNotNull);
    c.setJoinLines(true, expectedRevision: stale);
    expect(c.joinLines, isFalse);
    final calls = ocr.paths.length;
    await c.extractText(expectedRevision: stale);
    expect(ocr.paths.length, calls);
  });

  test('a preview error drops the image but keeps the text', () async {
    final c = await withImage();
    addTearDown(c.dispose);
    await c.extractText(expectedRevision: c.revision);
    c.textController.text = 'düzenlendi';
    final id = c.selection!.id;

    c.onPreviewError(id + 1);
    expect(c.selection, isNotNull);
    c.onPreviewError(id);
    expect(c.selection, isNull);
    expect(c.textController.text, 'düzenlendi');
    expect(c.errorMessage, isNotNull);
  });

  test('a failed OCR shows an error and releases busy', () async {
    ocr = FakeTextRecognitionService((_) async => throw Exception('x'));
    final c = await withImage();
    addTearDown(c.dispose);
    await c.extractText(expectedRevision: c.revision);
    expect(c.errorMessage, contains('Metin çıkarılamadı'));
    expect(c.isBusy, isFalse);
    expect(c.hasRecognizedText, isFalse);
  });

  test(
    'a late OCR result after dispose changes nothing but cleans up',
    () async {
      final gate = Completer<OcrResult>();
      ocr = FakeTextRecognitionService.withLayout((_) => gate.future);
      final c = await withImage();
      c.rotate(1);
      final run = c.extractText(expectedRevision: c.revision);
      await pumpEventQueue();
      expect(rotation.created, hasLength(1));
      expect(rotation.deleted, isEmpty);

      var notified = 0;
      c.addListener(() => notified++);
      c.dispose();
      gate.complete(const OcrResult('geç sonuç'));
      await run;

      expect(notified, 0);
      expect(rotation.deleted, ['/tmp/rotated_1.jpg']);
    },
  );

  test('recovers a lost image without confirmation', () async {
    final c = create(canRecover: true);
    addTearDown(c.dispose);
    await c.recoverLostImage();
    expect(c.selection?.file.path, '/lost.jpg');
    expect(c.isBusy, isFalse);
  });
}

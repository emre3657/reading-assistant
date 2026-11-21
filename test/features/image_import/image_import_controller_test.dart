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
    c.setJoinLines(false, expectedRevision: c.revision);
    expect(c.textController.text, 'ham metin');
    expect(c.hasRecognizedText, isTrue);

    c.removeImage(expectedRevision: c.revision);
    expect(c.selection, isNull);
    expect(c.quarterTurns, 0);
    expect(c.hasRecognizedText, isFalse);
    expect(c.joinLines, isTrue);
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

  test(
    'batch copy preserves OCR and edits without sharing draft state',
    () async {
      ocr = FakeTextRecognitionService((_) async => 'bir\niki');
      final original = await withImage();
      addTearDown(original.dispose);
      original.rotate(1);
      await original.extractText(expectedRevision: original.revision);
      original.setJoinLines(false, expectedRevision: original.revision);
      original.textController.value = const TextEditingValue(
        text: 'Düzenleme',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      );
      final copy = original.copyForBatch();
      addTearDown(copy.dispose);
      expect(copy.selection?.id, original.selection?.id);
      expect(copy.selection?.file.path, '/a.jpg');
      expect(copy.quarterTurns, 1);
      expect(copy.textController.value, original.textController.value);
      expect(copy.joinLines, isFalse);
      expect(copy.hasEditedText, isTrue);

      copy.setJoinLines(true, expectedRevision: copy.revision);
      expect(copy.textController.text, 'bir iki');
      copy.applySelectedFile(XFile('/replacement.jpg'));
      expect(original.selection?.file.path, '/a.jpg');
      expect(original.quarterTurns, 1);
      expect(original.textController.text, 'Düzenleme');
      expect(original.joinLines, isFalse);
      original.setJoinLines(true, expectedRevision: original.revision);
      expect(original.textController.text, 'bir iki');
    },
  );

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

  test(
    'empty OCR notice clears on text changes, not selection changes',
    () async {
      ocr = FakeTextRecognitionService((_) async => '');
      final c = await withImage();
      addTearDown(c.dispose);
      c.textController.text = 'El yazısı';
      await c.extractText(expectedRevision: c.revision);
      expect(c.infoMessage, contains('Görselde metin bulunamadı'));

      c.textController.selection = const TextSelection.collapsed(offset: 2);
      expect(c.infoMessage, isNotNull);
      var notified = 0;
      c.addListener(() => notified++);
      c.textController.text = 'El yazısı!';
      expect(c.infoMessage, isNull);
      expect(notified, 1);
      c.textController.clear();
      expect(c.infoMessage, isNull);

      await c.extractText(expectedRevision: c.revision);
      expect(c.infoMessage, contains('Görselde metin bulunamadı'));
    },
  );

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

  test(
    'clearing OCR rejects stale confirmations and preserves the image',
    () async {
      final c = await withImage();
      addTearDown(c.dispose);
      c.rotate(1);
      await c.extractText(expectedRevision: c.revision);
      c.setJoinLines(false, expectedRevision: c.revision);
      final revision = c.revision;
      c.textController.text = 'yeni taslak';
      expect(
        c.clearText(expectedRevision: revision, expectedText: 'ham metin'),
        isFalse,
      );
      expect(c.textController.text, 'yeni taslak');
      expect(
        c.clearText(expectedRevision: revision, expectedText: 'yeni taslak'),
        isTrue,
      );
      expect(c.selection!.file.path, '/a.jpg');
      expect(c.quarterTurns, 1);
      expect(c.textController.text, isEmpty);
      expect(c.hasOcrResult, isFalse);
      expect(c.joinLines, isFalse);
      c.setJoinLines(true, expectedRevision: c.revision);
      expect(c.textController.text, isEmpty);
      expect(
        c.clearText(expectedRevision: revision, expectedText: ''),
        isFalse,
      );
    },
  );

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
    c.setJoinLines(false, expectedRevision: stale);
    expect(c.joinLines, isTrue);
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

  test('late recovery does not overwrite a draft', () async {
    final gate = Completer<XFile?>();
    final c = ImageImportController(
      pickerService: FakeImagePickerService(
        canRecoverLostImage: true,
        onRetrieveLost: () => gate.future,
      ),
      textRecognitionService: ocr,
      rotationService: rotation,
      previewImageBuilder: _image,
    );
    addTearDown(c.dispose);
    final recovery = c.recoverLostImage();
    c.textController.text = 'Korunan taslak';
    gate.complete(XFile('/lost.jpg'));
    await recovery;
    expect(c.selection, isNull);
    expect(c.textController.text, 'Korunan taslak');
    expect(c.errorMessage, contains('taslağı korumak'));
  });
}

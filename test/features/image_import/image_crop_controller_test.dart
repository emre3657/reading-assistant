import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_controller.dart';
import 'package:reading_assistant/features/image_import/services/image_crop_service.dart';

import 'test_doubles.dart';

class _DelayedCropService extends ImageCropService {
  final gate = Completer<void>();
  String? output;

  @override
  Future<OwnedCrop> createCrop(String path, int turns, Rect bounds) async {
    await gate.future;
    final result = await super.createCrop(path, turns, bounds);
    output = result.path;
    return result;
  }
}

void main() {
  late Directory directory;
  late File source;
  late FakeTextRecognitionService ocr;

  Future<void> waitForDeletion(WidgetTester tester, String path) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (File(path).existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('crop_controller_');
    source = File('${directory.path}${Platform.pathSeparator}source.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 80, height: 40)));
    ocr = FakeTextRecognitionService((_) async => 'OCR metni');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  ImageImportController create({
    ImageCropService crop = const ImageCropService(),
  }) => ImageImportController(
    pickerService: FakeImagePickerService(),
    textRecognitionService: ocr,
    rotationService: FakeImageRotationService(),
    previewImageBuilder: fileImageProvider,
    cropService: crop,
    initialFile: XFile(source.path),
  );

  testWidgets('crop isolates drafts, preserves join option and supplies OCR', (
    tester,
  ) async {
    final original = create();
    original.setJoinLines(false, expectedRevision: original.revision);
    await original.extractText(expectedRevision: original.revision);
    expect(original.hasOcrResult, isTrue);
    original.textController.text = 'Elle yazılan metin';
    final draft = original.copyForBatch();
    final applied = await tester.runAsync(
      () => draft.applyCrop(
        const Rect.fromLTRB(0, 0, .5, 1),
        expectedRevision: draft.revision,
        expectedText: draft.textController.text,
      ),
    );
    expect(applied, isTrue);
    final cropPath = draft.selection!.file.path;
    expect(original.selection!.file.path, source.path);
    expect(original.textController.text, 'Elle yazılan metin');
    expect(draft.textController.text, isEmpty);
    expect(draft.joinLines, isFalse);
    expect(draft.hasOcrResult, isFalse);
    await draft.extractText(expectedRevision: draft.revision);
    expect(ocr.paths.last, cropPath);

    final copy = draft.copyForBatch();
    draft.dispose();
    await tester.pump();
    expect(File(cropPath).existsSync(), isTrue);
    copy.dispose();
    original.dispose();
    await tester.pump();
    await waitForDeletion(tester, cropPath);
    expect(File(cropPath).existsSync(), isFalse);
    expect(source.existsSync(), isTrue);
  });

  testWidgets('a failed crop preview keeps the prior image and text', (
    tester,
  ) async {
    final controller = ImageImportController(
      pickerService: FakeImagePickerService(),
      textRecognitionService: ocr,
      rotationService: FakeImageRotationService(),
      previewImageBuilder: (file) => file.path == source.path
          ? fileImageProvider(file)
          : FileImage(
              File('${directory.path}${Platform.pathSeparator}missing.png'),
            ),
      initialFile: XFile(source.path),
    );
    controller.textController.text = 'Korunan metin';
    final applied = await tester.runAsync(
      () => controller.applyCrop(
        const Rect.fromLTRB(0, 0, .5, 1),
        expectedRevision: controller.revision,
        expectedText: controller.textController.text,
      ),
    );
    expect(applied, isFalse);
    expect(controller.selection!.file.path, source.path);
    expect(controller.textController.text, 'Korunan metin');
    expect(controller.errorMessage, isNotNull);
    controller.dispose();
  });

  testWidgets('repeated crop after rotation preserves a shared earlier crop', (
    tester,
  ) async {
    final controller = create();
    expect(
      await tester.runAsync(
        () => controller.applyCrop(
          const Rect.fromLTRB(0, 0, .75, 1),
          expectedRevision: controller.revision,
          expectedText: '',
        ),
      ),
      isTrue,
    );
    final previous = controller.selection!.file.path;
    final copy = controller.copyForBatch();
    controller.rotate(1);
    expect(
      await tester.runAsync(
        () => controller.applyCrop(
          const Rect.fromLTRB(0, 0, 1, .5),
          expectedRevision: controller.revision,
          expectedText: '',
        ),
      ),
      isTrue,
    );
    final current = controller.selection!.file.path;
    final pixels = img.decodePng(File(current).readAsBytesSync())!;
    expect((pixels.width, pixels.height), (40, 30));
    expect(controller.quarterTurns, 0);
    await tester.pump();
    expect(File(previous).existsSync(), isTrue);
    expect(copy.selection!.file.path, previous);
    copy.dispose();
    controller.dispose();
    await tester.pump();
    await waitForDeletion(tester, previous);
    await waitForDeletion(tester, current);
    expect(File(previous).existsSync(), isFalse);
    expect(File(current).existsSync(), isFalse);
    expect(source.existsSync(), isTrue);
  });

  testWidgets('OCR keeps a cropped file alive after its screen closes', (
    tester,
  ) async {
    late Completer<String> gate;
    ocr = FakeTextRecognitionService((_) => gate.future);
    final controller = create();
    expect(
      await tester.runAsync(
        () => controller.applyCrop(
          const Rect.fromLTRB(0, 0, .5, 1),
          expectedRevision: controller.revision,
          expectedText: '',
        ),
      ),
      isTrue,
    );
    final path = controller.selection!.file.path;
    await tester.runAsync(() async {
      gate = Completer<String>();
      final pending = controller.extractText(
        expectedRevision: controller.revision,
      );
      controller.dispose();
      expect(File(path).existsSync(), isTrue);
      gate.complete('metin');
      await pending;
    });
    await tester.pump();
    await waitForDeletion(tester, path);
    expect(File(path).existsSync(), isFalse);
    expect(source.existsSync(), isTrue);
  });

  testWidgets('failure and late completion preserve or release the draft', (
    tester,
  ) async {
    final bad = create();
    source.writeAsStringSync('invalid');
    bad.textController.text = 'Korunan metin';
    final applied = await tester.runAsync(
      () => bad.applyCrop(
        const Rect.fromLTRB(0, 0, .5, 1),
        expectedRevision: bad.revision,
        expectedText: bad.textController.text,
      ),
    );
    expect(applied, isFalse);
    expect(bad.selection!.file.path, source.path);
    expect(bad.textController.text, 'Korunan metin');
    expect(bad.errorMessage, isNotNull);
    bad.dispose();

    source.writeAsBytesSync(img.encodePng(img.Image(width: 80, height: 40)));
    final service = _DelayedCropService();
    final closed = create(crop: service);
    final result = await tester.runAsync(() async {
      final pending = closed.applyCrop(
        const Rect.fromLTRB(0, 0, .5, 1),
        expectedRevision: closed.revision,
        expectedText: '',
      );
      closed.dispose();
      service.gate.complete();
      return pending;
    });
    expect(result, isFalse);
    expect(service.output, isNotNull);
    expect(File(service.output!).existsSync(), isFalse);
    expect(source.existsSync(), isTrue);
  });
}

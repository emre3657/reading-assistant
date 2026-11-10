import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/app.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
import 'package:reading_assistant/features/image_import/presentation/widgets/image_preview.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';

import '../listening/fake_preferences_store.dart';
import 'test_doubles.dart';

Future<void> _open(
  WidgetTester tester,
  FakeImagePickerService picker,
  FakeTextRecognitionService ocr, {
  FakeImageRotationService? rotation,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ReadingAssistantApp(
      pickerService: picker,
      rotationService: rotation ?? FakeImageRotationService(),
      textRecognitionService: ocr,
      previewImageBuilder: (_) => ControlledImageProvider(),
      readingPreferences: ReadingPreferences(store: FakePreferencesStore()),
    ),
  );
  await tester.pump();
}

Future<void> _extract(WidgetTester tester) async {
  await tester.tap(find.text('Metni çıkar'));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('camera preview uses existing OCR only when requested', (
    tester,
  ) async {
    final ocr = FakeTextRecognitionService((_) async => 'Kamera metni.');
    await _open(
      tester,
      FakeImagePickerService(onCamera: () async => XFile('/camera.jpg')),
      ocr,
    );
    await tester.tap(find.text('Fotoğraf çek'));
    await tester.pump();
    expect(find.byType(ImagePreview), findsOneWidget);
    expect(ocr.paths, isEmpty);
    await _extract(tester);
    expect(ocr.paths, ['/camera.jpg']);
    expect(find.text('Kamera metni.'), findsOneWidget);
  });

  testWidgets('camera image rotation is used by existing OCR flow', (
    tester,
  ) async {
    final ocr = FakeTextRecognitionService((_) async => 'Kamera metni.');
    final rotation = FakeImageRotationService();
    await _open(
      tester,
      FakeImagePickerService(onCamera: () async => XFile('/camera.jpg')),
      ocr,
      rotation: rotation,
    );
    await tester.tap(find.text('Fotoğraf çek'));
    await tester.pump();
    await tester.tap(find.text('Sağa döndür'));
    await tester.pump();
    await _extract(tester);
    expect(rotation.created, [('/camera.jpg', 1)]);
    expect(ocr.paths, ['/tmp/rotated_1.jpg']);
    expect(rotation.deleted, ['/tmp/rotated_1.jpg']);
  });

  testWidgets('add page does not consume a lost result for another screen', (
    tester,
  ) async {
    var recoveries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ImageImportScreen(
          pickerService: FakeImagePickerService(
            canRecoverLostImage: true,
            onRetrieveLost: () async {
              recoveries++;
              return XFile('/lost.jpg');
            },
          ),
          onSavePage: (_) async {},
        ),
      ),
    );
    await tester.pump();
    expect(recoveries, 0);
    expect(find.byType(ImagePreview), findsNothing);
  });

  testWidgets('camera cancellation and error preserve image and draft', (
    tester,
  ) async {
    var cameraCalls = 0;
    final ocr = FakeTextRecognitionService((_) async => 'Metin.');
    await _open(
      tester,
      FakeImagePickerService(
        onPick: () async => XFile('/gallery.jpg'),
        onCamera: () async {
          if (cameraCalls++ == 0) return null;
          throw StateError('permission denied');
        },
      ),
      ocr,
    );
    await tester.tap(find.text('Galeriden görsel seç'));
    await tester.pump();
    await _extract(tester);
    await tester.enterText(
      find.byKey(const ValueKey('import-text')),
      'Taslak.',
    );
    await tester.pump();
    await tester.tap(find.text('Fotoğraf çek'));
    await tester.pump();
    expect(find.byType(ImagePreview), findsOneWidget);
    expect(find.text('Düzenlediğin metin silinsin mi?'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('import-text')))
          .controller!
          .text,
      'Taslak.',
    );
    await tester.tap(find.text('Fotoğraf çek'));
    await tester.pump();
    expect(find.textContaining('Fotoğraf çekilemedi.'), findsOneWidget);
    expect(find.byType(ImagePreview), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('import-text')))
          .controller!
          .text,
      'Taslak.',
    );
  });

  testWidgets('replacement asks before discarding edited text', (tester) async {
    final ocr = FakeTextRecognitionService((_) async => 'Metin.');
    await _open(
      tester,
      FakeImagePickerService(
        onPick: () async => XFile('/gallery.jpg'),
        onCamera: () async => XFile('/camera.jpg'),
      ),
      ocr,
    );
    await tester.tap(find.text('Galeriden görsel seç'));
    await tester.pump();
    await _extract(tester);
    await tester.enterText(
      find.byKey(const ValueKey('import-text')),
      'Taslak.',
    );
    await tester.pump();
    await tester.tap(find.text('Fotoğraf çek'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Düzenlediğin metin silinsin mi?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('import-text')))
          .controller!
          .text,
      'Taslak.',
    );
    await tester.tap(find.text('Fotoğraf çek'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Metni sil ve değiştir'));
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreview), findsOneWidget);
    expect(find.byKey(const ValueKey('import-text')), findsNothing);
    await _extract(tester);
    expect(ocr.paths, ['/gallery.jpg', '/camera.jpg']);
  });

  testWidgets('pending camera blocks picking and a late result is ignored', (
    tester,
  ) async {
    final gate = Completer<XFile?>();
    var galleryCalls = 0;
    var cameraCalls = 0;
    final ocr = FakeTextRecognitionService((_) async => 'Metin.');
    await _open(
      tester,
      FakeImagePickerService(
        onPick: () async {
          galleryCalls++;
          return null;
        },
        onCamera: () {
          cameraCalls++;
          return gate.future;
        },
      ),
      ocr,
    );
    await tester.tap(find.text('Fotoğraf çek'));
    await tester.pump();
    expect(find.text('Galeriden görsel seç'), findsNothing);
    expect(find.text('Fotoğraf çek'), findsNothing);
    expect(cameraCalls, 1);
    expect(galleryCalls, 0);
    await tester.pumpWidget(const SizedBox());
    gate.complete(XFile('/late.jpg'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(ocr.paths, isEmpty);
  });
}

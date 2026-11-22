import 'dart:convert';

import 'fake_reading_positions.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
import 'package:reading_assistant/features/image_import/presentation/widgets/image_preview.dart';
import 'package:reading_assistant/features/image_import/services/image_picker_service.dart';
import 'package:reading_assistant/features/image_import/services/ocr_result.dart';
import 'package:reading_assistant/features/image_import/services/text_recognition_service.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/presentation/add_page_screen.dart';

import '../listening/fake_speech_service.dart';

class _Picker extends ImagePickerService {
  @override
  bool get canRecoverLostImage => false;
  @override
  Future<XFile?> pickFromGallery({bool recoverToHome = true}) async =>
      XFile('page.png');
  @override
  Future<List<XFile>> pickMultipleFromGallery({
    required bool recoverToHome,
    int? limit,
  }) async => [XFile('page.png')];
  @override
  Future<XFile?> takePhoto({required bool recoverToHome}) async {
    expect(recoverToHome, isFalse);
    return XFile('camera.png');
  }
}

class _Ocr extends TextRecognitionService {
  int calls = 0;
  @override
  Future<OcrResult> recognizeText(String path) async {
    calls++;
    return OcrResult('Görselden çıkarılan sayfa.', lines: const []);
  }
}

class _Store extends DocumentStore with FakeReadingPositions {
  int calls = 0;
  int? owner;
  String? savedText;
  @override
  Future<DocumentPage> appendPage({
    required int documentId,
    required String text,
  }) async {
    calls++;
    owner = documentId;
    savedText = text;
    return DocumentPage(
      id: 99,
      documentId: documentId,
      position: 2,
      text: text,
    );
  }
}

Future<void> _open(WidgetTester tester, _Store store, _Ocr ocr) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final image = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<int>(
              MaterialPageRoute(
                builder: (_) => AddPageScreen(
                  documentId: 7,
                  documentTitle: 'Kitabım',
                  store: store,
                  speechService: FakeSpeechService(),
                  pickerService: _Picker(),
                  textRecognitionService: ocr,
                  previewImageBuilder: (_) => image,
                ),
              ),
            ),
            child: const Text('Aç'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Aç'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('single page validation follows edits and clear', (tester) async {
    final store = _Store();
    await _open(tester, store, _Ocr());
    tester.view.physicalSize = const Size(320, 560);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('save-page'));
    final error = find.text('Sayfa metni boş olamaz.');
    expect(tester.widget<TextButton>(save).onPressed, isNull);
    expect(error, findsNothing);

    await tester.ensureVisible(find.text('Metin yaz veya yapıştır'));
    await tester.tap(find.text('Metin yaz veya yapıştır'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('new-page-text'));
    await tester.enterText(field, 'Taslak');
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(save).onPressed, isNotNull);
    final focus = FocusManager.instance.primaryFocus;

    await tester.enterText(field, '   ');
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(save).onPressed, isNull);
    expect(error.hitTestable(), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(focus));
    final scroll = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('content-scroll')),
        )
        .controller!;
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    final offset = scroll.offset;
    final controller = tester.widget<TextField>(field).controller!;
    controller.text = '  ';
    await tester.pumpAndSettle();
    expect(scroll.offset, offset);

    await tester.enterText(field, 'Yeni metin');
    await tester.pumpAndSettle();
    expect(error, findsNothing);
    expect(tester.widget<TextButton>(save).onPressed, isNotNull);
    await tester.ensureVisible(find.text('Temizle'));
    await tester.tap(find.text('Temizle'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Temizle'));
    await tester.pumpAndSettle();
    expect(error.hitTestable(), findsOneWidget);
    expect(tester.widget<TextButton>(save).onPressed, isNull);
    expect(store.calls, 0);
  });

  testWidgets('empty page error is below the image after OCR text is deleted', (
    tester,
  ) async {
    await _open(tester, _Store(), _Ocr());
    tester.view.physicalSize = const Size(320, 560);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Fotoğraf çek'));
    await tester.tap(find.text('Fotoğraf çek'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Metni çıkar'));
    await tester.tap(find.text('Metni çıkar'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('new-page-text'));
    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    final error = find.text('Sayfa metni boş olamaz.');
    expect(error.hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(error).dy,
      greaterThan(tester.getBottomLeft(find.byType(ImagePreview)).dy),
    );
  });

  testWidgets('offers gallery and manual entry in one screen', (tester) async {
    await _open(tester, _Store(), _Ocr());
    expect(find.text('Galeriden görsel seç'), findsOneWidget);
    expect(find.text('Fotoğraf çek'), findsOneWidget);
    expect(find.text('Metin yaz veya yapıştır'), findsOneWidget);
    expect(find.text('Kitabım'), findsOneWidget);
    expect(find.text('Metni kullan'), findsNothing);
    expect(find.byType(ImageImportScreen), findsOneWidget);
  });

  testWidgets('camera OCR saves the new page to the correct content', (
    tester,
  ) async {
    final store = _Store();
    final ocr = _Ocr();
    await _open(tester, store, ocr);
    await tester.tap(find.text('Fotoğraf çek'));
    await tester.pumpAndSettle();
    expect(ocr.calls, 0);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('save-page')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Metni çıkar'));
    await tester.pumpAndSettle();
    expect(ocr.calls, 1);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('save-page')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('save-page')));
    await tester.pumpAndSettle();
    expect(store.owner, 7);
    expect(store.savedText, 'Görselden çıkarılan sayfa.');
    expect(store.calls, 1);
  });

  testWidgets('gallery OCR stays inline and saves directly to same content', (
    tester,
  ) async {
    final store = _Store();
    final ocr = _Ocr();
    await _open(tester, store, ocr);
    await tester.tap(find.text('Galeriden görsel seç'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageImportScreen), findsOneWidget);
    expect(find.text('Metni çıkar'), findsOneWidget);
    await tester.tap(find.text('Metni çıkar'));
    await tester.pumpAndSettle();
    expect(ocr.calls, 1);
    expect(find.text('Görselden çıkarılan sayfa.'), findsOneWidget);
    expect(find.text('Metni kullan'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('save-page')));
    await tester.pumpAndSettle();
    expect(store.calls, 1);
    expect(store.owner, 7);
    expect(store.savedText, 'Görselden çıkarılan sayfa.');
    expect(find.byType(AddPageScreen), findsNothing);
  });

  testWidgets('continue editing preserves manual draft', (tester) async {
    // Failure/retry and double-save coverage remains in page_management_test.
    final store = _Store();
    await _open(tester, store, _Ocr());
    await tester.tap(find.text('Metin yaz veya yapıştır'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('new-page-text')),
      'Taslak.',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Düzenlemeye devam et'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('new-page-text')))
          .controller!
          .text,
      'Taslak.',
    );
    expect(store.calls, 0);
  });

  testWidgets(
    'new page clear keeps the editor open and close restores choice',
    (tester) async {
      final store = _Store();
      await _open(tester, store, _Ocr());
      await tester.tap(find.text('Metin yaz veya yapıştır'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('new-page-text'));
      await tester.enterText(field, 'Taslak sayfa.');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Temizle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'Taslak sayfa.');
      await tester.tap(find.text('Temizle'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Temizle'));
      await tester.pumpAndSettle();
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(store.calls, 0);
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(find.text('Metin yaz veya yapıştır'), findsOneWidget);
      expect(store.calls, 0);
    },
  );
}

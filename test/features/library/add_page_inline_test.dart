import 'dart:convert';

import 'fake_reading_positions.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
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
  Future<XFile?> pickFromGallery() async => XFile('page.png');
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
            onPressed: () => Navigator.of(context).push<bool>(
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
    await tester.tap(find.text('Metni çıkar'));
    await tester.pumpAndSettle();
    expect(ocr.calls, 1);
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
}

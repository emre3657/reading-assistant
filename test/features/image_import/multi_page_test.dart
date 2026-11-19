import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
import 'package:reading_assistant/features/image_import/presentation/multi_page_screen.dart';
import 'package:reading_assistant/features/image_import/services/image_picker_service.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/add_page_screen.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';

import '../listening/fake_preferences_store.dart';
import '../listening/fake_speech_service.dart';
import 'test_doubles.dart';

final _image = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, Widget screen) async {
  final preferences = ReadingPreferences(store: FakePreferencesStore());
  await preferences.load();
  await tester.pumpWidget(
    ReadingPreferencesScope(
      preferences: preferences,
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _draft(int id) => find.byKey(ValueKey('draft-$id'));
Finder _action(int id, String label) =>
    find.descendant(of: _draft(id), matching: find.text(label));
Finder get _field => find.byKey(const ValueKey('import-text'));

class _BatchStore extends DocumentStore {
  List<String>? texts;
  int? owner;
  String? title;
  DocumentCategory? category;
  @override
  Future<List<DocumentCategory>> categories() async => [
    DocumentCategory.note,
    DocumentCategory.book,
  ];
  @override
  Future<int> savePages({
    required String title,
    required DocumentCategory category,
    required List<String> texts,
  }) async {
    this.title = title;
    this.category = category;
    this.texts = texts;
    return 1;
  }

  @override
  Future<void> appendPages({
    required int documentId,
    required List<String> texts,
  }) async {
    owner = documentId;
    this.texts = texts;
  }
}

Future<void> _open(WidgetTester tester, int id) async {
  await _tap(
    tester,
    find.descendant(of: _draft(id), matching: find.byType(InkWell)).first,
  );
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lost multi-selection opens all recovered drafts', (
    tester,
  ) async {
    await _show(
      tester,
      ImageImportScreen(
        pickerService: FakeImagePickerService(
          canRecoverLostImage: true,
          onRetrieveLost: () async =>
              throw LostMultipleImagesException([XFile('a'), XFile('b')]),
        ),
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        speechService: FakeSpeechService(),
        previewImageBuilder: (_) => _image,
      ),
    );
    expect(_draft(0), findsOneWidget);
    expect(_draft(1), findsOneWidget);
  });

  testWidgets(
    'batch controls remain reachable at large text on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _show(
        tester,
        MultiPageScreen(
          files: [XFile('a'), XFile('b')],
          pickerService: FakeImagePickerService(),
          textRecognitionService: FakeTextRecognitionService(
            (path) async => path,
          ),
          rotationService: FakeImageRotationService(),
          previewImageBuilder: (_) => _image,
          speechService: FakeSpeechService(),
        ),
      );
      await tester.ensureVisible(_action(1, 'Yukarı'));
      await tester.pumpAndSettle();
      expect(_action(1, 'Yukarı').hitTestable(), findsOneWidget);
      await _tap(tester, _action(1, 'Yukarı'));
      await tester.ensureVisible(find.byKey(const ValueKey('save-batch')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('save-batch')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty page explanation is visible at large system text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _show(
      tester,
      MultiPageScreen(
        files: [XFile('a')],
        pickerService: FakeImagePickerService(),
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('save-batch')),
      200,
    );
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    final error = find.text('Bu sayfanın metni boş. Metni çıkarın veya yazın.');
    expect(error.hitTestable(), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'multi selection cancellation preserves existing text and selection',
    (tester) async {
      final picker = FakeImagePickerService(onPickMultiple: () async => []);
      await _show(
        tester,
        ImageImportScreen(
          pickerService: picker,
          speechService: FakeSpeechService(),
          previewImageBuilder: (_) => _image,
        ),
      );
      await _tap(tester, find.text('Metin yaz veya yapıştır'));
      await tester.enterText(_field, 'Korunan taslak');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('pick-multiple')));
      expect(
        tester.widget<TextField>(_field).controller!.text,
        'Korunan taslak',
      );
      expect(find.byType(MultiPageScreen), findsNothing);
    },
  );

  testWidgets('new document asks for title and category once', (tester) async {
    final store = _BatchStore();
    await _show(
      tester,
      ImageImportScreen(
        pickerService: FakeImagePickerService(
          onPickMultiple: () async => [XFile('a')],
        ),
        textRecognitionService: FakeTextRecognitionService(
          (path) async => 'Bir',
        ),
        rotationService: FakeImageRotationService(),
        speechService: FakeSpeechService(),
        previewImageBuilder: (_) => _image,
        store: store,
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('pick-multiple')));
    await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    await tester.enterText(find.byType(TextFormField).first, 'Belge');
    await _tap(tester, find.text('1 sayfayı ekle').last);
    expect(store.title, 'Belge');
    expect(store.category, DocumentCategory.note);
    expect(store.texts, ['Bir']);
    expect(find.byType(MultiPageScreen), findsNothing);
  });

  testWidgets('existing document appends chosen pages to its owner', (
    tester,
  ) async {
    final store = _BatchStore();
    await _show(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<int>(
              context,
              MaterialPageRoute(
                builder: (_) => AddPageScreen(
                  documentId: 7,
                  documentTitle: 'Kitap',
                  store: store,
                  pickerService: FakeImagePickerService(
                    onPickMultiple: () async => [XFile('a'), XFile('b')],
                  ),
                  textRecognitionService: FakeTextRecognitionService(
                    (path) async => path,
                  ),
                  rotationService: FakeImageRotationService(),
                  previewImageBuilder: (_) => _image,
                  speechService: FakeSpeechService(),
                ),
              ),
            ),
            child: const Text('Aç'),
          ),
        ),
      ),
    );
    await _tap(tester, find.text('Aç'));
    await _tap(tester, find.byKey(const ValueKey('pick-multiple')));
    await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    expect(store.owner, 7);
    expect(store.texts, ['a', 'b']);
    expect(find.byType(AddPageScreen), findsNothing);
  });

  testWidgets('existing page draft is not discarded without confirmation', (
    tester,
  ) async {
    final store = _BatchStore();
    await _show(
      tester,
      AddPageScreen(
        documentId: 7,
        documentTitle: 'Kitap',
        store: store,
        pickerService: FakeImagePickerService(
          onPickMultiple: () async => [XFile('a')],
        ),
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
      ),
    );
    await _tap(tester, find.text('Metin yaz veya yapıştır'));
    final field = find.byKey(const ValueKey('new-page-text'));
    await tester.enterText(field, 'Taslağım');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('pick-multiple')));
    expect(find.text('Mevcut sayfa taslağı kapatılsın mı?'), findsOneWidget);
    await _tap(tester, find.text('Vazgeç'));
    expect(tester.widget<TextField>(field).controller!.text, 'Taslağım');
    expect(find.byType(MultiPageScreen), findsNothing);
  });

  testWidgets('leaving during OCR drops late results and stops processing', (
    tester,
  ) async {
    final gate = Completer<String>();
    final ocr = FakeTextRecognitionService((path) => gate.future);
    await _show(
      tester,
      ImageImportScreen(
        pickerService: FakeImagePickerService(
          onPickMultiple: () async => [XFile('a'), XFile('b')],
        ),
        textRecognitionService: ocr,
        rotationService: FakeImageRotationService(),
        speechService: FakeSpeechService(),
        previewImageBuilder: (_) => _image,
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('pick-multiple')));
    await tester.tap(find.text('Tüm sayfalardan metin çıkar'));
    await tester.pump();
    expect(find.text('1 / 2 işleniyor'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-batch')))
          .onPressed,
      isNull,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Kaydetmeden çık'));
    gate.complete('geç sonuç');
    await tester.pumpAndSettle();
    expect(ocr.paths, ['a']);
    expect(find.byType(MultiPageScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'drafts stay with images through OCR, reorder, removal and retry',
    (tester) async {
      var failures = 0;
      final ocr = FakeTextRecognitionService((path) async {
        if (path == 'b' && failures++ == 0) throw StateError('OCR');
        return '$path ilk\nsatır';
      });
      final picker = FakeImagePickerService(
        onPickMultiple: () async => [XFile('a'), XFile('b'), XFile('c')],
      );
      await _show(
        tester,
        ImageImportScreen(
          pickerService: picker,
          textRecognitionService: ocr,
          rotationService: FakeImageRotationService(),
          speechService: FakeSpeechService(),
          previewImageBuilder: (_) => _image,
        ),
      );
      await _tap(tester, find.byKey(const ValueKey('pick-multiple')));
      await _open(tester, 0);
      await tester.enterText(_field, 'Elle yazılan');
      await _back(tester);
      await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
      expect(ocr.paths, ['b', 'c']);
      expect(_action(1, 'Yeniden dene'), findsOneWidget);
      await _tap(tester, _action(1, 'Yeniden dene'));
      expect(ocr.paths, ['b', 'c', 'b']);
      await _open(tester, 1);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      await _tap(tester, find.text('Metni çıkar'));
      expect(find.text('Metnin üzerine yazılsın mı?'), findsOneWidget);
      await _tap(tester, find.text('Vazgeç'));
      expect(ocr.paths, ['b', 'c', 'b']);
      await _tap(tester, find.text('Satırları birleştir'));
      expect(tester.widget<TextField>(_field).controller!.text, 'b ilk satır');
      await tester.enterText(_field, 'b düzeltme');
      await _tap(tester, find.text('Satırları birleştir'));
      expect(find.text('Düzenlediğin metin silinsin mi?'), findsOneWidget);
      await _tap(tester, find.text('Vazgeç'));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      expect(tester.widget<TextField>(_field).controller!.text, 'b düzeltme');
      await _tap(tester, find.text('Sağa döndür'));
      await _back(tester);
      await _tap(tester, _action(1, 'Yukarı'));
      await _open(tester, 2);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      await _back(tester);
      await _tap(tester, _action(2, 'Kaldır'));
      await _tap(tester, find.text('Sayfayı kaldır'));
      await _open(tester, 1);
      expect(tester.widget<TextField>(_field).controller!.text, 'b düzeltme');
      expect(find.textContaining('90° döndürüldü'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      await _back(tester);
      await _open(tester, 0);
      expect(tester.widget<TextField>(_field).controller!.text, 'Elle yazılan');
      await _tap(tester, find.text('Temizle'));
      await _tap(tester, find.text('Vazgeç'));
      expect(tester.widget<TextField>(_field).controller!.text, 'Elle yazılan');
      await _tap(tester, find.text('Temizle'));
      await _tap(tester, find.text('Temizle').last);
      expect(tester.widget<TextField>(_field).controller!.text, isEmpty);
      expect(find.text('Metni çıkar'), findsOneWidget);
      await _back(tester);
      await _open(tester, 1);
      expect(tester.widget<TextField>(_field).controller!.text, 'b düzeltme');
      await _back(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Vazgeç'));
      expect(find.byType(MultiPageScreen), findsOneWidget);
      expect(_draft(0), findsOneWidget);
    },
  );

  testWidgets('blank validation and failed save keep drafts; save is guarded', (
    tester,
  ) async {
    final completer = Completer<void>();
    var calls = 0;
    List<String>? saved;
    await _show(
      tester,
      MultiPageScreen(
        files: [XFile('a'), XFile('b')],
        pickerService: FakeImagePickerService(),
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
        onSavePages: (texts) async {
          calls++;
          saved = texts;
          if (calls == 1) throw StateError('save');
          await completer.future;
        },
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    expect(find.text('1. sayfa'), findsOneWidget);
    final error = find.text('Bu sayfanın metni boş. Metni çıkarın veya yazın.');
    expect(error, findsOneWidget);
    expect(error.hitTestable(), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.enterText(_field, '   ');
    await tester.pumpAndSettle();
    expect(error, findsOneWidget);
    await tester.enterText(_field, 'Bir');
    await tester.pumpAndSettle();
    expect(error, findsNothing);
    await _back(tester);
    expect(find.textContaining('Boş sayfalar: 2'), findsOneWidget);
    expect(_action(0, 'Sayfa metni boş.'), findsNothing);
    expect(_action(1, 'Sayfa metni boş.'), findsOneWidget);
    await _open(tester, 1);
    expect(error, findsOneWidget);
    await tester.enterText(_field, 'İki');
    await tester.pumpAndSettle();
    expect(error, findsNothing);
    await _back(tester);
    expect(find.text('Sayfa metni boş.'), findsNothing);
    await _tap(tester, _action(1, 'Yukarı'));
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    expect(calls, 1);
    expect(saved, ['İki', 'Bir']);
    expect(find.textContaining('Taslaklar korundu'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-batch')));
    await tester.pump();
    expect(calls, 2);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-batch')))
          .onPressed,
      isNull,
    );
    completer.complete();
    await tester.pumpAndSettle();
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/app.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
import 'package:reading_assistant/features/image_import/presentation/multi_page_screen.dart';
import 'package:reading_assistant/features/image_import/services/image_picker_service.dart';
import 'package:reading_assistant/features/library/data/backup_data.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/backup_screen.dart';
import 'package:reading_assistant/features/library/presentation/library_screen.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';

import '../image_import/test_doubles.dart';
import '../listening/fake_preferences_store.dart';
import '../listening/fake_speech_service.dart';
import 'fake_reading_positions.dart';

final _image = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

class _Store extends FakePreferencesStore with FakeReadingPositions {
  final document = SavedDocument(
    id: 1,
    title: 'Enjekte edilen belge',
    category: DocumentCategory.note,
    text: 'İlk sayfa.',
    createdAt: DateTime(2026),
  );
  final List<DocumentPage> storedPages = [
    const DocumentPage(id: 10, documentId: 1, position: 0, text: 'İlk sayfa.'),
  ];
  int listCalls = 0;
  int backupCalls = 0;

  @override
  Future<List<SavedDocument>> list() async {
    listCalls++;
    return [document];
  }

  @override
  Future<SavedDocument?> getDocument(int id) async => id == 1 ? document : null;

  @override
  Future<List<DocumentPage>> pages(int documentId) async =>
      List.of(storedPages);

  @override
  Future<DocumentPage> appendPage({
    required int documentId,
    required String text,
  }) async {
    final page = DocumentPage(
      id: 10 + storedPages.length,
      documentId: documentId,
      position: storedPages.length,
      text: text,
    );
    storedPages.add(page);
    return page;
  }

  @override
  Future<void> appendPages({
    required int documentId,
    required List<String> texts,
  }) async {
    for (final text in texts) {
      await appendPage(documentId: documentId, text: text);
    }
  }

  @override
  Future<bool> updatePageText({
    required int documentId,
    required int pageId,
    required String text,
  }) async {
    final index = storedPages.indexWhere((page) => page.id == pageId);
    if (index < 0) return false;
    storedPages[index] = DocumentPage(
      id: pageId,
      documentId: documentId,
      position: index,
      text: text,
    );
    return true;
  }

  @override
  Future<BackupData> backupSnapshot() async {
    backupCalls++;
    return BackupData.fromTables({
      'categories': [
        {'id': 'note', 'label': 'Not', 'normalized_label': 'not'},
      ],
      'documents': [
        {'id': 1, 'title': document.title, 'category': 'note', 'created_at': 7},
      ],
      'pages': [
        for (final page in storedPages)
          {
            'id': page.id,
            'document_id': 1,
            'position': page.position,
            'text': page.text,
          },
      ],
      'reading_positions': [],
      'bookmarks': [],
      'reading_preferences': [],
    });
  }
}

class _Picker extends ImagePickerService {
  @override
  bool get canRecoverLostImage => false;
  @override
  Future<List<XFile>> pickMultipleFromGallery({
    required bool recoverToHome,
    int? limit,
  }) async => [XFile('a'), XFile('b')];
}

class _Files extends BackupFileService {
  Uint8List? bytes;

  @override
  Future<bool> save(Uint8List bytes, String fileName) async {
    this.bytes = bytes;
    return true;
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('injected store reaches library, editors, batch and backup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _Store()..values = {'text_size': 'large'};
    final files = _Files();
    await tester.pumpWidget(
      ReadingAssistantApp(
        store: store,
        pickerService: _Picker(),
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
        backupFileService: files,
      ),
    );
    await tester.pumpAndSettle();
    final preferences = tester
        .widget<ReadingPreferencesScope>(
          find.byType(ReadingPreferencesScope).first,
        )
        .preferences;
    expect(preferences.store, same(store));
    expect(preferences.textSize, ReadingTextSize.large);

    await _tap(tester, find.byTooltip('Kayıtlarım'));
    expect(store.listCalls, greaterThan(0));
    expect(
      tester.widget<LibraryScreen>(find.byType(LibraryScreen)).store,
      same(store),
    );
    await _tap(tester, find.byKey(const ValueKey('document-1')));
    await _tap(tester, find.byKey(const ValueKey('page-10')));
    await _tap(tester, find.byIcon(Icons.edit_outlined));
    await tester.enterText(
      find.byKey(const ValueKey('document-text')),
      'Düzenlenen sayfa.',
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('save-document')));
    expect(store.storedPages.first.text, 'Düzenlenen sayfa.');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(const ValueKey('add-page')));
    await _tap(tester, find.text('Metin yaz veya yapıştır'));
    await tester.enterText(
      find.byKey(const ValueKey('new-page-text')),
      'Tek sayfa.',
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('save-page')));
    expect(store.storedPages.last.text, 'Tek sayfa.');

    await _tap(tester, find.byKey(const ValueKey('add-page')));
    await _tap(tester, find.text('Galeriden görsel seç'));
    expect(find.byType(MultiPageScreen), findsOneWidget);
    await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    expect(store.storedPages.map((p) => p.text), [
      'Düzenlenen sayfa.',
      'Tek sayfa.',
      'a',
      'b',
    ]);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Diğer seçenekler'));
    await _tap(tester, find.text('Yedekle ve geri yükle'));
    expect(
      tester.widget<BackupScreen>(find.byType(BackupScreen)).store,
      same(store),
    );
    await tester.tap(find.text('Yedek oluştur'));
    await tester.pump();
    for (var i = 0; i < 50 && files.bytes == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(store.backupCalls, 1);
    expect(BackupData.decode(files.bytes!).pageCount, 4);
  });

  testWidgets('two app roots keep preferences and stores independent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final a = _Store()..values = {'text_size': 'large'};
    final b = _Store()..values = {'text_size': 'normal'};
    await tester.pumpWidget(
      Row(
        textDirection: TextDirection.ltr,
        children: [
          Expanded(
            child: ReadingAssistantApp(
              key: const ValueKey('a'),
              store: a,
              pickerService: _Picker(),
            ),
          ),
          Expanded(
            child: ReadingAssistantApp(
              key: const ValueKey('b'),
              store: b,
              pickerService: _Picker(),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    ReadingPreferences preferences(String key) => tester
        .widget<ReadingPreferencesScope>(
          find
              .descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(ReadingPreferencesScope),
              )
              .first,
        )
        .preferences;
    final first = preferences('a');
    final second = preferences('b');
    expect(first.store, same(a));
    expect(second.store, same(b));
    expect(first.textSize, ReadingTextSize.large);
    expect(second.textSize, ReadingTextSize.normal);
    first.setTextSize(ReadingTextSize.extraLarge);
    await first.pendingWrites;
    expect(a.values!['text_size'], 'extraLarge');
    expect(b.values!['text_size'], 'normal');
    expect(second.textSize, ReadingTextSize.normal);
  });

  testWidgets('standalone import shares its preferences across pushed routes', (
    tester,
  ) async {
    final store = _Store()..values = {'text_size': 'large'};
    await tester.pumpWidget(
      MaterialApp(
        home: ImageImportScreen(
          store: store,
          pickerService: _Picker(),
          previewImageBuilder: (_) => _image,
          speechService: FakeSpeechService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Kayıtlarım'));
    final preferences = ReadingPreferencesScope.of(
      tester.element(find.byType(LibraryScreen)),
    );
    await _tap(tester, find.byKey(const ValueKey('document-1')));
    await _tap(tester, find.byKey(const ValueKey('page-10')));
    expect(
      ReadingPreferencesScope.of(
        tester.element(find.byType(SavedDocumentScreen)),
      ),
      same(preferences),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('add-page')));
    expect(
      ReadingPreferencesScope.of(
        tester.element(find.byType(ImageImportScreen).last),
      ),
      same(preferences),
    );
    await _tap(tester, find.text('Galeriden görsel seç'));
    final draft = find.byKey(const ValueKey('draft-0'));
    await _tap(
      tester,
      find.descendant(of: draft, matching: find.byType(InkWell)).first,
    );
    expect(
      ReadingPreferencesScope.of(
        tester.element(find.byType(ImageImportScreen).last),
      ),
      same(preferences),
    );
  });

  testWidgets('external preferences remain owned by caller', (tester) async {
    final store = _Store();
    final preferences = ReadingPreferences(store: store);
    await tester.pumpWidget(
      ReadingAssistantApp(
        store: store,
        readingPreferences: preferences,
        pickerService: _Picker(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    preferences.setTextSize(ReadingTextSize.large);
    await preferences.pendingWrites;
    expect(store.values!['text_size'], 'large');
    preferences.dispose();
  });

  testWidgets('preferences alone select their store', (tester) async {
    final store = _Store();
    final preferences = ReadingPreferences(store: store);
    await tester.pumpWidget(
      ReadingAssistantApp(
        readingPreferences: preferences,
        pickerService: _Picker(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ImageImportScreen>(find.byType(ImageImportScreen)).store,
      same(store),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    preferences.dispose();
  });

  testWidgets('mismatched store and preferences are rejected', (tester) async {
    final preferences = ReadingPreferences(store: _Store());
    await tester.pumpWidget(
      ReadingAssistantApp(
        store: _Store(),
        readingPreferences: preferences,
        pickerService: _Picker(),
      ),
    );
    expect(tester.takeException(), isA<ArgumentError>());
    preferences.dispose();
  });

  testWidgets('replacing root store resets routes to the new dependencies', (
    tester,
  ) async {
    final first = _Store();
    final second = _Store()..values = {'text_size': 'large'};
    await tester.pumpWidget(
      ReadingAssistantApp(store: first, pickerService: _Picker()),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Kayıtlarım'));
    await tester.pumpWidget(
      ReadingAssistantApp(store: second, pickerService: _Picker()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsNothing);
    final scope = tester.widget<ReadingPreferencesScope>(
      find.byType(ReadingPreferencesScope).first,
    );
    expect(scope.preferences.store, same(second));
    expect(scope.preferences.textSize, ReadingTextSize.large);
    await _tap(tester, find.byTooltip('Kayıtlarım'));
    expect(second.listCalls, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('owned preferences finish pending load after unmount', (
    tester,
  ) async {
    final store = _Store()..loadGate = Completer<void>();
    await tester.pumpWidget(
      ReadingAssistantApp(store: store, pickerService: _Picker()),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    store.loadGate!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('owned preferences finish pending writes after unmount', (
    tester,
  ) async {
    final store = _Store()..saveGate = Completer<void>();
    await tester.pumpWidget(
      ReadingAssistantApp(store: store, pickerService: _Picker()),
    );
    await tester.pumpAndSettle();
    final preferences = tester
        .widget<ReadingPreferencesScope>(
          find.byType(ReadingPreferencesScope).first,
        )
        .preferences;
    preferences.setTextSize(ReadingTextSize.large);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    store.saveGate!.complete();
    await preferences.pendingWrites;
    expect(store.values!['text_size'], 'large');
    expect(tester.takeException(), isNull);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_schema.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/document_details_dialog.dart';
import 'package:reading_assistant/features/library/presentation/library_screen.dart';
import 'package:reading_assistant/features/library/presentation/save_document_dialog.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../listening/fake_preferences_store.dart';
import '../listening/fake_speech_service.dart';
import 'fake_reading_positions.dart';

class _Store extends DocumentStore with FakeReadingPositions {
  final items = <DocumentCategory>[...DocumentCategory.values];
  SavedDocument? document;
  bool failCategory = false;
  int next = 0;

  @override
  Future<List<DocumentCategory>> categories() async => List.of(items);

  @override
  Future<DocumentCategory> createCategory(String name) async {
    if (failCategory) throw StateError('disk');
    final label = name.trim();
    if (items.any(
      (item) =>
          normalizeCategoryName(item.label) == normalizeCategoryName(label),
    )) {
      throw const DuplicateCategoryException();
    }
    final category = DocumentCategory('custom_${next++}', label);
    items.add(category);
    return category;
  }

  @override
  Future<DocumentCategory> renameCategory(
    DocumentCategory category,
    String name,
  ) async {
    if (failCategory) throw StateError('disk');
    final label = name.trim();
    if (items.any(
      (item) =>
          item != category &&
          normalizeCategoryName(item.label) == normalizeCategoryName(label),
    )) {
      throw const DuplicateCategoryException();
    }
    final renamed = DocumentCategory(category.name, label);
    items[items.indexOf(category)] = renamed;
    return renamed;
  }

  @override
  Future<int> save({
    required String title,
    required DocumentCategory category,
    required String text,
  }) async {
    document = SavedDocument(
      id: 1,
      title: title.trim(),
      category: category,
      text: text,
      createdAt: DateTime(2026),
    );
    return 1;
  }

  @override
  Future<List<SavedDocument>> list() async {
    final saved = document;
    if (saved == null) return [];
    return [
      SavedDocument(
        id: saved.id,
        title: saved.title,
        category: items.firstWhere((item) => item == saved.category),
        text: saved.text,
        createdAt: saved.createdAt,
      ),
    ];
  }

  @override
  Future<SavedDocument?> getDocument(int id) async =>
      (await list()).firstOrNull;

  @override
  Future<List<DocumentPage>> pages(int documentId) async => [
    DocumentPage(
      id: 1,
      documentId: documentId,
      position: 0,
      text: document!.text,
    ),
  ];

  @override
  Future<bool> updateDetails({
    required int id,
    required String title,
    required DocumentCategory category,
  }) async {
    document = SavedDocument(
      id: id,
      title: title,
      category: category,
      text: document!.text,
      createdAt: document!.createdAt,
    );
    return true;
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();

  test(
    'SQLite category identities, Turkish uniqueness and reopening',
    () async {
      final dir = await Directory.systemTemp.createTemp('categories-');
      final path = '${dir.path}${Platform.pathSeparator}test.db';
      OpenDatabaseOptions options() => OpenDatabaseOptions(
        version: documentDatabaseVersion,
        singleInstance: false,
        onConfigure: configureDocumentDatabase,
        onCreate: createDocumentSchema,
        onUpgrade: upgradeDocumentSchema,
        onOpen: ensureBuiltInCategories,
      );
      try {
        final db = await databaseFactoryFfi.openDatabase(
          path,
          options: options(),
        );
        final store = DocumentStore(databaseOpener: () async => db);
        final renamedBook = await store.renameCategory(
          DocumentCategory.book,
          ' Okuduklarım ',
        );
        final custom = await store.createCategory(' Kitap ');
        final istanbul = await store.createCategory('İstanbul');
        await expectLater(store.createCategory('   '), throwsArgumentError);
        await expectLater(
          store.createCategory('istanbul'),
          throwsA(isA<DuplicateCategoryException>()),
        );
        final isik = await store.createCategory('IŞIK');
        await expectLater(
          store.createCategory('ışık'),
          throwsA(isA<DuplicateCategoryException>()),
        );
        expect((await store.renameCategory(isik, 'ışık')).name, isik.name);
        await store.createCategory('Isik');
        await store.createCategory('Şeker');
        await store.createCategory('Seker');
        await expectLater(
          store.renameCategory(renamedBook, ' KİTAP '),
          throwsA(isA<DuplicateCategoryException>()),
        );
        final bookId = await store.save(
          title: 'Kitap',
          category: renamedBook,
          text: 'Bir.',
        );
        final customId = await store.save(
          title: 'Özel',
          category: custom,
          text: 'İki.',
        );
        await store.renameCategory(istanbul, 'Gezi');
        await db.close();
        final reopened = await databaseFactoryFfi.openDatabase(
          path,
          options: options(),
        );
        final restored = DocumentStore(databaseOpener: () async => reopened);
        expect(
          (await restored.getDocument(bookId))!.category.label,
          'Okuduklarım',
        );
        expect(
          (await restored.getDocument(bookId))!.category,
          DocumentCategory.book,
        );
        expect((await restored.getDocument(customId))!.category.label, 'Kitap');
        expect(
          (await restored.getDocument(customId))!.category,
          isNot(DocumentCategory.book),
        );
        expect(
          (await restored.categories()).any(
            (c) => c.name == istanbul.name && c.label == 'Gezi',
          ),
          isTrue,
        );
        await reopened.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'v6 migration preserves document, pages, position and preferences',
    () async {
      final dir = await Directory.systemTemp.createTemp('category-migration-');
      final path = '${dir.path}${Platform.pathSeparator}test.db';
      try {
        final old = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 6,
            singleInstance: false,
            onConfigure: configureDocumentDatabase,
            onCreate: (db, _) async {
              await db.execute(createDocumentsSql);
              await db.execute(createPagesSql);
              await db.execute(createReadingPositionsSql);
              await db.execute(invalidateReadingPositionSql);
              await db.execute(createReadingPreferencesSql);
              await db.execute(addFollowSentenceSql);
              await db.execute(addReadingTextSizeSql);
            },
          ),
        );
        await old.insert('documents', {
          'id': 42,
          'title': 'Önce',
          'category': 'book',
          'created_at': 7,
        });
        await old.insert('pages', {
          'id': 9,
          'document_id': 42,
          'position': 3,
          'text': 'Bir. İki.',
        });
        await old.insert('reading_positions', {
          'document_id': 42,
          'page_id': 9,
          'sentence_index': 1,
          'page_text': 'Bir. İki.',
        });
        await old.insert('reading_preferences', {
          'id': 1,
          'speed': 'fast',
          'auto_next_page': 1,
          'follow_sentence': 1,
          'text_size': 'large',
        });
        await old.close();
        final db = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: documentDatabaseVersion,
            singleInstance: false,
            onConfigure: configureDocumentDatabase,
            onUpgrade: upgradeDocumentSchema,
          ),
        );
        final store = DocumentStore(databaseOpener: () async => db);
        expect((await store.getDocument(42))!.category, DocumentCategory.book);
        expect((await store.pages(42)).single.position, 3);
        expect((await store.readingPosition(42))!.sentenceIndex, 1);
        expect((await store.loadReadingPreferences())!['text_size'], 'large');
        await store.renameCategory(DocumentCategory.book, 'Okuduklarım');
        expect((await store.getDocument(42))!.category.label, 'Okuduklarım');
        await db.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  testWidgets('create in save form, retry errors, rename and reload library', (
    tester,
  ) async {
    final store = _Store();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) =>
                    SaveDocumentDialog(text: 'Metin.', store: store),
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await _tap(tester, find.text('Aç'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Başlık'),
      'Korunan başlık',
    );
    await _tap(tester, find.byType(DropdownButtonFormField<DocumentCategory>));
    await _tap(tester, find.text('Yeni kategori oluştur').last);
    await _tap(tester, find.widgetWithText(FilledButton, 'Kaydet').last);
    expect(find.text('Bir kategori adı yaz.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('category-name')), 'nOT');
    await _tap(tester, find.widgetWithText(FilledButton, 'Kaydet').last);
    expect(find.text('Bu adla bir kategori zaten var.'), findsOneWidget);
    store.failCategory = true;
    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      ' Tarifler ',
    );
    await _tap(tester, find.widgetWithText(FilledButton, 'Kaydet').last);
    expect(
      find.text('Kategori kaydedilemedi. Tekrar deneyebilirsin.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('category-name')))
          .controller!
          .text,
      ' Tarifler ',
    );
    store.failCategory = false;
    await _tap(tester, find.widgetWithText(FilledButton, 'Kaydet').last);
    expect(find.text('Tarifler'), findsOneWidget);
    expect(find.text('Korunan başlık'), findsOneWidget);
    expect(store.document, isNull);
    await _tap(tester, find.widgetWithText(FilledButton, 'Kaydet'));
    expect(store.document!.category.label, 'Tarifler');
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Kayıtlarım menüsü'));
    await _tap(tester, find.text('Kategorileri yönet'));
    await _tap(
      tester,
      find.byTooltip('Tarifler kategorisini yeniden adlandır'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      'Yeni ad',
    );
    await _tap(tester, find.widgetWithText(FilledButton, 'Kaydet'));
    expect(find.text('Yeni ad'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Yeni ad'), findsOneWidget);
    expect(find.text('Korunan başlık'), findsOneWidget);
  });

  testWidgets('details creation selects category without losing title', (
    tester,
  ) async {
    final store = _Store();
    await store.save(
      title: 'Eski',
      category: DocumentCategory.note,
      text: 'Metin.',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDocumentDetailsDialog(
                context: context,
                document: store.document!,
                store: store,
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await _tap(tester, find.text('Aç'));
    await tester.enterText(
      find.byKey(const ValueKey('document-details-title')),
      'Yeni başlık',
    );
    await _tap(tester, find.byType(DropdownButtonFormField<DocumentCategory>));
    await _tap(tester, find.text('Yeni kategori oluştur').last);
    await tester.enterText(find.byKey(const ValueKey('category-name')), 'Özel');
    await _tap(tester, find.widgetWithText(FilledButton, 'Kaydet').last);
    expect(find.text('Yeni başlık'), findsOneWidget);
    expect(find.text('Özel'), findsOneWidget);
    expect(store.document!.title, 'Eski');
    await _tap(tester, find.byKey(const ValueKey('save-document-details')));
    expect(store.document!.title, 'Yeni başlık');
    expect(store.document!.category.label, 'Özel');
  });

  testWidgets('renaming errors preserve input and allow retry', (tester) async {
    final store = _Store();
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Kayıtlarım menüsü'));
    await _tap(tester, find.text('Kategorileri yönet'));
    await _tap(tester, find.byTooltip('Kitap kategorisini yeniden adlandır'));
    await tester.enterText(find.byKey(const ValueKey('category-name')), 'NOT');
    await _tap(tester, find.widgetWithText(FilledButton, 'Kaydet'));
    expect(find.text('Bu adla bir kategori zaten var.'), findsOneWidget);
    store.failCategory = true;
    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      'Okuduklarım',
    );
    await _tap(tester, find.widgetWithText(FilledButton, 'Kaydet'));
    expect(
      find.text('Kategori kaydedilemedi. Tekrar deneyebilirsin.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('category-name')))
          .controller!
          .text,
      'Okuduklarım',
    );
    store.failCategory = false;
    await _tap(tester, find.widgetWithText(FilledButton, 'Kaydet'));
    expect(find.text('Okuduklarım'), findsOneWidget);
    expect(store.items.first, DocumentCategory.book);
  });

  testWidgets('category controls remain usable with large system text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _Store();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) =>
                    SaveDocumentDialog(text: 'Metin.', store: store),
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await _tap(tester, find.text('Aç'));
    await _tap(tester, find.byType(DropdownButtonFormField<DocumentCategory>));
    await _tap(tester, find.text('Yeni kategori oluştur').last);
    await tester.enterText(find.byKey(const ValueKey('category-name')), 'Özel');
    await _tap(tester, find.widgetWithText(FilledButton, 'Kaydet').last);
    expect(find.text('Özel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renamed built-in book alone retains justification', (
    tester,
  ) async {
    final store = _Store();
    final book = await store.renameCategory(
      DocumentCategory.book,
      'Okuduklarım',
    );
    final custom = await store.createCategory('Kitap');
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    for (final entry in [
      (book, TextAlign.justify),
      (custom, TextAlign.start),
    ]) {
      await store.save(title: 'Başlık', category: entry.$1, text: 'Metin.');
      await tester.pumpWidget(
        ReadingPreferencesScope(
          preferences: preferences,
          child: MaterialApp(
            home: SavedDocumentScreen(
              document: store.document!,
              store: store,
              speechService: FakeSpeechService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('saved-reading-text')))
            .textAlign,
        entry.$2,
      );
      expect(find.text(entry.$1.label), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

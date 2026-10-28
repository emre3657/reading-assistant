import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_schema.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _legacySchema = '''
CREATE TABLE documents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  category TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
''';

OpenDatabaseOptions _options() => OpenDatabaseOptions(
  version: documentDatabaseVersion,
  singleInstance: false,
  onConfigure: configureDocumentDatabase,
  onCreate: createDocumentSchema,
  onUpgrade: upgradeDocumentSchema,
);

void main() {
  sqfliteFfiInit();

  group('v2 schema and store with real SQLite', () {
    late Database database;
    late DocumentStore store;

    setUp(() async {
      database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: _options(),
      );
      store = DocumentStore(databaseOpener: () async => database);
    });

    tearDown(() async => database.close());

    test(
      'details edit preserves every page, position and creation date',
      () async {
        final id = await store.save(
          title: 'Eski',
          category: DocumentCategory.note,
          text: 'İlk\n\nsayfa.',
        );
        await store.appendPage(documentId: id, text: ' İkinci sayfa. ');
        final before = await database.query('pages', orderBy: 'position');
        final date = (await store.getDocument(id))!.createdAt;
        expect(
          await store.updateDetails(
            id: id,
            title: ' Yeni ',
            category: DocumentCategory.book,
          ),
          isTrue,
        );
        final document = (await store.getDocument(id))!;
        expect(document.title, 'Yeni');
        expect(document.category, DocumentCategory.book);
        expect(document.createdAt, date);
        expect(await database.query('pages', orderBy: 'position'), before);
      },
    );

    test('details validation and missing record do not touch data', () async {
      final id = await store.save(
        title: 'Eski',
        category: DocumentCategory.note,
        text: 'Metin.',
      );
      await expectLater(
        store.updateDetails(
          id: id,
          title: ' ',
          category: DocumentCategory.book,
        ),
        throwsArgumentError,
      );
      expect(
        await store.updateDetails(
          id: id + 100,
          title: 'Yeni',
          category: DocumentCategory.book,
        ),
        isFalse,
      );
      expect((await store.getDocument(id))!.title, 'Eski');
    });

    test('page text edit cannot overwrite newer content details', () async {
      final id = await store.save(
        title: 'Eski',
        category: DocumentCategory.note,
        text: 'İlk.',
      );
      final second = await store.appendPage(documentId: id, text: 'İkinci.');
      await store.updateDetails(
        id: id,
        title: 'Güncel',
        category: DocumentCategory.book,
      );
      final before = await database.query('documents');
      expect(
        await store.updatePageText(
          documentId: id,
          pageId: second.id,
          text: ' Yeni\n\nmetin. ',
        ),
        isTrue,
      );
      expect(await database.query('documents'), before);
      final pages = await store.pages(id);
      expect(pages.first.text, 'İlk.');
      expect(pages.last.text, ' Yeni\n\nmetin. ');
      expect(pages.last.position, second.position);
    });

    test('page text edit rejects foreign page and blank text', () async {
      final first = await store.save(
        title: 'Bir',
        category: DocumentCategory.note,
        text: 'Bir.',
      );
      final second = await store.save(
        title: 'İki',
        category: DocumentCategory.note,
        text: 'İki.',
      );
      final page = (await store.pages(second)).single;
      expect(
        await store.updatePageText(
          documentId: first,
          pageId: page.id,
          text: 'Yanlış',
        ),
        isFalse,
      );
      await expectLater(
        store.updatePageText(documentId: second, pageId: page.id, text: '  '),
        throwsArgumentError,
      );
      expect((await store.pages(second)).single.text, 'İki.');
    });

    test('new database has v2 tables and foreign keys enabled', () async {
      expect(await database.getVersion(), 2);
      final columns = await database.rawQuery('PRAGMA table_info(documents)');
      expect(columns.map((row) => row['name']), isNot(contains('text')));
      expect(await database.query('pages'), isEmpty);
      final flags = await database.rawQuery('PRAGMA foreign_keys');
      expect(flags.single.values.single, 1);
    });

    test('save/list/update keep one page and preserve creation date', () async {
      final id = await store.save(
        title: ' Başlık ',
        category: DocumentCategory.note,
        text: 'İlk\n\nmetin.',
      );
      final before = (await store.list()).single;
      expect(before.id, id);
      expect(before.title, 'Başlık');
      expect(before.text, 'İlk\n\nmetin.');
      final pages = await store.pages(id);
      expect(pages, hasLength(1));
      expect(pages.single.position, 0);
      expect(pages.single.documentId, id);
      expect(
        await store.update(
          id: id,
          title: ' Yeni ',
          category: DocumentCategory.book,
          text: 'Güncel\nmetin.',
        ),
        isTrue,
      );
      final after = (await store.list()).single;
      expect(after.title, 'Yeni');
      expect(after.category, DocumentCategory.book);
      expect(after.text, 'Güncel\nmetin.');
      expect(after.createdAt, before.createdAt);
      expect((await store.pages(id)).single.id, pages.single.id);
    });

    test('missing update/delete return false', () async {
      expect(
        await store.update(
          id: 99,
          title: 'Yok',
          category: DocumentCategory.note,
          text: 'Metin',
        ),
        isFalse,
      );
      expect(await store.delete(99), isFalse);
      expect(await store.pages(99), isEmpty);
    });

    test('whitespace-only input is rejected', () async {
      await expectLater(
        store.save(title: ' ', category: DocumentCategory.note, text: 'Metin'),
        throwsArgumentError,
      );
      await expectLater(
        store.update(
          id: 1,
          title: 'Başlık',
          category: DocumentCategory.note,
          text: '\n ',
        ),
        throwsArgumentError,
      );
      expect(await store.list(), isEmpty);
    });

    test('delete cascades only to the selected document pages', () async {
      final first = await store.save(
        title: 'Bir',
        category: DocumentCategory.note,
        text: 'Birinci',
      );
      final second = await store.save(
        title: 'İki',
        category: DocumentCategory.recipe,
        text: 'İkinci',
      );
      await database.insert('pages', {
        'document_id': first,
        'position': 1,
        'text': 'Ek sayfa',
      });
      expect(await store.delete(first), isTrue);
      expect(await store.pages(first), isEmpty);
      expect((await store.pages(second)).single.text, 'İkinci');
      expect((await store.list()).single.id, second);
    });

    test('page order, unique position and ownership are enforced', () async {
      final id = await store.save(
        title: 'Başlık',
        category: DocumentCategory.lesson,
        text: 'Sıfır',
      );
      await database.insert('pages', {
        'document_id': id,
        'position': 2,
        'text': 'İki',
      });
      await database.insert('pages', {
        'document_id': id,
        'position': 1,
        'text': 'Bir',
      });
      expect((await store.pages(id)).map((page) => page.position), [0, 1, 2]);
      await expectLater(
        database.insert('pages', {
          'document_id': id,
          'position': 1,
          'text': 'Çakışma',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.insert('pages', {
          'document_id': 999,
          'position': 0,
          'text': 'Sahipsiz',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.insert('pages', {
          'document_id': id,
          'position': -1,
          'text': 'Geçersiz',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test(
      'old single-page editor cannot overwrite a multi-page document',
      () async {
        final id = await store.save(
          title: 'Eski başlık',
          category: DocumentCategory.book,
          text: 'Bir',
        );
        await database.insert('pages', {
          'document_id': id,
          'position': 1,
          'text': 'İki',
        });
        await expectLater(
          store.update(
            id: id,
            title: 'Değişmesin',
            category: DocumentCategory.note,
            text: 'Yeni',
          ),
          throwsStateError,
        );
        expect((await store.list()).single.title, 'Eski başlık');
        expect((await store.pages(id)).map((page) => page.text), [
          'Bir',
          'İki',
        ]);
      },
    );

    test('failed first-page insert rolls back document creation', () async {
      await database.execute('''
        CREATE TRIGGER reject_page BEFORE INSERT ON pages
        BEGIN SELECT RAISE(ABORT, 'test failure'); END
      ''');
      await expectLater(
        store.save(
          title: 'Başlık',
          category: DocumentCategory.note,
          text: 'Metin',
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await database.query('documents'), isEmpty);
      expect(await database.query('pages'), isEmpty);
    });

    test('failed text update rolls back metadata changes too', () async {
      final id = await store.save(
        title: 'Eski',
        category: DocumentCategory.book,
        text: 'Eski metin',
      );
      await database.execute('''
        CREATE TRIGGER reject_page_update BEFORE UPDATE ON pages
        BEGIN SELECT RAISE(ABORT, 'test failure'); END
      ''');
      await expectLater(
        store.update(
          id: id,
          title: 'Yeni',
          category: DocumentCategory.note,
          text: 'Yeni metin',
        ),
        throwsA(isA<DatabaseException>()),
      );
      final document = (await store.list()).single;
      expect(document.title, 'Eski');
      expect(document.category, DocumentCategory.book);
      expect(document.text, 'Eski metin');
    });

    test(
      'append keeps one document and adds ordered pages with exact text',
      () async {
        final id = await store.save(
          title: 'Kitap',
          category: DocumentCategory.book,
          text: 'İlk sayfa',
        );
        final second = await store.appendPage(
          documentId: id,
          text: '  İkinci\n\nsayfa  ',
        );
        final third = await store.appendPage(documentId: id, text: 'Üçüncü');
        expect(await store.list(), hasLength(1));
        expect(second.position, 1);
        expect(third.position, 2);
        expect((await store.pages(id)).map((page) => page.text), [
          'İlk sayfa',
          '  İkinci\n\nsayfa  ',
          'Üçüncü',
        ]);
        expect((await store.getDocument(id))!.text, 'İlk sayfa');
        expect(await store.getDocument(999), isNull);
      },
    );

    test('append validates input and requires an existing owner', () async {
      await expectLater(
        store.appendPage(documentId: 999, text: ' '),
        throwsArgumentError,
      );
      await expectLater(
        store.appendPage(documentId: 999, text: 'Metin'),
        throwsStateError,
      );
      expect(await database.query('pages'), isEmpty);
      expect(await database.query('documents'), isEmpty);
    });

    test('concurrent append calls cannot reuse the same position', () async {
      final id = await store.save(
        title: 'Not',
        category: DocumentCategory.note,
        text: 'İlk',
      );
      await Future.wait([
        store.appendPage(documentId: id, text: 'A'),
        store.appendPage(documentId: id, text: 'B'),
      ]);
      final pages = await store.pages(id);
      expect(pages.map((page) => page.position), [0, 1, 2]);
      expect(
        pages.skip(1).map((page) => page.text),
        unorderedEquals(['A', 'B']),
      );
    });

    test('update targets the selected page, not the first one', () async {
      final id = await store.save(
        title: 'Eski',
        category: DocumentCategory.note,
        text: 'İlk',
      );
      final before = (await store.getDocument(id))!;
      final page = await store.appendPage(documentId: id, text: 'İkinci');
      expect(
        await store.updatePage(
          documentId: id,
          pageId: page.id,
          title: 'Yeni',
          category: DocumentCategory.book,
          text: 'Düzenlenmiş ikinci',
        ),
        isTrue,
      );
      expect((await store.pages(id)).map((page) => page.text), [
        'İlk',
        'Düzenlenmiş ikinci',
      ]);
      final after = (await store.getDocument(id))!;
      expect(after.title, 'Yeni');
      expect(after.category, DocumentCategory.book);
      expect(after.createdAt, before.createdAt);
    });

    test(
      'a foreign page cannot change another content or its metadata',
      () async {
        final first = await store.save(
          title: 'Bir',
          category: DocumentCategory.note,
          text: 'Bir',
        );
        final second = await store.save(
          title: 'İki',
          category: DocumentCategory.note,
          text: 'İki',
        );
        final foreignPage = (await store.pages(second)).single;
        expect(
          await store.updatePage(
            documentId: first,
            pageId: foreignPage.id,
            title: 'Bozulmasın',
            category: DocumentCategory.book,
            text: 'Yanlış',
          ),
          isFalse,
        );
        expect((await store.getDocument(first))!.title, 'Bir');
        expect((await store.pages(second)).single.text, 'İki');
      },
    );

    test('failed append preserves every existing page', () async {
      final id = await store.save(
        title: 'Not',
        category: DocumentCategory.note,
        text: 'İlk',
      );
      await database.execute(
        "CREATE TRIGGER reject_append BEFORE INSERT ON pages "
        "BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      await expectLater(
        store.appendPage(documentId: id, text: 'Yeni'),
        throwsA(isA<DatabaseException>()),
      );
      expect((await store.pages(id)).single.text, 'İlk');
    });

    test('page update failure rolls back metadata', () async {
      final id = await store.save(
        title: 'Eski',
        category: DocumentCategory.note,
        text: 'İlk',
      );
      final page = await store.appendPage(documentId: id, text: 'İkinci');
      await database.execute(
        "CREATE TRIGGER reject_selected_update BEFORE UPDATE ON pages "
        "BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      await expectLater(
        store.updatePage(
          documentId: id,
          pageId: page.id,
          title: 'Yeni',
          category: DocumentCategory.book,
          text: 'Yeni',
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect((await store.getDocument(id))!.title, 'Eski');
      expect((await store.pages(id)).map((page) => page.text), [
        'İlk',
        'İkinci',
      ]);
    });
  });

  group('real file migration from v1 to v2', () {
    late Directory directory;
    late String path;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('reading_schema_test_');
      path = '${directory.path}/migration.db';
    });
    tearDown(() async => directory.delete(recursive: true));

    Future<Database> createLegacy() {
      return databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: false,
          onCreate: (database, version) => database.execute(_legacySchema),
        ),
      );
    }

    test(
      'existing ids, metadata, exact text and all categories survive',
      () async {
        final legacy = await createLegacy();
        final expected = <int, String>{};
        try {
          for (var index = 0; index < DocumentCategory.values.length; index++) {
            final id = 10 + index * 3;
            final text = '  Çığ, şüphe, ı, İ.\n\nSayfa $index.  ';
            expected[id] = text;
            await legacy.insert('documents', {
              'id': id,
              'title': 'İçerik $index',
              'category': DocumentCategory.values[index].name,
              'text': text,
              'created_at': 1700000000000 + index,
            });
          }
        } finally {
          await legacy.close();
        }
        final upgraded = await databaseFactoryFfi.openDatabase(
          path,
          options: _options(),
        );
        try {
          expect(await upgraded.getVersion(), 2);
          final store = DocumentStore(databaseOpener: () async => upgraded);
          expect(await store.list(), hasLength(expected.length));
          for (var index = 0; index < DocumentCategory.values.length; index++) {
            final id = 10 + index * 3;
            final metadata = (await upgraded.query(
              'documents',
              where: 'id = ?',
              whereArgs: [id],
            )).single;
            expect(metadata['title'], 'İçerik $index');
            expect(metadata['category'], DocumentCategory.values[index].name);
            expect(metadata['created_at'], 1700000000000 + index);
            final pages = await store.pages(id);
            expect(pages, hasLength(1));
            expect(pages.single.position, 0);
            expect(pages.single.text, expected[id]);
          }
          final newId = await store.save(
            title: 'Yeni',
            category: DocumentCategory.note,
            text: 'Yeni sayfa',
          );
          expect(
            newId,
            greaterThan(expected.keys.reduce((a, b) => a > b ? a : b)),
          );
          expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        } finally {
          await upgraded.close();
        }
        // Reopening an upgraded file must not duplicate pages.
        final reopened = await databaseFactoryFfi.openDatabase(
          path,
          options: _options(),
        );
        try {
          expect(await reopened.query('pages'), hasLength(expected.length + 1));
        } finally {
          await reopened.close();
        }
      },
    );

    test('an empty v1 database upgrades without reinstalling', () async {
      final legacy = await createLegacy();
      await legacy.close();
      final upgraded = await databaseFactoryFfi.openDatabase(
        path,
        options: _options(),
      );
      try {
        expect(await upgraded.getVersion(), 2);
        expect(await upgraded.query('documents'), isEmpty);
        expect(await upgraded.query('pages'), isEmpty);
      } finally {
        await upgraded.close();
      }
    });

    test('upgrade failure rolls back data and schema version', () async {
      final legacy = await createLegacy();
      await legacy.insert('documents', {
        'id': 7,
        'title': 'Korunacak',
        'category': 'note',
        'text': 'Özgün metin',
        'created_at': 123,
      });
      await legacy.close();
      await expectLater(
        databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 2,
            singleInstance: false,
            onConfigure: configureDocumentDatabase,
            onUpgrade: (database, oldVersion, newVersion) async {
              await upgradeDocumentSchema(database, oldVersion, newVersion);
              throw StateError('Simulated upgrade failure');
            },
          ),
        ),
        throwsA(anything),
      );
      final original = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        expect(await original.getVersion(), 1);
        final row = (await original.query('documents')).single;
        expect(row['id'], 7);
        expect(row['text'], 'Özgün metin');
        expect(row['created_at'], 123);
      } finally {
        await original.close();
      }
    });
  });
}

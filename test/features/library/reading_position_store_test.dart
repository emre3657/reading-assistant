import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_schema.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  late DocumentStore store;
  late int documentId;
  late int firstId;
  late int secondId;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: documentDatabaseVersion,
        onConfigure: configureDocumentDatabase,
        onCreate: createDocumentSchema,
        onUpgrade: upgradeDocumentSchema,
      ),
    );
    store = DocumentStore(databaseOpener: () async => database);
    documentId = await store.save(
      title: 'Kitap',
      category: DocumentCategory.book,
      text: 'Bir. İki.',
    );
    firstId = (await store.pages(documentId)).single.id;
    secondId = (await store.appendPage(
      documentId: documentId,
      text: 'Üç. Dört.',
    )).id;
  });
  tearDown(() async => database.close());

  Future<void> save(int pageId, int index, String text) =>
      store.saveReadingPosition(
        documentId: documentId,
        pageId: pageId,
        sentenceIndex: index,
        pageText: text,
      );

  test('persists by page id across a new store and reorder', () async {
    final before = await database.query('documents');
    final pagesBefore = await store.pages(documentId);
    await save(secondId, 1, 'Üç. Dört.');
    await store.reorderPages(
      documentId: documentId,
      orderedPageIds: [secondId, firstId],
    );
    final reopened = DocumentStore(databaseOpener: () async => database);
    final position = await reopened.readingPosition(documentId);
    expect(position?.pageId, secondId);
    expect(position?.sentenceIndex, 1);
    expect(position?.pageText, 'Üç. Dört.');
    expect(await database.query('documents'), before);
    final pagesAfter = await store.pages(documentId);
    expect(pagesAfter.map((p) => p.text), [
      pagesBefore[1].text,
      pagesBefore[0].text,
    ]);
  });

  test('text edits and deletions invalidate position', () async {
    await save(firstId, 1, 'Bir. İki.');
    await store.updatePageText(
      documentId: documentId,
      pageId: firstId,
      text: 'Yeni.',
    );
    await store.updatePageText(
      documentId: documentId,
      pageId: firstId,
      text: 'Bir. İki.',
    );
    expect(await store.readingPosition(documentId), isNull);
    await save(secondId, 0, 'Üç. Dört.');
    await store.deletePage(documentId: documentId, pageId: secondId);
    expect(await store.readingPosition(documentId), isNull);
    await save(firstId, 0, 'Bir. İki.');
    await store.delete(documentId);
    expect(await database.query('reading_positions'), isEmpty);
  });

  test(
    'foreign or changed text never saves; invalid ownership is cleaned',
    () async {
      final other = await store.save(
        title: 'Not',
        category: DocumentCategory.note,
        text: 'Başka.',
      );
      final foreign = (await store.pages(other)).single.id;
      await expectLater(save(foreign, 0, 'Başka.'), throwsStateError);
      await expectLater(save(firstId, 0, 'Eski.'), throwsStateError);
      expect(await store.readingPosition(documentId), isNull);
      await database.insert('reading_positions', {
        'document_id': documentId,
        'page_id': foreign,
        'sentence_index': 0,
        'page_text': 'Başka.',
      });
      expect(await store.readingPosition(documentId), isNull);
      expect(await database.query('reading_positions'), isEmpty);
    },
  );

  test('queued writes precede later positions and completion', () async {
    final gate = Completer<Database>();
    final queued = DocumentStore(databaseOpener: () => gate.future);
    Future<void> write(int page, int index, String text) =>
        queued.saveReadingPosition(
          documentId: documentId,
          pageId: page,
          sentenceIndex: index,
          pageText: text,
        );
    final first = write(firstId, 0, 'Bir. İki.');
    final second = write(secondId, 1, 'Üç. Dört.');
    final complete = queued.completeReadingPage(
      documentId: documentId,
      pageId: secondId,
    );
    gate.complete(database);
    await Future.wait([first, second, complete]);
    expect(await queued.readingPosition(documentId), isNull);
    final older = write(firstId, 0, 'Bir. İki.');
    final newer = write(secondId, 0, 'Üç. Dört.');
    await Future.wait([older, newer]);
    expect((await queued.readingPosition(documentId))?.pageId, secondId);
  });

  test(
    'pending position write cannot outlive an edit and text restoration',
    () async {
      final gate = Completer<Database>();
      final delayed = DocumentStore(databaseOpener: () => gate.future);
      final oldWrite = delayed.saveReadingPosition(
        documentId: documentId,
        pageId: firstId,
        sentenceIndex: 1,
        pageText: 'Bir. İki.',
      );
      final edit = store.updatePageText(
        documentId: documentId,
        pageId: firstId,
        text: 'Yeni.',
      );
      final restore = store.updatePageText(
        documentId: documentId,
        pageId: firstId,
        text: 'Bir. İki.',
      );
      gate.complete(database);
      await Future.wait([oldWrite, edit, restore]);
      expect(await store.readingPosition(documentId), isNull);
    },
  );

  test('only final page completion clears the record', () async {
    await save(firstId, 1, 'Bir. İki.');
    await store.completeReadingPage(documentId: documentId, pageId: firstId);
    expect((await store.readingPosition(documentId))?.sentenceIndex, 1);
    await store.completeReadingPage(documentId: documentId, pageId: secondId);
    expect(await store.readingPosition(documentId), isNull);
  });

  test('repeated identical position does not write', () async {
    await save(firstId, 0, 'Bir. İki.');
    await database.execute('''
      CREATE TRIGGER reject_duplicate BEFORE UPDATE ON reading_positions
      BEGIN SELECT RAISE(ABORT, 'unexpected write'); END
    ''');
    await save(firstId, 0, 'Bir. İki.');
    await expectLater(
      save(firstId, 1, 'Bir. İki.'),
      throwsA(isA<DatabaseException>()),
    );
    expect((await store.readingPosition(documentId))?.sentenceIndex, 0);
  });

  test('v2 migration preserves data and failure rolls back', () async {
    final dir = await Directory.systemTemp.createTemp('reading-migration-');
    final path = '${dir.path}${Platform.pathSeparator}test.db';
    try {
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          singleInstance: false,
          onConfigure: configureDocumentDatabase,
          onCreate: (db, _) async {
            await db.execute(createDocumentsSql);
            await db.execute(createPagesSql);
          },
        ),
      );
      await old.insert('documents', {
        'id': 42,
        'title': 'Eski',
        'category': 'note',
        'created_at': 7,
      });
      await old.insert('pages', {
        'id': 9,
        'document_id': 42,
        'position': 4,
        'text': 'Metin',
      });
      await old.close();
      await expectLater(
        databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 3,
            singleInstance: false,
            onConfigure: configureDocumentDatabase,
            onUpgrade: (db, oldVersion, newVersion) async {
              await upgradeDocumentSchema(db, oldVersion, newVersion);
              throw StateError('migration failure');
            },
          ),
        ),
        throwsStateError,
      );
      final original = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 2, singleInstance: false),
      );
      expect(await original.getVersion(), 2);
      expect(await original.query('pages'), hasLength(1));
      expect(
        await original.rawQuery(
          "SELECT name FROM sqlite_master WHERE name = 'reading_positions'",
        ),
        isEmpty,
      );
      await original.close();
      final upgraded = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: configureDocumentDatabase,
          onUpgrade: upgradeDocumentSchema,
        ),
      );
      expect(await upgraded.getVersion(), 3);
      expect((await upgraded.query('documents')).single['created_at'], 7);
      expect((await upgraded.query('pages')).single['id'], 9);
      expect(await upgraded.query('reading_positions'), isEmpty);
      await upgraded.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('position survives closing and reopening a database file', () async {
    final dir = await Directory.systemTemp.createTemp('reading-position-');
    final path = '${dir.path}${Platform.pathSeparator}test.db';
    OpenDatabaseOptions options() => OpenDatabaseOptions(
      version: documentDatabaseVersion,
      singleInstance: false,
      onConfigure: configureDocumentDatabase,
      onCreate: createDocumentSchema,
      onUpgrade: upgradeDocumentSchema,
    );
    try {
      final first = await databaseFactoryFfi.openDatabase(
        path,
        options: options(),
      );
      final writer = DocumentStore(databaseOpener: () async => first);
      final id = await writer.save(
        title: 'Kitap',
        category: DocumentCategory.book,
        text: 'Bir. İki.',
      );
      final page = (await writer.pages(id)).single;
      await writer.saveReadingPosition(
        documentId: id,
        pageId: page.id,
        sentenceIndex: 1,
        pageText: page.text,
      );
      await first.close();
      final second = await databaseFactoryFfi.openDatabase(
        path,
        options: options(),
      );
      final reader = DocumentStore(databaseOpener: () async => second);
      expect((await reader.readingPosition(id))?.pageId, page.id);
      expect((await reader.readingPosition(id))?.sentenceIndex, 1);
      await second.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

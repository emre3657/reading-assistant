import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_schema.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late DocumentStore store;
  late int docId;
  late int otherId;
  late List<int> ids; // page ids of docId in position order
  late List<int> otherIds;

  Future<List<int>> order(int documentId) async => [
    for (final row in await database.query(
      'pages',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'position',
    ))
      row['id'] as int,
  ];

  Future<List<Map<String, Object?>>> snapshot() =>
      database.query('pages', orderBy: 'id');

  Future<List<Map<String, Object?>>> withoutPositions(int documentId) async => [
    for (final row in await database.query(
      'pages',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'id',
    ))
      {'id': row['id'], 'text': row['text'], 'document_id': row['document_id']},
  ];

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: documentDatabaseVersion,
        singleInstance: false,
        onConfigure: configureDocumentDatabase,
        onCreate: createDocumentSchema,
        onUpgrade: upgradeDocumentSchema,
      ),
    );
    store = DocumentStore(databaseOpener: () async => database);

    docId = await store.save(
      title: 'A',
      category: DocumentCategory.book,
      text: 'a0',
    );
    for (final t in ['a1', 'a2', 'a3']) {
      await store.appendPage(documentId: docId, text: t);
    }
    otherId = await store.save(
      title: 'B',
      category: DocumentCategory.note,
      text: 'b0',
    );
    await store.appendPage(documentId: otherId, text: 'b1');
    ids = await order(docId);
    otherIds = await order(otherId);
  });

  tearDown(() async => database.close());

  Future<List<String>> texts(int documentId) async => [
    for (final p in await store.pages(documentId)) p.text,
  ];

  test('moves a page down, up, first to last and last to first', () async {
    // a0 a1 a2 a3 -> move a0 after a2 (insert, not swap)
    expect(
      await store.reorderPages(
        documentId: docId,
        orderedPageIds: [ids[1], ids[2], ids[0], ids[3]],
      ),
      isTrue,
    );
    expect(await texts(docId), ['a1', 'a2', 'a0', 'a3']);

    // move a3 up to index 1
    var now = await order(docId);
    await store.reorderPages(
      documentId: docId,
      orderedPageIds: [now[0], now[3], now[1], now[2]],
    );
    expect(await texts(docId), ['a1', 'a3', 'a2', 'a0']);

    // first to last
    now = await order(docId);
    await store.reorderPages(
      documentId: docId,
      orderedPageIds: [...now.skip(1), now.first],
    );
    expect(await texts(docId), ['a3', 'a2', 'a0', 'a1']);

    // last to first
    now = await order(docId);
    await store.reorderPages(
      documentId: docId,
      orderedPageIds: [now.last, ...now.take(3)],
    );
    expect(await texts(docId), ['a1', 'a3', 'a2', 'a0']);

    final positions = [for (final p in await store.pages(docId)) p.position];
    expect(positions, [0, 1, 2, 3]);
  });

  test('same order writes nothing', () async {
    final before = await snapshot();
    expect(
      await store.reorderPages(documentId: docId, orderedPageIds: ids),
      isFalse,
    );
    expect(await snapshot(), before);
  });

  test('keeps ids, texts and other contents unchanged', () async {
    final textsBefore = await withoutPositions(docId);
    final otherBefore = await database.query(
      'pages',
      where: 'document_id = ?',
      whereArgs: [otherId],
      orderBy: 'id',
    );
    final docsBefore = await database.query('documents', orderBy: 'id');

    await store.reorderPages(
      documentId: docId,
      orderedPageIds: ids.reversed.toList(),
    );

    expect(await withoutPositions(docId), textsBefore);
    expect(
      await database.query(
        'pages',
        where: 'document_id = ?',
        whereArgs: [otherId],
        orderBy: 'id',
      ),
      otherBefore,
    );
    expect(await database.query('documents', orderBy: 'id'), docsBefore);
    expect(await order(otherId), otherIds);
  });

  test('handles position gaps left by deletions and closes them', () async {
    await store.deletePage(documentId: docId, pageId: ids[1]);
    // positions are now 0, 2, 3
    expect([for (final p in await store.pages(docId)) p.position], [0, 2, 3]);

    // Same order but gaps: renumbers (counts as a change).
    expect(
      await store.reorderPages(
        documentId: docId,
        orderedPageIds: [ids[0], ids[2], ids[3]],
      ),
      isTrue,
    );
    expect([for (final p in await store.pages(docId)) p.position], [0, 1, 2]);

    await store.reorderPages(
      documentId: docId,
      orderedPageIds: [ids[3], ids[0], ids[2]],
    );
    expect(await texts(docId), ['a3', 'a0', 'a2']);
    expect([for (final p in await store.pages(docId)) p.position], [0, 1, 2]);
  });

  test('rejects missing, duplicate, foreign and unknown ids', () async {
    final before = await snapshot();
    final bad = <List<int>>[
      ids.take(3).toList(),
      [...ids.take(3), ids[0]],
      [...ids.take(3), otherIds.first],
      [...ids, otherIds.first],
      [...ids.take(3), 99999],
      const [],
    ];
    for (final candidate in bad) {
      await expectLater(
        store.reorderPages(documentId: docId, orderedPageIds: candidate),
        throwsArgumentError,
        reason: '$candidate',
      );
    }
    expect(await snapshot(), before);
  });

  test('an error in the middle rolls everything back', () async {
    final before = await snapshot();
    // Fails the final renumbering of one page after others were moved.
    await database.execute('''
      CREATE TRIGGER fail_reorder BEFORE UPDATE OF position ON pages
      WHEN NEW.position = 2 AND NEW.id = ${ids[0]}
      BEGIN SELECT RAISE(ABORT, 'boom'); END
    ''');

    await expectLater(
      store.reorderPages(
        documentId: docId,
        orderedPageIds: [ids[1], ids[2], ids[0], ids[3]],
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(await snapshot(), before);
    expect(await order(docId), ids);
  });

  test('new order survives reopening the content', () async {
    final reversed = ids.reversed.toList();
    await store.reorderPages(documentId: docId, orderedPageIds: reversed);

    final reopened = DocumentStore(databaseOpener: () async => database);
    expect([for (final p in await reopened.pages(docId)) p.id], reversed);
    expect((await reopened.list()).firstWhere((d) => d.id == docId).text, 'a3');
  });
}

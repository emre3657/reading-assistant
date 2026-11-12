import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_schema.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

OpenDatabaseOptions _options() => OpenDatabaseOptions(
  version: documentDatabaseVersion,
  singleInstance: false,
  onConfigure: configureDocumentDatabase,
  onCreate: createDocumentSchema,
  onUpgrade: upgradeDocumentSchema,
);

void main() {
  sqfliteFfiInit();

  test(
    'transfer and deletion preserve pages, position and preferences',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: _options(),
      );
      addTearDown(db.close);
      final store = DocumentStore(databaseOpener: () async => db);
      final id = await store.save(
        title: 'Özgün',
        category: DocumentCategory.book,
        text: 'Bir. İki.',
      );
      final page = (await store.pages(id)).single;
      await store.appendPage(documentId: id, text: 'Son sayfa.');
      await store.saveReadingPosition(
        documentId: id,
        pageId: page.id,
        sentenceIndex: 1,
        pageText: page.text,
      );
      await store.saveReadingPreferences(
        speed: 'fast',
        autoNextPage: true,
        followSentence: true,
        textSize: 'large',
      );
      final beforeDocs = await db.query('documents');
      final beforePages = await db.query('pages');
      final beforePosition = await db.query('reading_positions');
      final beforePrefs = await db.query('reading_preferences');
      expect(await store.categoryDocumentCount(DocumentCategory.book), 1);
      await store.deleteCategory(
        DocumentCategory.book,
        target: DocumentCategory.note,
      );
      final after = (await db.query('documents')).single;
      expect(after, {...beforeDocs.single, 'category': 'note'});
      expect(await db.query('pages'), beforePages);
      expect(await db.query('reading_positions'), beforePosition);
      expect(await db.query('reading_preferences'), beforePrefs);
      expect((await store.getDocument(id))!.category, DocumentCategory.note);
      expect(
        (await store.categories()).contains(DocumentCategory.book),
        isFalse,
      );
      await store.deleteCategory(DocumentCategory.recipe);
      expect(
        (await store.categories()).contains(DocumentCategory.recipe),
        isFalse,
      );
    },
  );

  test(
    'invalid targets, final category and database failure roll back',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: _options(),
      );
      addTearDown(db.close);
      final store = DocumentStore(databaseOpener: () async => db);
      final id = await store.save(
        title: 'Özgün',
        category: DocumentCategory.book,
        text: 'Metin.',
      );
      for (final target in [
        null,
        DocumentCategory.book,
        const DocumentCategory('missing', 'Yok'),
      ]) {
        await expectLater(
          store.deleteCategory(DocumentCategory.book, target: target),
          throwsA(
            isA<CategoryDeletionException>().having(
              (e) => e.problem,
              'problem',
              CategoryDeletionProblem.invalidTarget,
            ),
          ),
        );
        expect((await store.getDocument(id))!.category, DocumentCategory.book);
      }
      await db.execute("""
      CREATE TRIGGER fail_category_delete BEFORE DELETE ON categories
      WHEN OLD.id = 'book' BEGIN SELECT RAISE(ABORT, 'test failure'); END
    """);
      await expectLater(
        store.deleteCategory(
          DocumentCategory.book,
          target: DocumentCategory.note,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect((await store.getDocument(id))!.category, DocumentCategory.book);
      expect(
        (await store.categories()).contains(DocumentCategory.book),
        isTrue,
      );
      await db.execute('DROP TRIGGER fail_category_delete');
      for (final category in [
        DocumentCategory.note,
        DocumentCategory.recipe,
        DocumentCategory.lesson,
        DocumentCategory.lyrics,
      ]) {
        await store.deleteCategory(category);
      }
      await expectLater(
        store.deleteCategory(DocumentCategory.book),
        throwsA(
          isA<CategoryDeletionException>().having(
            (e) => e.problem,
            'problem',
            CategoryDeletionProblem.lastCategory,
          ),
        ),
      );
      expect((await store.getDocument(id))!.category, DocumentCategory.book);
    },
  );

  test('deleted built-in remains deleted after reopening', () async {
    final dir = await Directory.systemTemp.createTemp('category-delete-');
    final path = '${dir.path}${Platform.pathSeparator}test.db';
    Database? db;
    try {
      db = await databaseFactoryFfi.openDatabase(path, options: _options());
      final store = DocumentStore(databaseOpener: () async => db!);
      await store.deleteCategory(DocumentCategory.book);
      final custom = await store.createCategory('Kitap');
      await db.close();
      db = await databaseFactoryFfi.openDatabase(path, options: _options());
      final reopened = DocumentStore(databaseOpener: () async => db!);
      final categories = await reopened.categories();
      expect(categories.contains(DocumentCategory.book), isFalse);
      expect(categories.contains(custom), isTrue);
    } finally {
      if (db?.isOpen ?? false) await db!.close();
      await dir.delete(recursive: true);
    }
  });
}

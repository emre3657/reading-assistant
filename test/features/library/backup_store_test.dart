import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/backup_data.dart';
import 'package:reading_assistant/features/library/data/document_schema.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database sourceDb;
  late Database targetDb;
  late DocumentStore source;
  late DocumentStore target;

  Future<Database> open() => databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: documentDatabaseVersion,
      onConfigure: configureDocumentDatabase,
      onCreate: createDocumentSchema,
      onUpgrade: upgradeDocumentSchema,
    ),
  );

  setUp(() async {
    sourceDb = await open();
    targetDb = await open();
    source = DocumentStore(databaseOpener: () async => sourceDb);
    target = DocumentStore(databaseOpener: () async => targetDb);
  });
  tearDown(() async {
    await sourceDb.close();
    await targetDb.close();
  });

  Future<BackupData> populated() async {
    final category = await source.createCategory('Özel');
    final id = await source.savePages(
      title: 'Örnek',
      category: category,
      texts: ['Bir. İki.', 'Üç. Dört.'],
    );
    final pages = await source.pages(id);
    await source.reorderPages(
      documentId: id,
      orderedPageIds: [pages[1].id, pages[0].id],
    );
    await source.saveReadingPosition(
      documentId: id,
      pageId: pages[0].id,
      sentenceIndex: 1,
      pageText: pages[0].text,
    );
    await source.saveBookmark(
      documentId: id,
      pageId: pages[1].id,
      sentenceIndex: 1,
      pageText: pages[1].text,
    );
    await source.saveReadingPreferences(
      speed: 'fast',
      autoNextPage: true,
      followSentence: true,
      textSize: 'large',
      textAlignment: 'justify',
      lineSpacing: 'wide',
      pageView: 'book',
      pageAnimationEnabled: true,
      pageAnimationEffect: 'turn',
      bookmarkShape: 'corner',
      bookmarkColor: 'teal',
      themeMode: 'dark',
      themePalette: 'blue',
    );
    return source.backupSnapshot();
  }

  test('round trip replaces existing data and preserves all tables', () async {
    final backup = await populated();
    await target.save(
      title: 'Eski',
      category: DocumentCategory.note,
      text: 'Eski metin.',
    );
    await target.restoreBackup(BackupData.decode(backup.encode()));
    final restored = await target.backupSnapshot();
    expect(restored.tables, backup.tables);
    expect(restored.documentCount, 1);
    expect(restored.pageCount, 2);
    final id = restored.tables['documents']!.single['id'] as int;
    expect((await target.pages(id)).map((page) => page.text), [
      'Üç. Dört.',
      'Bir. İki.',
    ]);
    expect((await target.readingPosition(id))?.sentenceIndex, 1);
    expect(
      (await target.bookmark(id))?.pageId,
      (await target.pages(id)).first.id,
    );
    expect((await target.loadReadingPreferences())?['line_spacing'], 'wide');
    expect((await target.loadReadingPreferences())?['page_view'], 'book');
    expect(
      (await target.loadReadingPreferences())?['page_animation_enabled'],
      1,
    );
    expect(
      (await target.loadReadingPreferences())?['page_animation_effect'],
      'turn',
    );
    expect(
      (await target.loadReadingPreferences())?['bookmark_shape'],
      'corner',
    );
    expect((await target.loadReadingPreferences())?['bookmark_color'], 'teal');
    expect((await target.loadReadingPreferences())?['theme_mode'], 'dark');
    expect((await target.loadReadingPreferences())?['theme_palette'], 'blue');
  });

  test('legacy and unknown page view restore with plain default', () async {
    final backup = await populated();
    Map<String, dynamic> fresh() =>
        jsonDecode(utf8.decode(backup.encode())) as Map<String, dynamic>;
    for (final legacy in [true, false]) {
      final data = fresh();
      final row =
          data['data']['reading_preferences'][0] as Map<String, dynamic>;
      if (legacy) {
        row.remove('page_view');
        row.remove('page_animation_enabled');
        row.remove('page_animation_effect');
        row.remove('bookmark_shape');
        row.remove('bookmark_color');
        row.remove('theme_mode');
        row.remove('theme_palette');
      } else {
        row['page_view'] = 'future';
        row['page_animation_effect'] = 'future';
        row['bookmark_shape'] = 'future';
        row['bookmark_color'] = 'future';
        row['theme_mode'] = 'future';
        row['theme_palette'] = 'future';
      }
      final parsed = BackupData.decode(
        Uint8List.fromList(utf8.encode(jsonEncode(data))),
      );
      await target.restoreBackup(parsed);
      expect((await target.loadReadingPreferences())?['page_view'], 'plain');
      expect(
        (await target.loadReadingPreferences())?['page_animation_effect'],
        'fade',
      );
      expect(
        (await target.loadReadingPreferences())?['bookmark_shape'],
        'ribbon',
      );
      expect((await target.loadReadingPreferences())?['bookmark_color'], 'red');
      expect((await target.loadReadingPreferences())?['theme_mode'], 'system');
      expect(
        (await target.loadReadingPreferences())?['theme_palette'],
        'turquoise',
      );
      expect(
        (await target.loadReadingPreferences())?['page_animation_enabled'],
        legacy ? 0 : 1,
      );
      expect((await target.loadReadingPreferences())?['line_spacing'], 'wide');
      expect(
        await target.bookmark(parsed.tables['documents']!.single['id'] as int),
        isNotNull,
      );
    }
  });

  test('empty target can restore a snapshot', () async {
    final backup = await populated();
    await target.restoreBackup(BackupData.decode(backup.encode()));
    expect((await target.backupSnapshot()).tables, backup.tables);
  });

  test(
    'restore transaction rolls back all existing data on insert failure',
    () async {
      final backup = await populated();
      await target.save(
        title: 'Korunan',
        category: DocumentCategory.note,
        text: 'Metin.',
      );
      final before = await target.backupSnapshot();
      await targetDb.execute(
        "CREATE TRIGGER reject_restore BEFORE INSERT ON pages BEGIN SELECT RAISE(ABORT, 'fail'); END",
      );
      await expectLater(
        target.restoreBackup(backup),
        throwsA(isA<DatabaseException>()),
      );
      expect((await target.backupSnapshot()).tables, before.tables);
    },
  );

  test(
    'invalid format, missing data and bad references never change target',
    () async {
      final backup = await populated();
      await target.save(
        title: 'Korunan',
        category: DocumentCategory.note,
        text: 'Metin.',
      );
      final before = await target.backupSnapshot();
      Uint8List encode(Object value) =>
          Uint8List.fromList(utf8.encode(jsonEncode(value)));
      Map<String, dynamic> fresh() =>
          jsonDecode(utf8.decode(backup.encode())) as Map<String, dynamic>;
      final version = fresh()..['version'] = 999;
      final missing = fresh()..['data'].remove('pages');
      final invalid = fresh();
      invalid['data']['bookmarks'][0]['page_id'] = -1;
      final badCategory = fresh();
      badCategory['data']['documents'][0]['category'] = 'missing';
      final badSentence = fresh();
      badSentence['data']['reading_positions'][0]['sentence_index'] = 999;
      for (final bytes in [
        Uint8List.fromList([0xff]),
        encode(version),
        encode(missing),
        encode(invalid),
        encode(badCategory),
        encode(badSentence),
      ]) {
        expect(() => BackupData.decode(bytes), throwsFormatException);
        expect((await target.backupSnapshot()).tables, before.tables);
      }
    },
  );
}

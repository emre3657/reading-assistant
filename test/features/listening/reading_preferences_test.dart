import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_schema.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/listening/presentation/listening_controller.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_preferences_store.dart';

void main() {
  sqfliteFfiInit();

  test('defaults and invalid stored values are safe', () async {
    final store = FakePreferencesStore();
    final preferences = ReadingPreferences(store: store);
    await preferences.load();
    expect(preferences.speed, ReadingSpeed.normal);
    expect(preferences.autoNextPage, isFalse);
    expect(preferences.followSentence, isFalse);
    expect(preferences.textSize, ReadingTextSize.normal);
    expect(preferences.textAlignment, ReadingTextAlignment.start);
    expect(preferences.lineSpacing, ReadingLineSpacing.normal);
    expect(preferences.pageView, ReadingPageView.plain);
    expect(preferences.pageAnimationEnabled, isFalse);
    expect(preferences.pageAnimationEffect, PageAnimationEffect.fade);
    expect(preferences.bookmarkShape, BookmarkShape.ribbon);
    expect(preferences.bookmarkColor, BookmarkColor.red);
    expect(store.saveCalls, 0);

    store.values = {
      'speed': 'invalid',
      'auto_next_page': 42,
      'follow_sentence': 42,
      'text_size': 'invalid',
      'text_alignment': 'invalid',
      'line_spacing': 'invalid',
      'page_view': 'invalid',
      'page_animation_enabled': 0,
      'page_animation_effect': 'unknown',
      'bookmark_shape': 'unknown',
      'bookmark_color': 'unknown',
    };
    final invalid = ReadingPreferences(store: store);
    await invalid.load();
    expect(invalid.speed, ReadingSpeed.normal);
    expect(invalid.autoNextPage, isFalse);
    expect(invalid.followSentence, isFalse);
    expect(invalid.textSize, ReadingTextSize.normal);
    expect(invalid.textAlignment, ReadingTextAlignment.start);
    expect(invalid.lineSpacing, ReadingLineSpacing.normal);
    expect(invalid.pageView, ReadingPageView.plain);
    expect(invalid.pageAnimationEffect, PageAnimationEffect.fade);
    expect(invalid.bookmarkShape, BookmarkShape.ribbon);
    expect(invalid.bookmarkColor, BookmarkColor.red);
  });

  test(
    'loading blocks changes; queued writes preserve the latest choice',
    () async {
      final store = FakePreferencesStore()
        ..values = {'speed': 'fast', 'auto_next_page': 1}
        ..loadGate = Completer<void>()
        ..saveGate = Completer<void>();
      final preferences = ReadingPreferences(store: store);
      final loading = preferences.load();
      preferences.setSpeed(ReadingSpeed.slow);
      preferences.setTextSize(ReadingTextSize.large);
      preferences.setTextAlignment(ReadingTextAlignment.center);
      preferences.setLineSpacing(ReadingLineSpacing.relaxed);
      expect(store.saveCalls, 0);
      store.loadGate!.complete();
      await loading;
      expect(preferences.speed, ReadingSpeed.fast);
      expect(preferences.autoNextPage, isTrue);

      preferences.setSpeed(ReadingSpeed.slow);
      preferences.setSpeed(ReadingSpeed.faster);
      preferences.setAutoNextPage(false);
      preferences.setFollowSentence(true);
      preferences.setTextAlignment(ReadingTextAlignment.right);
      preferences.setTextAlignment(ReadingTextAlignment.justify);
      preferences.setTextSize(ReadingTextSize.large);
      preferences.setTextSize(ReadingTextSize.extraLarge);
      preferences.setLineSpacing(ReadingLineSpacing.relaxed);
      preferences.setLineSpacing(ReadingLineSpacing.wide);
      preferences.setPageView(ReadingPageView.book);
      preferences.setPageAnimationEnabled(true);
      preferences.setBookmarkShape(BookmarkShape.corner);
      preferences.setBookmarkColor(BookmarkColor.teal);
      preferences.setPageAnimationEffect(PageAnimationEffect.turn);
      preferences.setPageAnimationEnabled(false);
      preferences.setPageAnimationEnabled(true);
      preferences.setFollowSentence(false);
      preferences.setFollowSentence(true);
      await Future<void>.delayed(Duration.zero);
      expect(store.saveCalls, 1);
      store.saveGate!.complete();
      await preferences.pendingWrites;
      expect(store.values, {
        'speed': 'faster',
        'auto_next_page': 0,
        'follow_sentence': 1,
        'text_size': 'extraLarge',
        'text_alignment': 'justify',
        'line_spacing': 'wide',
        'page_view': 'book',
        'page_animation_enabled': 1,
        'page_animation_effect': 'turn',
        'bookmark_shape': 'corner',
        'bookmark_color': 'teal',
      });
      expect(store.saveCalls, 19);
    },
  );

  test(
    'load and save errors leave usable state and suppress repeated notices',
    () async {
      final store = FakePreferencesStore()
        ..loadError = StateError('load')
        ..saveError = StateError('save');
      final preferences = ReadingPreferences(store: store);
      await preferences.load();
      expect(preferences.ready, isTrue);
      expect(preferences.errorMessage, contains('yüklenemedi'));
      preferences.setSpeed(ReadingSpeed.fast);
      preferences.setAutoNextPage(true);
      preferences.setFollowSentence(true);
      preferences.setTextSize(ReadingTextSize.large);
      preferences.setTextAlignment(ReadingTextAlignment.center);
      preferences.setLineSpacing(ReadingLineSpacing.wide);
      await preferences.pendingWrites;
      expect(preferences.speed, ReadingSpeed.fast);
      expect(preferences.autoNextPage, isTrue);
      expect(preferences.followSentence, isTrue);
      expect(preferences.textSize, ReadingTextSize.large);
      expect(preferences.textAlignment, ReadingTextAlignment.center);
      expect(preferences.lineSpacing, ReadingLineSpacing.wide);
      expect(preferences.errorRevision, 2);
      expect(preferences.errorMessage, contains('kaydedilemedi'));
      store.saveError = null;
      preferences.setSpeed(ReadingSpeed.slow);
      await preferences.pendingWrites;
      expect(store.values!['speed'], 'slow');
      expect(store.values!['text_alignment'], 'center');
      expect(store.values!['line_spacing'], 'wide');
    },
  );

  test('preferences survive closing and reopening SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('reading-preferences-');
    final path = '${dir.path}${Platform.pathSeparator}test.db';
    OpenDatabaseOptions options() => OpenDatabaseOptions(
      version: documentDatabaseVersion,
      singleInstance: false,
      onConfigure: configureDocumentDatabase,
      onCreate: createDocumentSchema,
      onUpgrade: upgradeDocumentSchema,
    );
    try {
      final database = await databaseFactoryFfi.openDatabase(
        path,
        options: options(),
      );
      final preferences = ReadingPreferences(
        store: DocumentStore(databaseOpener: () async => database),
      );
      await preferences.load();
      preferences.setSpeed(ReadingSpeed.faster);
      preferences.setAutoNextPage(true);
      preferences.setFollowSentence(true);
      preferences.setTextSize(ReadingTextSize.extraLarge);
      preferences.setTextAlignment(ReadingTextAlignment.center);
      preferences.setLineSpacing(ReadingLineSpacing.relaxed);
      preferences.setPageView(ReadingPageView.book);
      preferences.setPageAnimationEnabled(true);
      preferences.setPageAnimationEffect(PageAnimationEffect.slide);
      preferences.setBookmarkShape(BookmarkShape.strip);
      preferences.setBookmarkColor(BookmarkColor.purple);
      await preferences.pendingWrites;
      await database.close();
      final reopened = await databaseFactoryFfi.openDatabase(
        path,
        options: options(),
      );
      final restored = ReadingPreferences(
        store: DocumentStore(databaseOpener: () async => reopened),
      );
      await restored.load();
      expect(restored.speed, ReadingSpeed.faster);
      expect(restored.autoNextPage, isTrue);
      expect(restored.followSentence, isTrue);
      expect(restored.textSize, ReadingTextSize.extraLarge);
      expect(restored.textAlignment, ReadingTextAlignment.center);
      expect(restored.lineSpacing, ReadingLineSpacing.relaxed);
      expect(restored.pageView, ReadingPageView.book);
      expect(restored.pageAnimationEnabled, isTrue);
      expect(restored.pageAnimationEffect, PageAnimationEffect.slide);
      expect(restored.bookmarkShape, BookmarkShape.strip);
      expect(restored.bookmarkColor, BookmarkColor.purple);
      await reopened.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('v10 migration preserves contents, locations and preferences', () async {
    final dir = await Directory.systemTemp.createTemp('page-view-migration-');
    final path = '${dir.path}${Platform.pathSeparator}test.db';
    try {
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 10,
          singleInstance: false,
          onConfigure: configureDocumentDatabase,
          onCreate: (db, version) async {
            await createDocumentSchema(db, version);
            await db.execute(
              'ALTER TABLE reading_preferences DROP COLUMN bookmark_shape',
            );
            await db.execute(
              'ALTER TABLE reading_preferences DROP COLUMN bookmark_color',
            );
            await db.execute(
              'ALTER TABLE reading_preferences DROP COLUMN page_view',
            );
            await db.execute(
              'ALTER TABLE reading_preferences DROP COLUMN page_animation_enabled',
            );
            await db.execute(
              'ALTER TABLE reading_preferences DROP COLUMN page_animation_effect',
            );
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
        'text': 'Bir. İki.',
      });
      for (final table in ['reading_positions', 'bookmarks']) {
        await old.insert(table, {
          'document_id': 42,
          'page_id': 9,
          'sentence_index': 1,
          'page_text': 'Bir. İki.',
        });
      }
      await old.insert('reading_preferences', {
        'id': 1,
        'speed': 'fast',
        'auto_next_page': 1,
        'follow_sentence': 1,
        'text_size': 'large',
        'text_alignment': 'center',
        'line_spacing': 'wide',
      });
      await old.close();
      final upgraded = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: documentDatabaseVersion,
          singleInstance: false,
          onConfigure: configureDocumentDatabase,
          onUpgrade: upgradeDocumentSchema,
        ),
      );
      try {
        final store = DocumentStore(databaseOpener: () async => upgraded);
        final preferences = ReadingPreferences(store: store);
        await preferences.load();
        expect(preferences.pageView, ReadingPageView.plain);
        expect(preferences.lineSpacing, ReadingLineSpacing.wide);
        expect((await store.getDocument(42))?.title, 'Eski');
        expect((await store.pages(42)).single.position, 4);
        expect((await store.readingPosition(42))?.sentenceIndex, 1);
        expect((await store.bookmark(42))?.sentenceIndex, 1);
      } finally {
        await upgraded.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });

  for (final version in [11, 12]) {
    test(
      'v$version upgrade preserves view and defaults bookmark appearance',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'animation-migration-',
        );
        final path = '${dir.path}${Platform.pathSeparator}test.db';
        try {
          final old = await databaseFactoryFfi.openDatabase(
            path,
            options: OpenDatabaseOptions(
              version: version,
              singleInstance: false,
              onConfigure: configureDocumentDatabase,
              onCreate: (db, version) async {
                await createDocumentSchema(db, version);
                await db.execute(
                  'ALTER TABLE reading_preferences DROP COLUMN bookmark_shape',
                );
                await db.execute(
                  'ALTER TABLE reading_preferences DROP COLUMN bookmark_color',
                );
                if (version == 11) {
                  await db.execute(
                    'ALTER TABLE reading_preferences DROP COLUMN page_animation_enabled',
                  );
                  await db.execute(
                    'ALTER TABLE reading_preferences DROP COLUMN page_animation_effect',
                  );
                }
              },
            ),
          );
          await old.insert('reading_preferences', {
            'id': 1,
            'speed': 'fast',
            'auto_next_page': 1,
            'follow_sentence': 1,
            'text_size': 'large',
            'text_alignment': 'center',
            'line_spacing': 'wide',
            'page_view': 'book',
            if (version == 12) 'page_animation_enabled': 1,
            if (version == 12) 'page_animation_effect': 'turn',
          });
          await old.close();
          final upgraded = await databaseFactoryFfi.openDatabase(
            path,
            options: OpenDatabaseOptions(
              version: documentDatabaseVersion,
              singleInstance: false,
              onConfigure: configureDocumentDatabase,
              onUpgrade: upgradeDocumentSchema,
            ),
          );
          try {
            final preferences = ReadingPreferences(
              store: DocumentStore(databaseOpener: () async => upgraded),
            );
            await preferences.load();
            expect(preferences.pageView, ReadingPageView.book);
            expect(preferences.pageAnimationEnabled, version == 12);
            expect(
              preferences.pageAnimationEffect,
              version == 12
                  ? PageAnimationEffect.turn
                  : PageAnimationEffect.fade,
            );
            expect(preferences.bookmarkShape, BookmarkShape.ribbon);
            expect(preferences.bookmarkColor, BookmarkColor.red);
            expect(preferences.speed, ReadingSpeed.fast);
          } finally {
            await upgraded.close();
          }
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );
  }

  for (final version in [7, 8]) {
    test(
      'v$version migration preserves records and defaults missing preferences',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'alignment-migration-',
        );
        final path = '${dir.path}${Platform.pathSeparator}test.db';
        try {
          final old = await databaseFactoryFfi.openDatabase(
            path,
            options: OpenDatabaseOptions(
              version: version,
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
                await createCategories(db);
                if (version >= 8) await db.execute(addReadingTextAlignmentSql);
              },
            ),
          );
          await old.update(
            'categories',
            {'label': 'Okuduklarım', 'normalized_label': 'okuduklarım'},
            where: 'id = ?',
            whereArgs: ['book'],
          );
          await old.delete(
            'categories',
            where: 'id = ?',
            whereArgs: ['recipe'],
          );
          await old.insert('documents', {
            'id': 42,
            'title': 'Eski',
            'category': 'book',
            'created_at': 7,
          });
          await old.insert('pages', {
            'id': 9,
            'document_id': 42,
            'position': 4,
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
            if (version >= 8) 'text_alignment': 'center',
          });
          await old.close();
          final upgraded = await databaseFactoryFfi.openDatabase(
            path,
            options: OpenDatabaseOptions(
              version: documentDatabaseVersion,
              singleInstance: false,
              onConfigure: configureDocumentDatabase,
              onUpgrade: upgradeDocumentSchema,
            ),
          );
          expect(
            (await upgraded.query('documents')).single['category'],
            'book',
          );
          expect((await upgraded.query('documents')).single['created_at'], 7);
          expect((await upgraded.query('pages')).single['text'], 'Bir. İki.');
          expect(
            (await upgraded.query('reading_positions'))
                .single['sentence_index'],
            1,
          );
          expect(
            (await upgraded.query(
              'categories',
              where: 'id = ?',
              whereArgs: ['book'],
            )).single['label'],
            'Okuduklarım',
          );
          expect(
            await upgraded.query(
              'categories',
              where: 'id = ?',
              whereArgs: ['recipe'],
            ),
            isEmpty,
          );
          expect((await upgraded.query('reading_preferences')).single, {
            'id': 1,
            'speed': 'fast',
            'auto_next_page': 1,
            'follow_sentence': 1,
            'text_size': 'large',
            'text_alignment': version >= 8 ? 'center' : 'start',
            'line_spacing': 'normal',
            'page_view': 'plain',
            'page_animation_enabled': 0,
            'page_animation_effect': 'fade',
            'bookmark_shape': 'ribbon',
            'bookmark_color': 'red',
          });
          await upgraded.close();
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );
  }

  test('v5 migration preserves content, position and preferences', () async {
    final dir = await Directory.systemTemp.createTemp('text-size-migration-');
    final path = '${dir.path}${Platform.pathSeparator}test.db';
    try {
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 5,
          singleInstance: false,
          onConfigure: configureDocumentDatabase,
          onCreate: (db, _) async {
            await db.execute(createDocumentsSql);
            await db.execute(createPagesSql);
            await db.execute(createReadingPositionsSql);
            await db.execute(invalidateReadingPositionSql);
            await db.execute(createReadingPreferencesSql);
            await db.execute(addFollowSentenceSql);
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
      });
      await old.close();
      final upgraded = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: documentDatabaseVersion,
          singleInstance: false,
          onConfigure: configureDocumentDatabase,
          onUpgrade: upgradeDocumentSchema,
        ),
      );
      expect((await upgraded.query('documents')).single['title'], 'Eski');
      expect((await upgraded.query('pages')).single['position'], 4);
      expect(
        (await upgraded.query('reading_positions')).single['sentence_index'],
        1,
      );
      expect((await upgraded.query('reading_preferences')).single, {
        'id': 1,
        'speed': 'fast',
        'auto_next_page': 1,
        'follow_sentence': 1,
        'text_size': 'normal',
        'text_alignment': 'start',
        'line_spacing': 'normal',
        'page_view': 'plain',
        'page_animation_enabled': 0,
        'page_animation_effect': 'fade',
        'bookmark_shape': 'ribbon',
        'bookmark_color': 'red',
      });
      await upgraded.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test(
    'v4 migration preserves existing data and rolls back on failure',
    () async {
      final dir = await Directory.systemTemp.createTemp('follow-migration-');
      final path = '${dir.path}${Platform.pathSeparator}test.db';
      try {
        final old = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 4,
            singleInstance: false,
            onConfigure: configureDocumentDatabase,
            onCreate: (db, _) async {
              await db.execute(createDocumentsSql);
              await db.execute(createPagesSql);
              await db.execute(createReadingPositionsSql);
              await db.execute(invalidateReadingPositionSql);
              await db.execute(createReadingPreferencesSql);
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
        });
        await old.close();
        await expectLater(
          databaseFactoryFfi.openDatabase(
            path,
            options: OpenDatabaseOptions(
              version: 5,
              singleInstance: false,
              onUpgrade: (db, from, to) async {
                await upgradeDocumentSchema(db, from, to);
                throw StateError('migration failed');
              },
            ),
          ),
          throwsStateError,
        );
        final rollback = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(version: 4, singleInstance: false),
        );
        expect(await rollback.getVersion(), 4);
        expect(
          (await rollback.query('reading_preferences')).single
              .containsKey('follow_sentence'),
          isFalse,
        );
        await rollback.close();
        final upgraded = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 5,
            singleInstance: false,
            onConfigure: configureDocumentDatabase,
            onUpgrade: upgradeDocumentSchema,
          ),
        );
        expect((await upgraded.query('documents')).single['created_at'], 7);
        expect((await upgraded.query('pages')).single['position'], 4);
        expect(
          (await upgraded.query('reading_positions')).single['sentence_index'],
          1,
        );
        final row = (await upgraded.query('reading_preferences')).single;
        expect(row['speed'], 'fast');
        expect(row['auto_next_page'], 1);
        expect(row['follow_sentence'], 0);
        await upgraded.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test('v3 upgrade preserves data and a failed upgrade rolls back', () async {
    final dir = await Directory.systemTemp.createTemp('preferences-migration-');
    final path = '${dir.path}${Platform.pathSeparator}test.db';
    try {
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: configureDocumentDatabase,
          onCreate: (db, _) async {
            await db.execute(createDocumentsSql);
            await db.execute(createPagesSql);
            await db.execute(createReadingPositionsSql);
            await db.execute(invalidateReadingPositionSql);
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
        'text': 'Bir. İki.',
      });
      await old.insert('reading_positions', {
        'document_id': 42,
        'page_id': 9,
        'sentence_index': 1,
        'page_text': 'Bir. İki.',
      });
      await old.close();
      await expectLater(
        databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 4,
            singleInstance: false,
            onConfigure: configureDocumentDatabase,
            onUpgrade: (db, from, to) async {
              await upgradeDocumentSchema(db, from, to);
              throw StateError('migration failed');
            },
          ),
        ),
        throwsStateError,
      );
      final rollback = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 3, singleInstance: false),
      );
      expect(await rollback.getVersion(), 3);
      expect(
        await rollback.rawQuery(
          "SELECT name FROM sqlite_master WHERE name = 'reading_preferences'",
        ),
        isEmpty,
      );
      await rollback.close();
      final upgraded = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          singleInstance: false,
          onConfigure: configureDocumentDatabase,
          onUpgrade: upgradeDocumentSchema,
        ),
      );
      expect((await upgraded.query('documents')).single['created_at'], 7);
      expect((await upgraded.query('pages')).single['position'], 4);
      expect(
        (await upgraded.query('reading_positions')).single['sentence_index'],
        1,
      );
      expect(await upgraded.query('reading_preferences'), isEmpty);
      await upgraded.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

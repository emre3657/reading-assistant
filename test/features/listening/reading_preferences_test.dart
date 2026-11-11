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
    expect(store.saveCalls, 0);

    store.values = {
      'speed': 'invalid',
      'auto_next_page': 42,
      'follow_sentence': 42,
      'text_size': 'invalid',
    };
    final invalid = ReadingPreferences(store: store);
    await invalid.load();
    expect(invalid.speed, ReadingSpeed.normal);
    expect(invalid.autoNextPage, isFalse);
    expect(invalid.followSentence, isFalse);
    expect(invalid.textSize, ReadingTextSize.normal);
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
      expect(store.saveCalls, 0);
      store.loadGate!.complete();
      await loading;
      expect(preferences.speed, ReadingSpeed.fast);
      expect(preferences.autoNextPage, isTrue);

      preferences.setSpeed(ReadingSpeed.slow);
      preferences.setSpeed(ReadingSpeed.faster);
      preferences.setAutoNextPage(false);
      preferences.setFollowSentence(true);
      preferences.setTextSize(ReadingTextSize.large);
      preferences.setTextSize(ReadingTextSize.extraLarge);
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
      });
      expect(store.saveCalls, 8);
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
      await preferences.pendingWrites;
      expect(preferences.speed, ReadingSpeed.fast);
      expect(preferences.autoNextPage, isTrue);
      expect(preferences.followSentence, isTrue);
      expect(preferences.textSize, ReadingTextSize.large);
      expect(preferences.errorRevision, 2);
      expect(preferences.errorMessage, contains('kaydedilemedi'));
      store.saveError = null;
      preferences.setSpeed(ReadingSpeed.slow);
      await preferences.pendingWrites;
      expect(store.values!['speed'], 'slow');
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
      await reopened.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

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

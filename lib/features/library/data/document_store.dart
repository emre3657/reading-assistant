import 'package:sqflite/sqflite.dart';

import 'document_page.dart';
import 'document_schema.dart';
import 'reading_position.dart';
import 'saved_document.dart';

class DocumentStore {
  /// An injected opener must return an already configured current database.
  DocumentStore({this.databaseOpener});

  static final instance = DocumentStore();

  final Future<Database> Function()? databaseOpener;
  Future<Database>? _databaseFuture;
  static Future<void> _positionTail = Future.value();

  Future<T> _queuePosition<T>(Future<T> Function() action) {
    final result = _positionTail.then((_) => action());
    _positionTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  /// Serializes position reads, writes and completion so older writes cannot
  /// overwrite a newer sentence or a completion.
  Future<void> saveReadingPosition({
    required int documentId,
    required int pageId,
    required int sentenceIndex,
    required String pageText,
  }) => _queuePosition(() async {
    if (sentenceIndex < 0) throw ArgumentError.value(sentenceIndex);
    final database = await _database;
    await database.transaction((txn) async {
      final page = await txn.query(
        'pages',
        columns: ['id'],
        where: 'document_id = ? AND id = ? AND text = ?',
        whereArgs: [documentId, pageId, pageText],
      );
      if (page.isEmpty) {
        throw StateError('Reading position page is missing or changed.');
      }
      final existing = await txn.query(
        'reading_positions',
        where: 'document_id = ?',
        whereArgs: [documentId],
      );
      final values = {
        'document_id': documentId,
        'page_id': pageId,
        'sentence_index': sentenceIndex,
        'page_text': pageText,
      };
      if (existing.isEmpty) {
        await txn.insert('reading_positions', values);
      } else if (existing.single['page_id'] != pageId ||
          existing.single['sentence_index'] != sentenceIndex ||
          existing.single['page_text'] != pageText) {
        await txn.update(
          'reading_positions',
          values,
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
      }
    });
  });

  Future<ReadingPosition?> readingPosition(int documentId) =>
      _queuePosition(() async {
        final database = await _database;
        return database.transaction((txn) async {
          final rows = await txn.rawQuery(
            '''
            SELECT r.page_id, r.sentence_index, r.page_text,
                   p.id AS valid_page
            FROM reading_positions r
            LEFT JOIN pages p ON p.id = r.page_id
              AND p.document_id = r.document_id AND p.text = r.page_text
            WHERE r.document_id = ?
          ''',
            [documentId],
          );
          if (rows.isEmpty) return null;
          final row = rows.single;
          if (row['valid_page'] == null) {
            await txn.delete(
              'reading_positions',
              where: 'document_id = ?',
              whereArgs: [documentId],
            );
            return null;
          }
          return ReadingPosition(
            pageId: row['page_id'] as int,
            sentenceIndex: row['sentence_index'] as int,
            pageText: row['page_text'] as String,
          );
        });
      });

  Future<void> completeReadingPage({
    required int documentId,
    required int pageId,
  }) => _queuePosition(() async {
    final database = await _database;
    await database.rawDelete(
      '''
      DELETE FROM reading_positions
      WHERE document_id = ?
        AND ? = (
          SELECT id FROM pages WHERE document_id = ?
          ORDER BY position DESC, id DESC LIMIT 1
        )
    ''',
      [documentId, pageId, documentId],
    );
  });

  Future<Database> get _database => _databaseFuture ??= _open();

  Future<Map<String, Object?>?> loadReadingPreferences() async {
    final database = await _database;
    final rows = await database.query('reading_preferences', where: 'id = 1');
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> saveReadingPreferences({
    required String speed,
    required bool autoNextPage,
    required bool followSentence,
  }) async {
    final database = await _database;
    await database.insert('reading_preferences', {
      'id': 1,
      'speed': speed,
      'auto_next_page': autoNextPage ? 1 : 0,
      'follow_sentence': followSentence ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Database> _open() async {
    try {
      final opener = databaseOpener;
      if (opener != null) return await opener();
      return await openDatabase(
        'reading_assistant.db',
        version: documentDatabaseVersion,
        onConfigure: configureDocumentDatabase,
        onCreate: createDocumentSchema,
        onUpgrade: upgradeDocumentSchema,
      );
    } catch (_) {
      _databaseFuture = null;
      rethrow;
    }
  }

  Future<int> save({
    required String title,
    required DocumentCategory category,
    required String text,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || text.trim().isEmpty) {
      throw ArgumentError('Title and text must not be empty.');
    }
    final database = await _database;
    // Metadata and the first page must either both exist or neither exist.
    return database.transaction((transaction) async {
      final id = await transaction.insert('documents', {
        'title': cleanTitle,
        'category': category.name,
        'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      });
      await transaction.insert('pages', {
        'document_id': id,
        'position': 0,
        'text': text,
      });
      return id;
    });
  }

  /// Legacy combined update retained for compatibility. New editors use
  /// updateDetails and updatePageText separately.
  Future<bool> update({
    required int id,
    required String title,
    required DocumentCategory category,
    required String text,
  }) => _queuePosition(() async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || text.trim().isEmpty) {
      throw ArgumentError('Title and text must not be empty.');
    }
    final database = await _database;
    return database.transaction((transaction) async {
      final documents = await transaction.query(
        'documents',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (documents.isEmpty) return false;

      final pages = await transaction.query(
        'pages',
        columns: ['id'],
        where: 'document_id = ?',
        whereArgs: [id],
      );
      if (pages.length != 1) {
        // Never silently overwrite a multi-page document through the old UI.
        throw StateError('Single-page update requires exactly one page.');
      }
      await transaction.update(
        'documents',
        {'title': cleanTitle, 'category': category.name},
        where: 'id = ?',
        whereArgs: [id],
      );
      final updated = await transaction.update(
        'pages',
        {'text': text},
        where: 'id = ?',
        whereArgs: [pages.single['id']],
      );
      if (updated != 1) throw StateError('Page update failed.');
      return true;
    });
  });

  /// Changes content metadata without writing to any page.
  Future<bool> updateDetails({
    required int id,
    required String title,
    required DocumentCategory category,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || cleanTitle.length > 120) {
      throw ArgumentError('Title must contain between 1 and 120 characters.');
    }
    final database = await _database;
    return await database.update(
          'documents',
          {'title': cleanTitle, 'category': category.name},
          where: 'id = ?',
          whereArgs: [id],
        ) >
        0;
  }

  /// Changes one page only; stale reader metadata can never overwrite details.
  Future<bool> updatePageText({
    required int documentId,
    required int pageId,
    required String text,
  }) => _queuePosition(() async {
    if (text.trim().isEmpty) {
      throw ArgumentError('Page text must not be empty.');
    }
    final database = await _database;
    return await database.update(
          'pages',
          {'text': text},
          where: 'id = ? AND document_id = ?',
          whereArgs: [pageId, documentId],
        ) >
        0;
  });

  /// Foreign-key cascade removes every page belonging to this document.
  Future<bool> delete(int id) async {
    final database = await _database;
    return await database.delete(
          'documents',
          where: 'id = ?',
          whereArgs: [id],
        ) >
        0;
  }

  /// Lists content metadata with the first page as a preview adapter.
  Future<List<SavedDocument>> list() async {
    final database = await _database;
    final rows = await database.rawQuery('''
      SELECT d.id, d.title, d.category, d.created_at,
        COALESCE((
          SELECT p.text FROM pages p
          WHERE p.document_id = d.id
          ORDER BY p.position, p.id LIMIT 1
        ), '') AS text
      FROM documents d
      ORDER BY d.created_at DESC, d.id DESC
    ''');
    return rows.map(SavedDocument.fromMap).toList(growable: false);
  }

  Future<SavedDocument?> getDocument(int id) async {
    final database = await _database;
    final rows = await database.rawQuery(
      '''
      SELECT d.id, d.title, d.category, d.created_at,
        COALESCE((
          SELECT p.text FROM pages p WHERE p.document_id = d.id
          ORDER BY p.position, p.id LIMIT 1
        ), '') AS text
      FROM documents d WHERE d.id = ?
    ''',
      [id],
    );
    return rows.isEmpty ? null : SavedDocument.fromMap(rows.single);
  }

  /// Appends to this content, never creating a separate document.
  Future<DocumentPage> appendPage({
    required int documentId,
    required String text,
  }) async {
    if (text.trim().isEmpty) {
      throw ArgumentError('Page text must not be empty.');
    }
    final database = await _database;
    return database.transaction((transaction) async {
      final owner = await transaction.query(
        'documents',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [documentId],
      );
      if (owner.isEmpty) throw StateError('Document not found.');
      final rows = await transaction.rawQuery(
        'SELECT COALESCE(MAX(position), -1) + 1 AS next_position '
        'FROM pages WHERE document_id = ?',
        [documentId],
      );
      final position = rows.single['next_position'] as int;
      final id = await transaction.insert('pages', {
        'document_id': documentId,
        'position': position,
        'text': text,
      });
      return DocumentPage(
        id: id,
        documentId: documentId,
        position: position,
        text: text,
      );
    });
  }

  /// Legacy combined operation; the page editor uses updatePageText instead.
  Future<bool> updatePage({
    required int documentId,
    required int pageId,
    required String title,
    required DocumentCategory category,
    required String text,
  }) => _queuePosition(() async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || text.trim().isEmpty) {
      throw ArgumentError('Title and text must not be empty.');
    }
    final database = await _database;
    return database.transaction((transaction) async {
      final page = await transaction.query(
        'pages',
        columns: ['id'],
        where: 'id = ? AND document_id = ?',
        whereArgs: [pageId, documentId],
      );
      if (page.isEmpty) return false;
      final count = await transaction.update(
        'documents',
        {'title': cleanTitle, 'category': category.name},
        where: 'id = ?',
        whereArgs: [documentId],
      );
      if (count != 1) throw StateError('Document update failed.');
      final updated = await transaction.update(
        'pages',
        {'text': text},
        where: 'id = ? AND document_id = ?',
        whereArgs: [pageId, documentId],
      );
      if (updated != 1) throw StateError('Page update failed.');
      return true;
    });
  });

  /// Removes only the selected page belonging to this content. Remaining
  /// positions stay stable; the UI numbers pages by their current list order.
  /// An empty content remains available for adding new pages.
  Future<bool> deletePage({
    required int documentId,
    required int pageId,
  }) async {
    final database = await _database;
    return await database.delete(
          'pages',
          where: 'id = ? AND document_id = ?',
          whereArgs: [pageId, documentId],
        ) >
        0;
  }

  /// Saves a new page order for one content. [orderedPageIds] must contain
  /// every page of [documentId] exactly once. Returns false (and writes
  /// nothing) when the order and the 0..n-1 positions are already as given.
  ///
  /// Positions are first moved above the current maximum, so the unique
  /// (document_id, position) constraint never collides, then renumbered
  /// 0..n-1 (which also closes gaps left by deleted pages). Any failure rolls
  /// the whole transaction back.
  Future<bool> reorderPages({
    required int documentId,
    required List<int> orderedPageIds,
  }) async {
    final database = await _database;
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        'pages',
        columns: ['id', 'position'],
        where: 'document_id = ?',
        whereArgs: [documentId],
        orderBy: 'position ASC, id ASC',
      );
      final currentIds = [for (final row in rows) row['id'] as int];

      if (orderedPageIds.length != currentIds.length ||
          orderedPageIds.toSet().length != orderedPageIds.length ||
          !currentIds.toSet().containsAll(orderedPageIds)) {
        throw ArgumentError(
          'Page ids must list every page of the document exactly once.',
        );
      }
      if (rows.isEmpty) return false;

      var unchanged = true;
      for (var i = 0; i < rows.length; i++) {
        if (currentIds[i] != orderedPageIds[i] || rows[i]['position'] != i) {
          unchanged = false;
          break;
        }
      }
      if (unchanged) return false;

      final maxPosition = rows
          .map((row) => row['position'] as int)
          .reduce((a, b) => a > b ? a : b);

      for (var i = 0; i < orderedPageIds.length; i++) {
        await transaction.update(
          'pages',
          {'position': maxPosition + 1 + i},
          where: 'id = ? AND document_id = ?',
          whereArgs: [orderedPageIds[i], documentId],
        );
      }
      for (var i = 0; i < orderedPageIds.length; i++) {
        final count = await transaction.update(
          'pages',
          {'position': i},
          where: 'id = ? AND document_id = ?',
          whereArgs: [orderedPageIds[i], documentId],
        );
        if (count != 1) throw StateError('Page reorder failed.');
      }
      return true;
    });
  }

  Future<List<DocumentPage>> pages(int documentId) async {
    final database = await _database;
    final rows = await database.query(
      'pages',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'position ASC, id ASC',
    );
    return rows.map(DocumentPage.fromMap).toList(growable: false);
  }
}

import 'package:sqflite/sqflite.dart';

import 'document_page.dart';
import 'document_schema.dart';
import 'saved_document.dart';

class DocumentStore {
  /// An injected opener must return an already configured v2 database.
  DocumentStore({this.databaseOpener});

  static final instance = DocumentStore();

  final Future<Database> Function()? databaseOpener;
  Future<Database>? _databaseFuture;

  Future<Database> get _database => _databaseFuture ??= _open();

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

  /// Compatibility method for the current single-page editing screen.
  /// Multi-page editing will use explicit page operations in the next step.
  Future<bool> update({
    required int id,
    required String title,
    required DocumentCategory category,
    required String text,
  }) async {
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
  }

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

  /// Temporary adapter for the existing single-page UI. At this stage all
  /// app-created documents have exactly one page; the next UI will read pages.
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

  /// Updates the selected page and shared metadata atomically. Other pages
  /// and the document creation date are left untouched.
  Future<bool> updatePage({
    required int documentId,
    required int pageId,
    required String title,
    required DocumentCategory category,
    required String text,
  }) async {
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

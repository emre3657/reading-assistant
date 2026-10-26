import 'package:sqflite/sqflite.dart';

import 'saved_document.dart';

class DocumentStore {
  DocumentStore._();

  static final instance = DocumentStore._();

  Future<Database>? _databaseFuture;

  Future<Database> get _database {
    return _databaseFuture ??= _open();
  }

  Future<Database> _open() async {
    try {
      return await openDatabase(
        'reading_assistant.db',
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE documents (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              category TEXT NOT NULL,
              text TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');
        },
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

    return database.insert('documents', {
      'title': cleanTitle,
      'category': category.name,
      // Preserve the user's text, including paragraph boundaries.
      'text': text,
      'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  Future<List<SavedDocument>> list() async {
    final database = await _database;
    final rows = await database.query(
      'documents',
      orderBy: 'created_at DESC, id DESC',
    );

    return rows.map(SavedDocument.fromMap).toList(growable: false);
  }
}

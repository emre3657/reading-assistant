import 'package:sqflite/sqflite.dart';

const documentDatabaseVersion = 2;

const createDocumentsSql = '''
CREATE TABLE documents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  category TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
''';

const createPagesSql = '''
CREATE TABLE pages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  document_id INTEGER NOT NULL,
  position INTEGER NOT NULL CHECK (position >= 0),
  text TEXT NOT NULL,
  FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE,
  UNIQUE (document_id, position)
)
''';

const renameLegacyDocumentsSql = 'ALTER TABLE documents RENAME TO documents_v1';

const copyLegacyDocumentsSql = '''
INSERT INTO documents (id, title, category, created_at)
SELECT id, title, category, created_at FROM documents_v1
''';

const copyLegacyPagesSql = '''
INSERT INTO pages (document_id, position, text)
SELECT id, 0, text FROM documents_v1
''';

const dropLegacyDocumentsSql = 'DROP TABLE documents_v1';

Future<void> configureDocumentDatabase(Database database) async {
  // This must be enabled before the creation/upgrade transaction begins.
  await database.execute('PRAGMA foreign_keys = ON');
}

Future<void> createDocumentSchema(Database database, int version) async {
  await database.execute(createDocumentsSql);
  await database.execute(createPagesSql);
}

Future<void> upgradeDocumentSchema(
  Database database,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion < 2 && newVersion >= 2) {
    // sqflite already runs onUpgrade inside a transaction. Do not nest one.
    await database.execute(renameLegacyDocumentsSql);
    await database.execute(createDocumentsSql);
    await database.execute(createPagesSql);
    await database.execute(copyLegacyDocumentsSql);
    await database.execute(copyLegacyPagesSql);
    await database.execute(dropLegacyDocumentsSql);
  }
}

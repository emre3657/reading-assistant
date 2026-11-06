import 'package:sqflite/sqflite.dart';

const documentDatabaseVersion = 3;

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

const createReadingPositionsSql = '''
CREATE TABLE reading_positions (
  document_id INTEGER PRIMARY KEY,
  page_id INTEGER NOT NULL,
  sentence_index INTEGER NOT NULL CHECK (sentence_index >= 0),
  page_text TEXT NOT NULL,
  FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE,
  FOREIGN KEY (page_id) REFERENCES pages(id) ON DELETE CASCADE
)
''';

const invalidateReadingPositionSql = '''
CREATE TRIGGER invalidate_reading_position
AFTER UPDATE OF text ON pages
WHEN OLD.text != NEW.text
BEGIN
  DELETE FROM reading_positions WHERE page_id = OLD.id;
END
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
  await database.execute(createReadingPositionsSql);
  await database.execute(invalidateReadingPositionSql);
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
  if (oldVersion < 3 && newVersion >= 3) {
    await database.execute(createReadingPositionsSql);
    await database.execute(invalidateReadingPositionSql);
  }
}

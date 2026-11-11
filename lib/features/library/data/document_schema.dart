import 'package:sqflite/sqflite.dart';

import 'saved_document.dart';
import 'turkish_text.dart';

const documentDatabaseVersion = 7;

String normalizeCategoryName(String name) => normalizeTurkishCase(name.trim());

const createCategoriesSql = '''
CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  normalized_label TEXT NOT NULL UNIQUE
)
''';

Future<void> createCategories(DatabaseExecutor database) async {
  await database.execute(createCategoriesSql);
  await ensureBuiltInCategories(database);
  final legacy = await database.rawQuery(
    'SELECT DISTINCT category FROM documents WHERE category NOT IN (SELECT id FROM categories)',
  );
  for (final row in legacy) {
    final id = row['category'] as String;
    var label = id.trim().isEmpty ? 'Eski kategori' : id.trim();
    var suffix = 1;
    final base = label;
    while ((await database.query(
      'categories',
      columns: ['id'],
      where: 'normalized_label = ?',
      whereArgs: [normalizeCategoryName(label)],
    )).isNotEmpty) {
      label = '$base (${suffix++})';
    }
    await database.insert('categories', {
      'id': id,
      'label': label,
      'normalized_label': normalizeCategoryName(label),
    });
  }
  await database.execute('''
    CREATE TRIGGER validate_document_category_insert
    BEFORE INSERT ON documents
    WHEN NOT EXISTS (SELECT 1 FROM categories WHERE id = NEW.category)
    BEGIN SELECT RAISE(ABORT, 'Invalid category'); END
  ''');
  await database.execute('''
    CREATE TRIGGER validate_document_category_update
    BEFORE UPDATE OF category ON documents
    WHEN NOT EXISTS (SELECT 1 FROM categories WHERE id = NEW.category)
    BEGIN SELECT RAISE(ABORT, 'Invalid category'); END
  ''');
  await database.execute('''
    CREATE TRIGGER prevent_referenced_category_delete
    BEFORE DELETE ON categories
    WHEN EXISTS (SELECT 1 FROM documents WHERE category = OLD.id)
    BEGIN SELECT RAISE(ABORT, 'Category is in use'); END
  ''');
}

Future<void> ensureBuiltInCategories(DatabaseExecutor database) async {
  for (final category in DocumentCategory.values) {
    final existing = await database.query(
      'categories',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [category.name],
    );
    if (existing.isEmpty) {
      await database.insert('categories', {
        'id': category.name,
        'label': category.label,
        'normalized_label': normalizeCategoryName(category.label),
      });
    }
  }
}

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

const createReadingPreferencesSql = '''
CREATE TABLE reading_preferences (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  speed TEXT NOT NULL,
  auto_next_page INTEGER NOT NULL
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
  await database.execute(createReadingPositionsSql);
  await database.execute(invalidateReadingPositionSql);
  await database.execute(createReadingPreferencesSql);
  await database.execute(addFollowSentenceSql);
  await database.execute(addReadingTextSizeSql);
  await createCategories(database);
}

const addFollowSentenceSql =
    'ALTER TABLE reading_preferences ADD COLUMN follow_sentence INTEGER NOT NULL DEFAULT 0';

const addReadingTextSizeSql =
    "ALTER TABLE reading_preferences ADD COLUMN text_size TEXT NOT NULL DEFAULT 'normal'";

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
  if (oldVersion < 4 && newVersion >= 4) {
    await database.execute(createReadingPreferencesSql);
  }
  if (oldVersion < 5 && newVersion >= 5) {
    await database.execute(addFollowSentenceSql);
  }
  if (oldVersion < 6 && newVersion >= 6) {
    await database.execute(addReadingTextSizeSql);
  }
  if (oldVersion < 7 && newVersion >= 7) {
    await createCategories(database);
  }
}

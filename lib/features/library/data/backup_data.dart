import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import '../../listening/services/sentence_splitter.dart';
import 'document_schema.dart';

const backupFormat = 'reading-assistant';
const backupVersion = 1;

Future<BackupData> validateBackupTables(Map tables) =>
    Isolate.run(() => BackupData.fromTables(tables));

Future<BackupData> decodeBackup(Uint8List bytes) =>
    Isolate.run(() => BackupData.decode(bytes));

const backupColumns = <String, Map<String, Type>>{
  'categories': {'id': String, 'label': String, 'normalized_label': String},
  'documents': {
    'id': int,
    'title': String,
    'category': String,
    'created_at': int,
  },
  'pages': {'id': int, 'document_id': int, 'position': int, 'text': String},
  'reading_positions': {
    'document_id': int,
    'page_id': int,
    'sentence_index': int,
    'page_text': String,
  },
  'bookmarks': {
    'document_id': int,
    'page_id': int,
    'sentence_index': int,
    'page_text': String,
  },
  'reading_preferences': {
    'id': int,
    'speed': String,
    'auto_next_page': int,
    'follow_sentence': int,
    'text_size': String,
    'text_alignment': String,
    'line_spacing': String,
    'page_view': String,
    'page_animation_enabled': int,
    'page_animation_effect': String,
    'bookmark_shape': String,
    'bookmark_color': String,
    'theme_mode': String,
    'theme_palette': String,
  },
};

class BackupData {
  BackupData._(this.tables);

  final Map<String, List<Map<String, Object?>>> tables;

  int get documentCount => tables['documents']!.length;
  int get pageCount => tables['pages']!.length;

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format': backupFormat,
        'version': backupVersion,
        'data': tables,
      }),
    ),
  );

  static BackupData decode(Uint8List bytes) {
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map ||
        decoded['format'] != backupFormat ||
        decoded['version'] != backupVersion ||
        decoded['version'] is! int ||
        decoded.length != 3 ||
        decoded['data'] is! Map) {
      throw const FormatException('Unsupported backup format.');
    }
    return fromTables(decoded['data'] as Map);
  }

  static BackupData fromTables(Map raw) {
    if (raw.length != backupColumns.length ||
        !backupColumns.keys.every(raw.containsKey)) {
      throw const FormatException('Missing backup tables.');
    }
    final tables = <String, List<Map<String, Object?>>>{};
    for (final entry in backupColumns.entries) {
      final value = raw[entry.key];
      if (value is! List) throw const FormatException('Invalid table.');
      final rows = <Map<String, Object?>>[];
      for (final item in value) {
        if (item is! Map) {
          throw const FormatException('Invalid row.');
        }
        const optionalDefaults = <String, Object>{
          'page_view': 'plain',
          'page_animation_enabled': 0,
          'page_animation_effect': 'fade',
          'bookmark_shape': 'ribbon',
          'bookmark_color': 'red',
          'theme_mode': 'system',
          'theme_palette': 'turquoise',
        };
        final missing = entry.key == 'reading_preferences'
            ? optionalDefaults.keys
                  .where((key) => !item.containsKey(key))
                  .length
            : 0;
        if (item.length != entry.value.length - missing) {
          throw const FormatException('Invalid row.');
        }
        final row = <String, Object?>{};
        for (final column in entry.value.entries) {
          final field =
              entry.key == 'reading_preferences' &&
                  !item.containsKey(column.key)
              ? optionalDefaults[column.key]
              : item[column.key];
          if ((column.value == int && field is! int) ||
              (column.value == String && field is! String)) {
            throw const FormatException('Invalid field.');
          }
          row[column.key] = field;
        }
        if (entry.key == 'reading_preferences' &&
            !{'plain', 'book'}.contains(row['page_view'])) {
          row['page_view'] = 'plain';
        }
        if (entry.key == 'reading_preferences' &&
            !{'fade', 'slide', 'turn'}.contains(row['page_animation_effect'])) {
          row['page_animation_effect'] = 'fade';
        }
        if (entry.key == 'reading_preferences' &&
            !{'strip', 'ribbon', 'corner'}.contains(row['bookmark_shape'])) {
          row['bookmark_shape'] = 'ribbon';
        }
        if (entry.key == 'reading_preferences' &&
            !{
              'red',
              'teal',
              'blue',
              'purple',
            }.contains(row['bookmark_color'])) {
          row['bookmark_color'] = 'red';
        }
        if (entry.key == 'reading_preferences' &&
            !{'system', 'light', 'dark'}.contains(row['theme_mode'])) {
          row['theme_mode'] = 'system';
        }
        if (entry.key == 'reading_preferences' &&
            !{
              'turquoise',
              'blue',
              'purple',
              'green',
            }.contains(row['theme_palette'])) {
          row['theme_palette'] = 'turquoise';
        }
        rows.add(row);
      }
      tables[entry.key] = rows;
    }
    final categories = <String>{};
    final normalizedLabels = <String>{};
    for (final row in tables['categories']!) {
      final id = row['id'] as String;
      final label = row['label'] as String;
      final normalized = row['normalized_label'] as String;
      if (id.isEmpty ||
          label.trim().isEmpty ||
          normalized != normalizeCategoryName(label) ||
          !categories.add(id) ||
          !normalizedLabels.add(normalized)) {
        throw const FormatException('Invalid category.');
      }
    }
    if (categories.isEmpty) throw const FormatException('Missing categories.');
    final documents = <int>{};
    for (final row in tables['documents']!) {
      if (!documents.add(row['id'] as int) ||
          (row['title'] as String).trim().isEmpty ||
          !categories.contains(row['category']) ||
          (row['created_at'] as int) < -8640000000000000 ||
          (row['created_at'] as int) > 8640000000000000) {
        throw const FormatException('Invalid document.');
      }
    }
    final pages = <int, Map<String, Object?>>{};
    final pageOrders = <(int, int)>{};
    for (final row in tables['pages']!) {
      final id = row['id'] as int;
      final documentId = row['document_id'] as int;
      final position = row['position'] as int;
      if (pages.containsKey(id) ||
          !documents.contains(documentId) ||
          position < 0 ||
          !pageOrders.add((documentId, position))) {
        throw const FormatException('Invalid page.');
      }
      pages[id] = row;
    }
    for (final table in ['reading_positions', 'bookmarks']) {
      final owners = <int>{};
      for (final row in tables[table]!) {
        final owner = row['document_id'] as int;
        final page = pages[row['page_id']];
        final index = row['sentence_index'] as int;
        if (!owners.add(owner) ||
            page == null ||
            page['document_id'] != owner ||
            page['text'] != row['page_text']) {
          throw const FormatException('Invalid reading location.');
        }
        final sentences = splitSentences(page['text'] as String);
        if (index < 0 ||
            (sentences.isEmpty ? index != 0 : index >= sentences.length)) {
          throw const FormatException('Invalid sentence.');
        }
      }
    }
    final preferences = tables['reading_preferences']!;
    if (preferences.length > 1) {
      throw const FormatException('Invalid preferences.');
    }
    if (preferences.isNotEmpty) {
      final row = preferences.single;
      if (row['id'] != 1 ||
          !{
            'slow',
            'slow08',
            'slow09',
            'normal',
            'fast',
            'faster',
          }.contains(row['speed']) ||
          !{0, 1}.contains(row['auto_next_page']) ||
          !{0, 1}.contains(row['follow_sentence']) ||
          !{0, 1}.contains(row['page_animation_enabled']) ||
          !{'normal', 'large', 'extraLarge'}.contains(row['text_size']) ||
          !{
            'start',
            'center',
            'right',
            'justify',
          }.contains(row['text_alignment']) ||
          !{'normal', 'relaxed', 'wide'}.contains(row['line_spacing'])) {
        throw const FormatException('Invalid preferences.');
      }
    }
    return BackupData._(
      Map.unmodifiable({
        for (final entry in tables.entries)
          entry.key: List<Map<String, Object?>>.unmodifiable(
            entry.value.map((row) => Map<String, Object?>.unmodifiable(row)),
          ),
      }),
    );
  }
}

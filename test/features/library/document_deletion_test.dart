import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/library_screen.dart';
import 'package:sqflite/sqflite.dart';

SavedDocument _document(int id, String title) {
  return SavedDocument(
    id: id,
    title: title,
    category: DocumentCategory.note,
    text: '$title metni.',
    createdAt: DateTime(2026, 1, 1),
  );
}

class _FakeStore extends DocumentStore {
  _FakeStore(this.documents);

  List<SavedDocument> documents;
  final deletedIds = <int>[];

  Object? deleteError;
  Completer<void>? deleteGate;
  bool deleteResult = true;
  int listCalls = 0;

  @override
  Future<List<SavedDocument>> list() async {
    listCalls++;
    return List<SavedDocument>.of(documents);
  }

  @override
  Future<bool> delete(int id) async {
    deletedIds.add(id);
    await deleteGate?.future;

    if (deleteError != null) throw deleteError!;

    documents = [
      for (final document in documents)
        if (document.id != id) document,
    ];

    return deleteResult;
  }
}

/// Tests the Database API boundary, not real SQLite execution.
class _RecordingDatabase implements Database {
  int affectedRows = 1;
  String? deletedTable;
  String? whereClause;
  List<Object?>? arguments;

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    deletedTable = table;
    whereClause = where;
    arguments = whereArgs == null ? null : List<Object?>.of(whereArgs);
    return affectedRows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

Future<void> _showLibrary(WidgetTester tester, _FakeStore store) async {
  await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
  await tester.pumpAndSettle();
}

Future<void> _requestDeletion(WidgetTester tester, int id) async {
  await tester.tap(find.byKey(ValueKey('document-menu-$id')));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Sil'));
  await tester.pumpAndSettle();
}

void main() {
  group('DocumentStore.delete', () {
    test('targets only the requested id', () async {
      final database = _RecordingDatabase();
      final store = DocumentStore(databaseOpener: () async => database);

      final deleted = await store.delete(7);

      expect(deleted, isTrue);
      expect(database.deletedTable, 'documents');
      expect(database.whereClause, 'id = ?');
      expect(database.arguments, [7]);
    });

    test('returns false when no record was deleted', () async {
      final database = _RecordingDatabase()..affectedRows = 0;
      final store = DocumentStore(databaseOpener: () async => database);

      expect(await store.delete(99), isFalse);
    });

    test('propagates database failures', () async {
      final store = DocumentStore(
        databaseOpener: () async => throw StateError('database unavailable'),
      );

      await expectLater(store.delete(7), throwsStateError);
    });
  });

  group('deletion from library', () {
    testWidgets('cancel keeps the record without deleting', (tester) async {
      final store = _FakeStore([_document(1, 'Birinci')]);
      await _showLibrary(tester, store);

      await _requestDeletion(tester, 1);

      expect(find.text('Kayıt silinsin mi?'), findsOneWidget);
      expect(
        find.text('“Birinci” silinecek.\n\nBu işlem geri alınamaz.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      expect(store.deletedIds, isEmpty);
      expect(store.listCalls, 1);
      expect(find.byKey(const ValueKey('document-1')), findsOneWidget);
    });

    testWidgets('confirmation deletes only the selected record', (
      tester,
    ) async {
      final store = _FakeStore([
        _document(1, 'Birinci'),
        _document(2, 'İkinci'),
      ]);
      await _showLibrary(tester, store);

      await _requestDeletion(tester, 1);
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      expect(store.deletedIds, [1]);
      expect(store.listCalls, 2);
      expect(find.byKey(const ValueKey('document-1')), findsNothing);
      expect(find.byKey(const ValueKey('document-2')), findsOneWidget);
      expect(find.text('Kayıt silindi.'), findsOneWidget);
    });

    testWidgets('deleting the last record shows the empty state', (
      tester,
    ) async {
      final store = _FakeStore([_document(1, 'Birinci')]);
      await _showLibrary(tester, store);

      await _requestDeletion(tester, 1);
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNothing);
      expect(
        find.text(
          'Henüz kayıt yok. Çıkardığın metni kaydederek başlayabilirsin.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('failure keeps the record and allows retry', (tester) async {
      final store = _FakeStore([_document(1, 'Birinci')])
        ..deleteError = StateError('disk');

      await _showLibrary(tester, store);
      await _requestDeletion(tester, 1);
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('document-1')), findsOneWidget);
      expect(
        find.text('Kayıt silinemedi. Tekrar deneyebilirsin.'),
        findsOneWidget,
      );
      expect(store.listCalls, 1);

      store.deleteError = null;

      await _requestDeletion(tester, 1);
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      expect(store.deletedIds, [1, 1]);
      expect(find.byKey(const ValueKey('document-1')), findsNothing);
    });

    testWidgets('actions are disabled while deletion is pending', (
      tester,
    ) async {
      final gate = Completer<void>();
      final store = _FakeStore([
        _document(1, 'Birinci'),
        _document(2, 'İkinci'),
      ])..deleteGate = gate;

      await _showLibrary(tester, store);
      await _requestDeletion(tester, 1);
      await tester.tap(find.text('Sil'));

      // Do not pumpAndSettle while an indeterminate progress indicator runs.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(store.deletedIds, [1]);

      final otherRow = tester.widget<ListTile>(
        find.byKey(const ValueKey('document-2')),
      );
      expect(otherRow.onTap, isNull);

      final refresh = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Yenile',
        ),
      );
      expect(refresh.onPressed, isNull);

      final menu = tester.widget<PopupMenuButton>(
        find.byKey(const ValueKey('document-menu-2')),
      );
      expect(menu.enabled, isFalse);

      gate.complete();
      await tester.pumpAndSettle();

      expect(store.deletedIds, [1]);
      expect(
        tester.widget<ListTile>(find.byKey(const ValueKey('document-2'))).onTap,
        isNotNull,
      );
    });

    testWidgets('missing record refreshes without claiming deletion', (
      tester,
    ) async {
      final store = _FakeStore([_document(1, 'Birinci')])..deleteResult = false;

      await _showLibrary(tester, store);
      await _requestDeletion(tester, 1);
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      expect(find.text('Kayıt silindi.'), findsNothing);
      expect(
        find.text('Kayıt zaten kaldırılmış. Liste yenilendi.'),
        findsOneWidget,
      );
      expect(store.listCalls, 2);
    });

    testWidgets('completion after screen disposal is safe', (tester) async {
      final gate = Completer<void>();
      final store = _FakeStore([_document(1, 'Birinci')])..deleteGate = gate;

      await _showLibrary(tester, store);
      await _requestDeletion(tester, 1);
      await tester.tap(find.text('Sil'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(store.deletedIds, [1]);

      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}

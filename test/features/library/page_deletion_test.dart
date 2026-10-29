import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/document_contents_screen.dart';

class _Store extends DocumentStore {
  final document = SavedDocument(
    id: 7,
    title: 'Kitabım',
    category: DocumentCategory.book,
    text: 'Birinci.',
    createdAt: DateTime(2026),
  );
  List<DocumentPage> stored = const [
    DocumentPage(id: 70, documentId: 7, position: 0, text: 'Birinci.'),
    DocumentPage(id: 71, documentId: 7, position: 1, text: 'İkinci.'),
    DocumentPage(id: 72, documentId: 7, position: 2, text: 'Üçüncü.'),
  ];
  int calls = 0;
  int? deletedDocumentId;
  int? deletedPageId;
  Object? error;
  bool result = true;
  Completer<void>? gate;

  @override
  Future<SavedDocument?> getDocument(int id) async => document;
  @override
  Future<List<DocumentPage>> pages(int documentId) async => [...stored];
  @override
  Future<bool> deletePage({
    required int documentId,
    required int pageId,
  }) async {
    calls++;
    deletedDocumentId = documentId;
    deletedPageId = pageId;
    await gate?.future;
    if (error != null) throw error!;
    // Missing-record path simulates an already removed page.
    stored = stored.where((p) => p.id != pageId).toList();
    return result;
  }
}

Future<void> _show(
  WidgetTester tester,
  _Store store, {
  VoidCallback? onUpdated,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DocumentContentsScreen(
        document: store.document,
        store: store,
        onUpdated: onUpdated,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester, int id) async {
  await tester.tap(find.byKey(ValueKey('page-menu-$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sil'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cancel does not delete or notify', (tester) async {
    final store = _Store();
    var updates = 0;
    await _show(tester, store, onUpdated: () => updates++);
    await _confirm(tester, 71);
    expect(find.text('Sayfa 2 silinsin mi?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(store.calls, 0);
    expect(store.stored, hasLength(3));
    expect(updates, 0);
  });

  testWidgets('deletes selected page and renumbers visible pages', (
    tester,
  ) async {
    final store = _Store();
    var updates = 0;
    await _show(tester, store, onUpdated: () => updates++);
    await _confirm(tester, 71);
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(store.deletedDocumentId, 7);
    expect(store.deletedPageId, 71);
    expect(find.text('İkinci.'), findsNothing);
    final last = find.byKey(const ValueKey('page-72'));
    expect(
      find.descendant(of: last, matching: find.text('Sayfa 2')),
      findsOneWidget,
    );
    expect(find.text('Birinci.'), findsOneWidget);
    expect(updates, 1);
  });

  testWidgets('last page removal leaves empty content and add action', (
    tester,
  ) async {
    final store = _Store()
      ..stored = const [
        DocumentPage(id: 70, documentId: 7, position: 0, text: 'Birinci.'),
      ];
    await _show(tester, store);
    await _confirm(tester, 70);
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.text('Kitabım'), findsOneWidget);
    expect(find.text('Kitap · 0 sayfa'), findsOneWidget);
    expect(find.textContaining('Henüz sayfa yok.'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('add-page')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('failure preserves page and supports retry', (tester) async {
    final store = _Store()..error = StateError('disk');
    await _show(tester, store);
    await _confirm(tester, 71);
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.text('İkinci.'), findsOneWidget);
    expect(
      find.text('Sayfa silinemedi. Tekrar deneyebilirsin.'),
      findsOneWidget,
    );
    store.error = null;
    await _confirm(tester, 71);
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(store.calls, 2);
    expect(find.text('İkinci.'), findsNothing);
  });

  testWidgets('pending deletion disables actions and blocks system back', (
    tester,
  ) async {
    final store = _Store()..gate = Completer<void>();
    await _show(tester, store);
    await _confirm(tester, 71);
    await tester.tap(find.text('Sil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('add-page')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<PopupMenuButton<String>>(
            find.byKey(const ValueKey('content-options')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<PopupMenuButton<String>>(
            find.byKey(const ValueKey('page-menu-70')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester.widget<ListTile>(find.byKey(const ValueKey('page-70'))).onTap,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(DocumentContentsScreen), findsOneWidget);
    expect(store.calls, 1);
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('İkinci.'), findsNothing);
  });

  testWidgets('missing page reloads without claiming successful deletion', (
    tester,
  ) async {
    final store = _Store()..result = false;
    await _show(tester, store);
    await _confirm(tester, 71);
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.text('İkinci.'), findsNothing);
    expect(
      find.text('Sayfa zaten kaldırılmış. Liste yenilendi.'),
      findsOneWidget,
    );
    expect(find.text('Sayfa silindi.'), findsNothing);
  });

  testWidgets('late completion after disposal is ignored', (tester) async {
    final store = _Store()..gate = Completer<void>();
    await _show(tester, store);
    await _confirm(tester, 71);
    await tester.tap(find.text('Sil'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    store.gate!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

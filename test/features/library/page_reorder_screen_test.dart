import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/document_contents_screen.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';

// Fake store: covers our UI and state handling. The SQL itself is covered by
// page_reorder_store_test.dart; real touch dragging needs manual testing.
class _Store extends DocumentStore {
  _Store(int pageCount)
    : stored = [
        for (var i = 0; i < pageCount; i++)
          DocumentPage(
            id: 70 + i,
            documentId: 7,
            position: i,
            text: 'Metin ${i + 1}.',
          ),
      ];

  final document = SavedDocument(
    id: 7,
    title: 'Kitabım',
    category: DocumentCategory.book,
    text: 'Metin 1.',
    createdAt: DateTime(2026),
  );
  List<DocumentPage> stored;
  final calls = <List<int>>[];
  Object? error;
  Completer<void>? gate;

  @override
  Future<SavedDocument?> getDocument(int id) async => document;

  @override
  Future<List<DocumentPage>> pages(int documentId) async => [...stored];

  @override
  Future<bool> reorderPages({
    required int documentId,
    required List<int> orderedPageIds,
  }) async {
    calls.add(orderedPageIds);
    await gate?.future;
    if (error != null) throw error!;
    stored = [
      for (var i = 0; i < orderedPageIds.length; i++)
        DocumentPage(
          id: orderedPageIds[i],
          documentId: 7,
          position: i,
          text: stored.firstWhere((p) => p.id == orderedPageIds[i]).text,
        ),
    ];
    return true;
  }
}

final _hintFinder = find.byKey(const ValueKey('page-reorder-hint'));

Future<void> _show(
  WidgetTester tester,
  _Store store, {
  VoidCallback? onUpdated,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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

Finder _handle(int number) => find.byKey(ValueKey('page-handle-$number'));

List<String> _visibleOrder() => [
  for (final element in find.byType(ListTile).evaluate())
    ((element.widget as ListTile).subtitle! as Text).data!,
];

Future<void> _dragHandle(WidgetTester tester, int number, double dy) async {
  await tester.drag(_handle(number), Offset(0, dy));
  await tester.pump();
}

void main() {
  testWidgets('hint and handles appear only with at least two pages', (
    tester,
  ) async {
    final one = _Store(1);
    await _show(tester, one);
    expect(_hintFinder, findsNothing);
    expect(find.byIcon(Icons.drag_handle), findsNothing);

    await tester.pumpWidget(const SizedBox());
    final two = _Store(2);
    await _show(tester, two);
    expect(_hintFinder, findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
    // The existing menu stays next to the handle.
    expect(find.byKey(const ValueKey('page-menu-70')), findsOneWidget);
  });

  testWidgets('handle has a Turkish tooltip and semantics label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _show(tester, _Store(2));

    expect(find.byTooltip('Sırayı değiştirmek için sürükle'), findsNWidgets(2));
    for (final number in [1, 2]) {
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'Sayfa $number sırasını değiştir' &&
              w.properties.hint == 'Sürüklemek için basılı tutup taşı',
        ),
        findsOneWidget,
      );
    }
    semantics.dispose();
  });

  testWidgets('dragging the handle inserts the page and renumbers', (
    tester,
  ) async {
    final store = _Store(4);
    var updates = 0;
    await _show(tester, store, onUpdated: () => updates++);

    await _dragHandle(tester, 1, 220); // first page two places down
    await tester.pumpAndSettle();

    expect(store.calls, [
      [71, 72, 70, 73],
    ]);
    expect(updates, 1);
    // Metin 1 is now the third page: insertion, not a swap.
    final moved = find.byKey(const ValueKey('page-70'));
    expect(
      find.descendant(of: moved, matching: find.text('Sayfa 3')),
      findsOneWidget,
    );
    final second = find.byKey(const ValueKey('page-72'));
    expect(
      find.descendant(of: second, matching: find.text('Sayfa 2')),
      findsOneWidget,
    );
  });

  testWidgets('long press on the page body does not reorder pages', (
    tester,
  ) async {
    final store = _Store(3);
    await _show(tester, store);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Metin 3.')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -300));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(store.calls, isEmpty);

    final first = tester.getTopLeft(find.byKey(const ValueKey('page-70')));
    final second = tester.getTopLeft(find.byKey(const ValueKey('page-71')));
    final third = tester.getTopLeft(find.byKey(const ValueKey('page-72')));

    expect(first.dy, lessThan(second.dy));
    expect(second.dy, lessThan(third.dy));
  });

  testWidgets('a plain tap still opens the page', (tester) async {
    final store = _Store(2);
    await _show(tester, store);
    await tester.tap(find.text('Metin 2.'));
    await tester.pumpAndSettle();
    expect(find.byType(SavedDocumentScreen), findsOneWidget);
    expect(store.calls, isEmpty);
  });

  testWidgets('dropping on the same position does not write', (tester) async {
    final store = _Store(3);
    await _show(tester, store);
    await _dragHandle(tester, 2, 5);
    await tester.pumpAndSettle();
    expect(store.calls, isEmpty);
  });

  testWidgets('failure restores the previous order with a Turkish message', (
    tester,
  ) async {
    final store = _Store(3)..error = Exception('disk');
    var updates = 0;
    await _show(tester, store, onUpdated: () => updates++);

    await _dragHandle(tester, 1, 250);
    await tester.pumpAndSettle();

    expect(store.calls, hasLength(1));
    expect(updates, 0);
    expect(
      find.text('Sayfa sırası kaydedilemedi. Önceki sıra geri yüklendi.'),
      findsOneWidget,
    );
    final first = find.byKey(const ValueKey('page-70'));
    expect(
      find.descendant(of: first, matching: find.text('Sayfa 1')),
      findsOneWidget,
    );
    expect(find.text('Sıra kaydediliyor…'), findsNothing);
  });

  testWidgets('while saving: status shown, other actions and back blocked', (
    tester,
  ) async {
    final store = _Store(3)..gate = Completer();
    await _show(tester, store);

    await _dragHandle(tester, 1, 250);
    await tester.pump();
    expect(find.text('Sıra kaydediliyor…'), findsOneWidget);

    // Page open, add, content options, page menu, tap are all disabled.
    await tester.tap(find.text('Metin 2.'), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(DocumentContentsScreen), findsOneWidget);
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
            find.byKey(const ValueKey('page-menu-71')),
          )
          .enabled,
      isFalse,
    );

    // A second reorder is refused.
    await _dragHandle(tester, 3, -100);
    expect(store.calls, hasLength(1));

    // System back is blocked.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(DocumentContentsScreen), findsOneWidget);

    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Sıra kaydediliyor…'), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('add-page')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('a result arriving after dispose is ignored', (tester) async {
    final store = _Store(3)..gate = Completer();
    await _show(tester, store);
    await _dragHandle(tester, 1, 250);
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    store.gate!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reopening loads the saved order', (tester) async {
    final store = _Store(3);
    await _show(tester, store);
    await _dragHandle(tester, 1, 250);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await _show(tester, store);

    final tiles = _visibleOrder();
    expect(tiles.first, 'Metin 2.');
    expect(tiles.last, 'Metin 1.');
  });
}

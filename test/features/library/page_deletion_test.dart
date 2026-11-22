import 'dart:async';

import 'fake_reading_positions.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/document_contents_screen.dart';

class _Store extends DocumentStore with FakeReadingPositions {
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
  final batchCalls = <Set<int>>[];

  @override
  Future<SavedDocument?> getDocument(int id) async => document;
  @override
  Future<List<DocumentPage>> pages(int documentId) async => [...stored];
  @override
  Future<int> deletePages({
    required int documentId,
    required Set<int> pageIds,
  }) async {
    batchCalls.add(Set.of(pageIds));
    await gate?.future;
    if (error != null) throw error!;
    stored = stored.where((page) => !pageIds.contains(page.id)).toList();
    if (pageIds.contains(positions[documentId]?.pageId)) {
      positions.remove(documentId);
    }
    if (pageIds.contains(bookmarks[documentId]?.pageId)) {
      bookmarks.remove(documentId);
    }
    return pageIds.length;
  }

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

Finder _iconButton(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

void main() {
  testWidgets(
    'page confirmation is usable with large text on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = _Store();
      await _show(tester, store);
      await tester.ensureVisible(find.byKey(const ValueKey('page-70')));
      await tester.longPress(find.byKey(const ValueKey('page-70')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tümünü seç'));
      await tester.tap(find.byTooltip('Seçilenleri sil'));
      await tester.pumpAndSettle();
      expect(find.text('3 sayfa silinsin mi?'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(store.batchCalls, isEmpty);
    },
  );

  testWidgets('page selection disables dragging, supports cancel and back', (
    tester,
  ) async {
    final store = _Store();
    await _show(tester, store);
    await tester.longPress(find.byKey(const ValueKey('page-71')));
    await tester.pumpAndSettle();
    expect(find.text('1 seçili'), findsOneWidget);
    expect(find.byType(ReorderableDragStartListener), findsNothing);
    await tester.tap(find.byKey(const ValueKey('page-70')));
    await tester.pumpAndSettle();
    expect(find.text('2 seçili'), findsOneWidget);
    await tester.tap(find.byTooltip('Seçilenleri sil'));
    await tester.pumpAndSettle();
    expect(find.text('2 sayfa silinsin mi?'), findsOneWidget);
    expect(
      find.text('Seçili sayfalar silinecek. Bu işlem geri alınamaz.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(store.batchCalls, isEmpty);
    expect(find.text('2 seçili'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Kitabım'), findsOneWidget);
    expect(find.byType(ReorderableDragStartListener), findsWidgets);
  });

  testWidgets('page batch failure preserves selection and retry deletes all', (
    tester,
  ) async {
    final store = _Store()..error = StateError('disk');
    await _show(tester, store);
    await tester.longPress(find.byKey(const ValueKey('page-70')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tümünü seç'));
    await tester.tap(find.byTooltip('Seçilenleri sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await tester.pumpAndSettle();
    expect(find.text('3 seçili'), findsOneWidget);
    expect(store.stored, hasLength(3));
    expect(
      find.text('Sayfalar silinemedi. Seçim korundu, tekrar deneyebilirsin.'),
      findsOneWidget,
    );
    store.error = null;
    store.gate = Completer<void>();
    await tester.tap(find.byTooltip('Seçilenleri sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await tester.pump();
    expect(
      tester.widget<IconButton>(_iconButton('Seçilenleri sil')).onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('3 seçili'), findsOneWidget);
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(store.batchCalls, [
      {70, 71, 72},
      {70, 71, 72},
    ]);
    expect(find.text('3 sayfa silindi.'), findsOneWidget);
    expect(find.textContaining('Henüz sayfa yok.'), findsOneWidget);
  });

  testWidgets('single selected page uses singular confirmation and message', (
    tester,
  ) async {
    final store = _Store();
    await _show(tester, store);
    await tester.longPress(find.byKey(const ValueKey('page-71')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Seçilenleri sil'));
    await tester.pumpAndSettle();
    expect(find.text('Sayfa silinsin mi?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await tester.pumpAndSettle();
    expect(find.text('Sayfa silindi.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('page-72')),
        matching: find.text('Sayfa 2'),
      ),
      findsOneWidget,
    );
  });

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
      tester
          .widget<ListTile>(
            find.descendant(
              of: find.byKey(const ValueKey('page-70')),
              matching: find.byType(ListTile),
            ),
          )
          .onTap,
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

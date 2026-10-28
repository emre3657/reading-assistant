import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/document_contents_screen.dart';
import 'package:reading_assistant/features/library/presentation/document_details_dialog.dart';
import 'package:reading_assistant/features/library/presentation/library_screen.dart';

class _DetailsStore extends DocumentStore {
  SavedDocument document = SavedDocument(
    id: 7,
    title: 'Başlık',
    category: DocumentCategory.note,
    text: 'İlk sayfa.',
    createdAt: DateTime(2026, 1, 1),
  );
  int calls = 0;
  int listCalls = 0;
  bool result = true;
  Object? error;
  Completer<void>? gate;

  @override
  Future<bool> updateDetails({
    required int id,
    required String title,
    required DocumentCategory category,
  }) async {
    calls++;
    await gate?.future;
    if (error != null) throw error!;
    if (!result) return false;
    document = SavedDocument(
      id: id,
      title: title,
      category: category,
      text: document.text,
      createdAt: document.createdAt,
    );
    return true;
  }

  @override
  Future<List<SavedDocument>> list() async {
    listCalls++;
    return [document];
  }

  @override
  Future<SavedDocument?> getDocument(int id) async => document;

  @override
  Future<List<DocumentPage>> pages(int documentId) async => const [
    DocumentPage(id: 70, documentId: 7, position: 0, text: 'İlk sayfa.'),
    DocumentPage(id: 71, documentId: 7, position: 1, text: 'İkinci sayfa.'),
  ];
}

final _title = find.byKey(const ValueKey('document-details-title'));
final _save = find.byKey(const ValueKey('save-document-details'));

Future<void> _showDialog(WidgetTester tester, _DetailsStore store) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () {
                showDocumentDetailsDialog(
                  context: context,
                  document: store.document,
                  store: store,
                );
              },
              child: const Text('Aç'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Aç'));
  await tester.pumpAndSettle();
}

Future<void> _saveTitle(WidgetTester tester, String text) async {
  await tester.enterText(_title, text);
  await tester.tap(_save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dialog updates trimmed title and category, never page text', (
    tester,
  ) async {
    final store = _DetailsStore();
    final date = store.document.createdAt;
    await _showDialog(tester, store);
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.enterText(_title, '  Yeni başlık  ');
    await tester.tap(find.byType(DropdownButtonFormField<DocumentCategory>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitap').last);
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(store.calls, 1);
    expect(store.document.title, 'Yeni başlık');
    expect(store.document.category, DocumentCategory.book);
    expect(store.document.text, 'İlk sayfa.');
    expect(store.document.createdAt, date);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('blank title is rejected; unchanged save does not write', (
    tester,
  ) async {
    final store = _DetailsStore();
    await _showDialog(tester, store);
    await _saveTitle(tester, '   ');
    expect(find.text('Bir başlık yaz.'), findsOneWidget);
    expect(store.calls, 0);
    await _saveTitle(tester, 'Başlık');
    expect(store.calls, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('cancel leaves details untouched', (tester) async {
    final store = _DetailsStore();
    await _showDialog(tester, store);
    await tester.enterText(_title, 'Taslak');
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(store.calls, 0);
    expect(store.document.title, 'Başlık');
  });

  testWidgets('failure preserves draft and supports retry', (tester) async {
    final store = _DetailsStore()..error = StateError('disk');
    await _showDialog(tester, store);
    await _saveTitle(tester, 'Yeni');
    expect(find.textContaining('Bilgiler kaydedilemedi.'), findsOneWidget);
    expect(tester.widget<TextFormField>(_title).controller!.text, 'Yeni');
    store.error = null;
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(store.calls, 2);
    expect(store.document.title, 'Yeni');
  });

  testWidgets('missing content stays open without success', (tester) async {
    final store = _DetailsStore()..result = false;
    await _showDialog(tester, store);
    await _saveTitle(tester, 'Yeni');
    expect(find.textContaining('İçerik bulunamadı.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(store.document.title, 'Başlık');
  });

  testWidgets('pending save blocks cancel, back and duplicate save', (
    tester,
  ) async {
    final store = _DetailsStore()..gate = Completer<void>();
    await _showDialog(tester, store);
    await tester.enterText(_title, 'Yeni');
    await tester.tap(_save);
    await tester.pump();
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
    final cancel = find.widgetWithText(TextButton, 'Vazgeç');
    expect(tester.widget<TextButton>(cancel).onPressed, isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(store.calls, 1);
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('late result after dispose is ignored', (tester) async {
    final store = _DetailsStore()..gate = Completer<void>();
    await _showDialog(tester, store);
    await tester.enterText(_title, 'Yeni');
    await tester.tap(_save);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    store.gate!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('library menu edits details and reloads list', (tester) async {
    final store = _DetailsStore();
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('document-menu-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();
    await _saveTitle(tester, 'Güncel');
    expect(find.text('Güncel'), findsOneWidget);
    expect(store.listCalls, 2);
  });

  testWidgets('contents menu refreshes header without losing pages', (
    tester,
  ) async {
    final store = _DetailsStore();
    var updates = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentContentsScreen(
          document: store.document,
          store: store,
          onUpdated: () => updates++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('content-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();
    await _saveTitle(tester, 'Güncel');
    expect(find.text('Güncel'), findsOneWidget);
    expect(find.text('Sayfa 1'), findsOneWidget);
    expect(find.text('Sayfa 2'), findsOneWidget);
    expect(updates, 1);
  });

  testWidgets('dialog scrolls on narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDocumentDetailsDialog(
                context: context,
                document: _DetailsStore().document,
                store: _DetailsStore(),
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

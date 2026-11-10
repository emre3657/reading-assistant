import 'dart:async';

import 'fake_reading_positions.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/features/image_import/services/image_picker_service.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/reading_position.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/add_page_screen.dart';
import 'package:reading_assistant/features/library/presentation/document_contents_screen.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';

import '../listening/fake_speech_service.dart';

// Page-management tests must never wait for native Android picker recovery.
class _NoPicker extends ImagePickerService {
  @override
  bool get canRecoverLostImage => false;

  @override
  Future<XFile?> pickFromGallery() async => null;
}

class _PageStore extends DocumentStore with FakeReadingPositions {
  SavedDocument document = SavedDocument(
    id: 7,
    title: 'Deneme',
    category: DocumentCategory.lesson,
    text: 'İlk sayfa.',
    createdAt: DateTime(2026, 1, 1),
  );
  List<DocumentPage> storedPages = const [
    DocumentPage(id: 70, documentId: 7, position: 0, text: 'İlk sayfa.'),
    DocumentPage(id: 71, documentId: 7, position: 1, text: 'İkinci sayfa.'),
  ];
  int appendCalls = 0;
  int? appendedDocumentId;
  String? appendedText;
  Object? appendError;
  Object? loadError;
  Completer<void>? appendGate;

  @override
  Future<SavedDocument?> getDocument(int id) async {
    if (loadError != null) throw loadError!;
    return id == document.id ? document : null;
  }

  @override
  Future<List<DocumentPage>> pages(int documentId) async {
    if (loadError != null) throw loadError!;
    return List<DocumentPage>.of(storedPages);
  }

  @override
  Future<DocumentPage> appendPage({
    required int documentId,
    required String text,
  }) async {
    appendCalls++;
    appendedDocumentId = documentId;
    appendedText = text;
    await appendGate?.future;
    if (appendError != null) throw appendError!;
    final page = DocumentPage(
      id: 100 + appendCalls,
      documentId: documentId,
      position: storedPages.length,
      text: text,
    );
    storedPages = [...storedPages, page];
    return page;
  }

  @override
  Future<bool> updatePageText({
    required int documentId,
    required int pageId,
    required String text,
  }) async {
    final index = storedPages.indexWhere(
      (page) => page.documentId == documentId && page.id == pageId,
    );
    if (index < 0) return false;
    final old = storedPages[index];
    storedPages = [...storedPages]
      ..[index] = DocumentPage(
        id: old.id,
        documentId: old.documentId,
        position: old.position,
        text: text,
      );
    document = SavedDocument(
      id: document.id,
      title: document.title,
      category: document.category,
      text: storedPages.first.text,
      createdAt: document.createdAt,
    );
    return true;
  }
}

Future<void> _show(
  WidgetTester tester,
  _PageStore store, {
  FakeSpeechService? speech,
  VoidCallback? onUpdated,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: DocumentContentsScreen(
        document: store.document,
        pickerService: _NoPicker(),
        store: store,
        speechService: speech ?? FakeSpeechService(),
        onUpdated: onUpdated,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _add(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('add-page')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Metin yaz veya yapıştır'));
  await tester.pumpAndSettle();
}

final _newText = find.byKey(const ValueKey('new-page-text'));
final _savePage = find.byKey(const ValueKey('save-page'));

void main() {
  testWidgets('resume opens the saved page without speaking until requested', (
    tester,
  ) async {
    final store = _PageStore();
    store.storedPages = const [
      DocumentPage(id: 71, documentId: 7, position: 0, text: 'Bir. İki. Üç.'),
      DocumentPage(id: 70, documentId: 7, position: 5, text: 'Diğer.'),
    ];
    store.positions[7] = const ReadingPosition(
      pageId: 71,
      sentenceIndex: 1,
      pageText: 'Bir. İki. Üç.',
    );
    final speech = FakeSpeechService();
    await _show(tester, store, speech: speech);
    await tester.tap(find.text('Kaldığın yerden devam et'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SavedDocumentScreen>(find.byType(SavedDocumentScreen))
          .pageId,
      71,
    );
    expect(speech.spoken, isEmpty);
    await tester.tap(find.text('Sesli oku'));
    await tester.pumpAndSettle();
    expect(speech.spoken.single, 'İki. ');
    expect(store.positions[7]?.sentenceIndex, 1);
    await tester.tap(find.text('Duraklat'));
    await tester.pumpAndSettle();
    expect(store.positions[7]?.sentenceIndex, 1);
    await tester.tap(find.text('Durdur'));
    await tester.pumpAndSettle();
    expect(store.positions[7]?.sentenceIndex, 1);
    await tester.tap(find.text('Sesli oku'));
    await tester.pumpAndSettle();
    expect(speech.spoken.last, 'Bir. ');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Kaldığın yerden devam et'), findsOneWidget);
  });

  testWidgets(
    'normal page opening starts at the beginning; invalid index falls back',
    (tester) async {
      final store = _PageStore();
      store.storedPages = const [
        DocumentPage(id: 70, documentId: 7, position: 0, text: 'Bir. İki.'),
        DocumentPage(id: 71, documentId: 7, position: 1, text: 'Diğer.'),
      ];
      store.positions[7] = const ReadingPosition(
        pageId: 70,
        sentenceIndex: 99,
        pageText: 'Bir. İki.',
      );
      final speech = FakeSpeechService();
      await _show(tester, store, speech: speech);
      await tester.tap(find.text('Kaldığın yerden devam et'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sesli oku'));
      await tester.pumpAndSettle();
      expect(speech.spoken.last, 'Bir. ');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      store.positions[7] = const ReadingPosition(
        pageId: 70,
        sentenceIndex: 1,
        pageText: 'Bir. İki.',
      );
      await tester.tap(find.byKey(const ValueKey('page-70')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sesli oku'));
      await tester.pumpAndSettle();
      expect(speech.spoken.last, 'Bir. ');
    },
  );

  testWidgets('opening and changing pages do not alter the saved position', (
    tester,
  ) async {
    final store = _PageStore();
    store.positions[7] = const ReadingPosition(
      pageId: 71,
      sentenceIndex: 0,
      pageText: 'İkinci sayfa.',
    );
    await _show(tester, store);
    await tester.tap(find.byKey(const ValueKey('page-70')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('next-page')));
    await tester.pumpAndSettle();
    expect(store.positions[7]?.pageId, 71);
    expect(store.positionWrites, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Kaldığın yerden devam et'), findsOneWidget);
  });

  testWidgets(
    'resume option is accessible with large text on a narrow screen',
    (tester) async {
      final store = _PageStore();
      store.positions[7] = const ReadingPosition(
        pageId: 71,
        sentenceIndex: 0,
        pageText: 'İkinci sayfa.',
      );
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _show(tester, store);
      tester.view.physicalSize = const Size(320, 560);
      await tester.pumpAndSettle();
      final resume = find.text('Kaldığın yerden devam et');
      expect(tester.takeException(), isNull);
      expect(resume.hitTestable(), findsOneWidget);
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(find.byType(SavedDocumentScreen), findsOneWidget);
    },
  );

  testWidgets(
    'position write failures do not interrupt speech or repeat notices',
    (tester) async {
      final store = _PageStore()..positionSaveError = StateError('db');
      store.storedPages = const [
        DocumentPage(id: 70, documentId: 7, position: 0, text: 'Bir. İki.'),
      ];
      final speech = FakeSpeechService();
      await _show(tester, store, speech: speech);
      await tester.tap(find.byKey(const ValueKey('page-70')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sesli oku'));
      await tester.pumpAndSettle();
      expect(speech.isSpeaking, isTrue);
      expect(find.textContaining('Okuma konumu kaydedilemedi'), findsOneWidget);
      speech.finishCurrent();
      await tester.pumpAndSettle();
      expect(speech.spoken.last, 'İki.');
      expect(store.positionWrites, 2);
      expect(speech.isSpeaking, isTrue);
    },
  );

  testWidgets('position load failure leaves normal page opening available', (
    tester,
  ) async {
    final store = _PageStore()..positionLoadError = StateError('db');
    await _show(tester, store);
    expect(find.textContaining('Okuma konumu yüklenemedi'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('page-70')));
    await tester.pumpAndSettle();
    expect(find.byType(SavedDocumentScreen), findsOneWidget);
  });

  testWidgets('lists pages for every category', (tester) async {
    for (final category in DocumentCategory.values) {
      final store = _PageStore();
      store.document = SavedDocument(
        id: 7,
        title: 'Deneme',
        category: category,
        text: 'İlk sayfa.',
        createdAt: DateTime(2026, 1, 1),
      );
      await _show(tester, store);
      expect(find.text('Sayfa 1'), findsOneWidget);
      expect(find.text('Sayfa 2'), findsOneWidget);
      expect(find.text('${category.label} · 2 sayfa'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('opens and speaks the selected page', (tester) async {
    final store = _PageStore();
    final speech = FakeSpeechService();
    await _show(tester, store, speech: speech);
    await tester.tap(find.byKey(const ValueKey('page-71')));
    await tester.pumpAndSettle();
    final reader = tester.widget<SavedDocumentScreen>(
      find.byType(SavedDocumentScreen),
    );
    expect(reader.pageId, 71);
    expect(reader.document.text, 'İkinci sayfa.');
    await tester.tap(find.text('Sesli oku'));
    await tester.pump();
    await tester.pump();
    expect(speech.spoken.single, 'İkinci sayfa.');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(speech.isSpeaking, isFalse);
  });

  testWidgets('appends under the same content and refreshes page list', (
    tester,
  ) async {
    final store = _PageStore();
    var updates = 0;
    await _show(tester, store, onUpdated: () => updates++);
    await _add(tester);
    await tester.enterText(_newText, 'Üçüncü\n\nsayfa.');
    await tester.tap(_savePage);
    await tester.pumpAndSettle();
    expect(store.appendedDocumentId, 7);
    expect(store.appendedText, 'Üçüncü\n\nsayfa.');
    expect(store.appendCalls, 1);
    expect(updates, 1);
    expect(find.text('Sayfa 3'), findsOneWidget);
    expect(find.byType(AddPageScreen), findsNothing);
  });

  testWidgets('empty page is rejected', (tester) async {
    final store = _PageStore();
    await _show(tester, store);
    await _add(tester);
    await tester.enterText(_newText, ' \n ');
    await tester.tap(_savePage);
    await tester.pumpAndSettle();
    expect(find.text('Sayfa metni boş olamaz.'), findsOneWidget);
    expect(store.appendCalls, 0);
  });

  testWidgets('failed append keeps the draft and permits retry', (
    tester,
  ) async {
    final store = _PageStore()..appendError = StateError('disk');
    await _show(tester, store);
    await _add(tester);
    await tester.enterText(_newText, 'Korunan taslak.');
    await tester.tap(_savePage);
    await tester.pumpAndSettle();
    expect(find.textContaining('Sayfa eklenemedi'), findsOneWidget);
    expect(
      tester.widget<TextField>(_newText).controller!.text,
      'Korunan taslak.',
    );
    store.appendError = null;
    await tester.tap(_savePage);
    await tester.pumpAndSettle();
    expect(store.appendCalls, 2);
    expect(store.storedPages.last.text, 'Korunan taslak.');
  });

  testWidgets('continue editing and discard keep existing pages unchanged', (
    tester,
  ) async {
    final store = _PageStore();
    await _show(tester, store);
    await _add(tester);
    await tester.enterText(_newText, 'Taslak.');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Düzenlemeye devam et'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_newText).controller!.text, 'Taslak.');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydetmeden çık'));
    await tester.pumpAndSettle();
    expect(find.byType(AddPageScreen), findsNothing);
    expect(store.appendCalls, 0);
    expect(store.storedPages, hasLength(2));
  });

  testWidgets('save and exit adds the draft once', (tester) async {
    final store = _PageStore();
    await _show(tester, store);
    await _add(tester);
    await tester.enterText(_newText, 'Çıkışta kaydet.');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet ve çık'));
    await tester.pumpAndSettle();
    expect(store.appendCalls, 1);
    expect(find.text('Sayfa 3'), findsOneWidget);
  });

  testWidgets('save pending blocks duplicate save and back', (tester) async {
    final gate = Completer<void>();
    final store = _PageStore()..appendGate = gate;
    await _show(tester, store);
    await _add(tester);
    await tester.enterText(_newText, 'Taslak.');
    await tester.tap(_savePage);
    await tester.pump();
    expect(tester.widget<TextButton>(_savePage).onPressed, isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AddPageScreen), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(store.appendCalls, 1);
  });

  testWidgets('editing page two leaves page one intact', (tester) async {
    final store = _PageStore();
    await _show(tester, store);
    await tester.tap(find.byKey(const ValueKey('page-71')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('document-text')),
      'İkinci değişti.',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('save-document')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('save-document')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(store.storedPages.first.text, 'İlk sayfa.');
    expect(store.storedPages.last.text, 'İkinci değişti.');
    expect(find.text('İkinci değişti.'), findsOneWidget);
  });

  testWidgets('load failure can be retried', (tester) async {
    final store = _PageStore()..loadError = StateError('disk');
    await _show(tester, store);
    expect(find.textContaining('Sayfalar yüklenemedi'), findsOneWidget);
    store.loadError = null;
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    expect(find.text('Sayfa 1'), findsOneWidget);
  });
}

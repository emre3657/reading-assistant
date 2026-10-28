import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/library_screen.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';

import '../listening/fake_speech_service.dart';

// Fake store and fake speech engine: these tests cover our own UI and state
// handling. The real SQLite file and the real TTS engine are not exercised.
class FakeDocumentStore extends DocumentStore {
  FakeDocumentStore(this.documents);

  List<SavedDocument> documents;
  bool updateResult = true;
  Object? updateError;
  Completer<void>? updateGate;

  final updates =
      <({int id, String title, DocumentCategory category, String text})>[];
  int listCalls = 0;

  @override
  Future<bool> update({
    required int id,
    required String title,
    required DocumentCategory category,
    required String text,
  }) async {
    updates.add((id: id, title: title, category: category, text: text));
    await updateGate?.future;
    if (updateError != null) throw updateError!;
    if (!updateResult) return false;

    documents = [
      for (final d in documents)
        if (d.id == id)
          SavedDocument(
            id: id,
            title: title,
            category: category,
            text: text,
            createdAt: d.createdAt,
          )
        else
          d,
    ];
    return true;
  }

  @override
  Future<SavedDocument?> getDocument(int id) async {
    for (final document in documents) {
      if (document.id == id) return document;
    }
    return null;
  }

  @override
  Future<List<DocumentPage>> pages(int documentId) async {
    final document = await getDocument(documentId);
    return document == null
        ? []
        : [
            DocumentPage(
              id: documentId * 100,
              documentId: documentId,
              position: 0,
              text: document.text,
            ),
          ];
  }

  @override
  Future<bool> updatePageText({
    required int documentId,
    required int pageId,
    required String text,
  }) async {
    final document = (await getDocument(documentId))!;
    return update(
      id: documentId,
      title: document.title,
      category: document.category,
      text: text,
    );
  }

  @override
  Future<List<SavedDocument>> list() async {
    listCalls++;
    return documents;
  }
}

final _created = DateTime(2024, 1, 2);

SavedDocument _doc({
  int id = 7,
  String title = 'Başlık',
  DocumentCategory category = DocumentCategory.note,
  String text = 'Birinci cümle. İkinci cümle. Üçüncü cümle.',
}) => SavedDocument(
  id: id,
  title: title,
  category: category,
  text: text,
  createdAt: _created,
);

const _initialText = 'Birinci cümle. İkinci cümle. Üçüncü cümle.';

final _panel = find.byKey(const ValueKey('listening-panel'));
Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);
final _titleField = find.byKey(const ValueKey('document-title'));
final _textField = find.byKey(const ValueKey('document-text'));
final _editButton = find.byIcon(Icons.edit_outlined);
const _discardTitle = 'Kaydedilmemiş değişiklikler var';

Future<void> _show(
  WidgetTester tester,
  FakeDocumentStore store,
  FakeSpeechService speech, {
  VoidCallback? onUpdated,
  Size size = const Size(800, 1600),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(tester.view.resetViewInsets);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => SavedDocumentScreen(
                    document: store.documents.first,
                    store: store,
                    speechService: speech,
                    onUpdated: onUpdated,
                  ),
                ),
              ),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle();
}

Future<void> _enterEdit(WidgetTester tester) async {
  await tester.tap(_editButton);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(_button('Kaydet'));
  await tester.pump();
  await tester.pump();
}

Future<void> _startReading(WidgetTester tester) async {
  await tester.tap(_button('Sesli oku'));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('reading mode', () {
    testWidgets('opens in reading mode with the saved text', (tester) async {
      final store = FakeDocumentStore([_doc()]);
      await _show(tester, store, FakeSpeechService());

      expect(find.text(_initialText), findsOneWidget);
      expect(_titleField, findsNothing);
      expect(_panel, findsOneWidget);
    });

    testWidgets('keeps category alignment: book justified, others start', (
      tester,
    ) async {
      final book = FakeDocumentStore([_doc(category: DocumentCategory.book)]);
      await _show(tester, book, FakeSpeechService());
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).textAlign,
        TextAlign.justify,
      );

      await tester.pumpWidget(const SizedBox());
      final note = FakeDocumentStore([_doc()]);
      await _show(tester, note, FakeSpeechService());
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).textAlign,
        TextAlign.start,
      );
    });

    testWidgets('reads the displayed saved text with the shared controls', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      await _show(tester, FakeDocumentStore([_doc()]), speech);

      await _startReading(tester);
      expect(speech.spoken.first, contains('Birinci cümle.'));
      expect(find.text('Cümle 1 / 3'), findsOneWidget);

      await tester.tap(_button('Duraklat'));
      await tester.pump();
      await tester.pump();
      expect(_button('Devam et'), findsOneWidget);

      await tester.tap(find.text('Diğer kontroller'));
      await tester.pump();
      await tester.tap(_button('Sonraki cümle'));
      await tester.pump();
      expect(find.text('Cümle 2 / 3'), findsOneWidget);
    });
  });

  group('listening and editing lock each other', () {
    testWidgets('edit is disabled while reading and while paused', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      await _show(tester, FakeDocumentStore([_doc()]), speech);

      await _startReading(tester);

      IconButton edit() => tester.widget<IconButton>(
        find.ancestor(of: _editButton, matching: find.byType(IconButton)),
      );
      expect(edit().onPressed, isNull);
      expect(edit().tooltip, 'Düzenlemek için okumayı durdur');

      await tester.tap(_button('Duraklat'));
      await tester.pump();
      await tester.pump();
      expect(edit().onPressed, isNull);

      await tester.tap(_button('Durdur'));
      await tester.pump();
      await tester.pump();
      expect(edit().onPressed, isNotNull);
    });

    testWidgets('edit mode hides the panel and shows the form', (tester) async {
      await _show(tester, FakeDocumentStore([_doc()]), FakeSpeechService());
      await _enterEdit(tester);

      expect(_panel, findsNothing);
      expect(_titleField, findsNothing);
      expect(_textField, findsOneWidget);
      expect(
        find.byType(DropdownButtonFormField<DocumentCategory>),
        findsNothing,
      );
      expect(find.byType(TextFormField), findsOneWidget);
      final field = tester.widget<TextField>(
        find.descendant(of: _textField, matching: find.byType(TextField)),
      );
      expect(field.textAlign, TextAlign.start);
    });

    testWidgets('a stopped session does not carry its position to new text', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      await _show(tester, FakeDocumentStore([_doc()]), speech);

      await _startReading(tester);
      await tester.tap(find.text('Diğer kontroller'));
      await tester.pump();
      await tester.tap(_button('Sonraki cümle'));
      await tester.pump();
      await tester.tap(_button('Durdur'));
      await tester.pump();
      await tester.pump();

      await _enterEdit(tester);
      await _type(tester, _textField, 'Yeni metin. Başka cümle.');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      await _startReading(tester);
      expect(speech.spoken.last, contains('Yeni metin.'));
      expect(find.text('Cümle 1 / 2'), findsOneWidget);
    });
  });

  group('saving', () {
    testWidgets('updates page text without changing content details', (
      tester,
    ) async {
      final store = FakeDocumentStore([_doc(), _doc(id: 8, title: 'Diğer')]);
      var updated = 0;
      final speech = FakeSpeechService();
      await _show(tester, store, speech, onUpdated: () => updated++);
      await _enterEdit(tester);

      await _type(tester, _textField, 'Yeni metin.\n\nİkinci paragraf.');

      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(store.updates, hasLength(1));
      expect(store.updates.single.id, 7);
      expect(store.updates.single.title, 'Başlık');
      expect(store.updates.single.category, DocumentCategory.note);
      expect(store.updates.single.text, 'Yeni metin.\n\nİkinci paragraf.');
      expect(store.documents, hasLength(2));
      expect(store.documents.first.createdAt, _created);
      expect(updated, 1);

      expect(_titleField, findsNothing);
      expect(find.text('Başlık'), findsOneWidget);
      expect(find.text('Kayıt güncellendi.'), findsOneWidget);

      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).textAlign,
        TextAlign.start,
      );
      await _startReading(tester);
      expect(speech.spoken.first, contains('Yeni metin.'));
    });

    testWidgets('rejects whitespace-only page text', (tester) async {
      final store = FakeDocumentStore([_doc()]);
      await _show(tester, store, FakeSpeechService());
      await _enterEdit(tester);

      await _type(tester, _textField, ' \n  ');
      await _tapSave(tester);
      expect(find.text('Metin boş olamaz.'), findsOneWidget);

      expect(store.updates, isEmpty);
      expect(_titleField, findsNothing);
    });

    testWidgets('does not update when nothing changed', (tester) async {
      final store = FakeDocumentStore([_doc()]);
      var updated = 0;
      await _show(
        tester,
        store,
        FakeSpeechService(),
        onUpdated: () => updated++,
      );
      await _enterEdit(tester);
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(store.updates, isEmpty);
      expect(updated, 0);
      expect(_titleField, findsNothing);
      expect(find.text('Kayıt güncellendi.'), findsNothing);
    });

    testWidgets('a missing record is not reported as success', (tester) async {
      final store = FakeDocumentStore([_doc()])..updateResult = false;
      var updated = 0;
      await _show(
        tester,
        store,
        FakeSpeechService(),
        onUpdated: () => updated++,
      );
      await _enterEdit(tester);
      await _type(tester, _textField, 'Değişen metin.');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('Kayıt bulunamadı'), findsOneWidget);
      expect(find.text('Kayıt güncellendi.'), findsNothing);
      expect(updated, 0);
      expect(find.text('Değişen metin.'), findsOneWidget);
      expect(_textField, findsOneWidget);
    });

    testWidgets('keeps edits on error and succeeds on retry', (tester) async {
      final store = FakeDocumentStore([_doc()])
        ..updateError = Exception('disk');
      await _show(tester, store, FakeSpeechService());
      await _enterEdit(tester);
      await _type(tester, _textField, 'Korunan metin.');
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('Kayıt güncellenemedi'), findsOneWidget);
      expect(find.text('Korunan metin.'), findsOneWidget);
      expect(_button('Kaydet'), findsOneWidget);

      store.updateError = null;
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(store.updates, hasLength(2));
      expect(_titleField, findsNothing);
      expect(find.text('Kayıt güncellendi.'), findsOneWidget);
    });

    testWidgets('blocks double save and leaving while saving', (tester) async {
      final store = FakeDocumentStore([_doc()])..updateGate = Completer();
      await _show(tester, store, FakeSpeechService());
      await _enterEdit(tester);
      await _type(tester, _textField, 'Yeni.');

      await _tapSave(tester);
      expect(
        tester.widget<ButtonStyleButton>(_button('Kaydediliyor…')).onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(store.updates, hasLength(1));
      expect(find.text(_discardTitle), findsNothing);
      expect(_textField, findsOneWidget);

      store.updateGate!.complete();
      await tester.pumpAndSettle();
      expect(store.updates, hasLength(1));
      expect(_titleField, findsNothing);
    });

    testWidgets('a result arriving after dispose is ignored', (tester) async {
      final store = FakeDocumentStore([_doc()])..updateGate = Completer();
      var updated = 0;
      await _show(
        tester,
        store,
        FakeSpeechService(),
        onUpdated: () => updated++,
      );
      await _enterEdit(tester);
      await _type(tester, _textField, 'Yeni.');
      await _tapSave(tester);

      await tester.pumpWidget(const SizedBox());
      store.updateGate!.complete();
      await tester.pump();

      expect(updated, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('leaving with unsaved changes', () {
    testWidgets('system back without changes leaves directly', (tester) async {
      await _show(tester, FakeDocumentStore([_doc()]), FakeSpeechService());
      await _enterEdit(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SavedDocumentScreen), findsNothing);
    });

    testWidgets('continue editing preserves the draft', (tester) async {
      final store = FakeDocumentStore([_doc()]);
      await _show(tester, store, FakeSpeechService());
      await _enterEdit(tester);
      await _type(tester, _textField, 'Yarım kalan.');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(_discardTitle), findsOneWidget);
      await tester.tap(find.text('Düzenlemeye devam et'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(_textField).controller!.text,
        'Yarım kalan.',
      );
      expect(store.updates, isEmpty);
    });

    testWidgets('discard exits without updating', (tester) async {
      final store = FakeDocumentStore([_doc()]);
      await _show(tester, store, FakeSpeechService());
      await _enterEdit(tester);
      await _type(tester, _textField, 'Yarım kalan.');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydetmeden çık'));
      await tester.pumpAndSettle();
      expect(find.byType(SavedDocumentScreen), findsNothing);
      expect(store.updates, isEmpty);
      expect(store.documents.single.text, _initialText);
    });

    testWidgets('save and exit updates before leaving', (tester) async {
      final store = FakeDocumentStore([_doc()]);
      await _show(tester, store, FakeSpeechService());
      await _enterEdit(tester);
      await _type(tester, _textField, 'Yeni kayıt metni.');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet ve çık'));
      await tester.pumpAndSettle();
      expect(store.updates, hasLength(1));
      expect(store.documents.single.text, 'Yeni kayıt metni.');
      expect(find.byType(SavedDocumentScreen), findsNothing);
    });

    testWidgets('save and exit failure keeps the draft', (tester) async {
      final store = FakeDocumentStore([_doc()])
        ..updateError = Exception('disk');
      await _show(tester, store, FakeSpeechService());
      await _enterEdit(tester);
      await _type(tester, _textField, 'Korunan taslak.');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet ve çık'));
      await tester.pumpAndSettle();
      expect(find.byType(SavedDocumentScreen), findsOneWidget);
      expect(find.textContaining('Kayıt güncellenemedi'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(_textField).controller!.text,
        'Korunan taslak.',
      );
      store.updateError = null;
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(store.documents.single.text, 'Korunan taslak.');
    });

    testWidgets('save and exit validates before leaving', (tester) async {
      final store = FakeDocumentStore([_doc()]);
      await _show(tester, store, FakeSpeechService());
      await _enterEdit(tester);
      await _type(tester, _textField, ' ');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet ve çık'));
      await tester.pumpAndSettle();
      expect(find.text('Metin boş olamaz.'), findsOneWidget);
      expect(find.byType(SavedDocumentScreen), findsOneWidget);
      expect(store.updates, isEmpty);
    });

    testWidgets('repeated back presses leave one confirmation open', (
      tester,
    ) async {
      await _show(tester, FakeDocumentStore([_doc()]), FakeSpeechService());
      await _enterEdit(tester);
      await _type(tester, _textField, 'Yarım kalan.');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_discardTitle), findsOneWidget);
      await tester.tap(find.text('Düzenlemeye devam et'));
      await tester.pumpAndSettle();
    });

    testWidgets('app bar back uses the same confirmation', (tester) async {
      await _show(tester, FakeDocumentStore([_doc()]), FakeSpeechService());
      await _enterEdit(tester);
      await _type(tester, _textField, 'Taslak.');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(_discardTitle), findsOneWidget);
      await tester.tap(find.text('Düzenlemeye devam et'));
      await tester.pumpAndSettle();
    });

    testWidgets('normal back waits for speech stop before leaving', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      await _show(tester, FakeDocumentStore([_doc()]), speech);
      await _startReading(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SavedDocumentScreen), findsNothing);
      expect(speech.isSpeaking, isFalse);
      expect(speech.disposed, isFalse);
    });
  });

  group('lifecycle', () {
    testWidgets('background stops reading; inactive does not', (tester) async {
      final speech = FakeSpeechService();
      await _show(tester, FakeDocumentStore([_doc()]), speech);
      await _startReading(tester);
      expect(speech.isSpeaking, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(speech.stopCalls, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump();
      expect(speech.isSpeaking, isFalse);
      expect(speech.stopCalls, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    });

    testWidgets('leaving the screen stops reading; injected service is kept', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      await _show(tester, FakeDocumentStore([_doc()]), speech);
      await _startReading(tester);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(speech.isSpeaking, isFalse);
      expect(speech.disposed, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a late speech result after dispose changes nothing', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      await _show(tester, FakeDocumentStore([_doc()]), speech);
      await _startReading(tester);

      await tester.pumpWidget(const SizedBox());
      speech.finishCurrent();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('layout', () {
    testWidgets('narrow screen and large text do not overflow', (tester) async {
      final store = FakeDocumentStore([_doc()]);
      await _show(
        tester,
        store,
        FakeSpeechService(),
        size: const Size(320, 560),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Diğer kontroller'));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Diğer kontroller'));
      await tester.pump();
      await _enterEdit(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_button('Kaydet'));
      expect(_button('Kaydet'), findsOneWidget);
    });
  });

  group('library', () {
    Future<void> openLibrary(
      WidgetTester tester,
      FakeDocumentStore store,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(store: store, speechService: FakeSpeechService()),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openFirstPage(WidgetTester tester, String title) async {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sayfa 1'));
      await tester.pumpAndSettle();
    }

    Future<void> backToLibrary(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    testWidgets('refreshes after an update, not after a plain visit', (
      tester,
    ) async {
      final store = FakeDocumentStore([_doc()]);
      await openLibrary(tester, store);
      expect(store.listCalls, 1);
      await openFirstPage(tester, 'Başlık');
      await backToLibrary(tester);
      expect(store.listCalls, 1);
      await openFirstPage(tester, 'Başlık');
      await _enterEdit(tester);
      await _type(tester, _textField, 'Güncel metin.');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      await backToLibrary(tester);
      expect(store.listCalls, 2);
      expect(find.text('Başlık'), findsOneWidget);
      expect(store.documents.single.text, 'Güncel metin.');
    });

    testWidgets('a failed update does not refresh the list', (tester) async {
      final store = FakeDocumentStore([_doc()])..updateResult = false;
      await openLibrary(tester, store);
      await openFirstPage(tester, 'Başlık');
      await _enterEdit(tester);
      await _type(tester, _textField, 'Başka.');
      await _tapSave(tester);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydetmeden çık'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(store.listCalls, 1);
    });
  });
}

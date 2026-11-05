import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';

import '../listening/fake_speech_service.dart';

// Fake store and fake speech engine: these cover our own navigation and state
// handling, not the real SQLite file or the real TTS engine.
class _Store extends DocumentStore {
  _Store(this.pageList);

  List<DocumentPage> pageList;
  Object? pagesError;
  Completer<void>? pagesGate;
  Object? updateError;
  int pagesCalls = 0;
  final updates = <({int pageId, String text})>[];

  @override
  Future<List<DocumentPage>> pages(int documentId) async {
    pagesCalls++;
    await pagesGate?.future;
    if (pagesError != null) throw pagesError!;
    return pageList;
  }

  @override
  Future<bool> updatePageText({
    required int documentId,
    required int pageId,
    required String text,
  }) async {
    if (updateError != null) throw updateError!;
    updates.add((pageId: pageId, text: text));
    return true;
  }
}

DocumentPage _page(int id, int position, String text) =>
    DocumentPage(id: id, documentId: 7, position: position, text: text);

// Positions have gaps and ids are not in order on purpose.
List<DocumentPage> _threePages() => [
  _page(30, 0, 'Birinci sayfa metni.'),
  _page(10, 4, 'İkinci sayfa metni.'),
  _page(20, 9, 'Üçüncü sayfa metni.'),
];

final _previous = find.byKey(const ValueKey('previous-page'));
final _next = find.byKey(const ValueKey('next-page'));
final _textField = find.byKey(const ValueKey('document-text'));
final _editButton = find.byIcon(Icons.edit_outlined);

bool _enabled(Finder finder) =>
    (finder.evaluate().single.widget as ButtonStyleButton).onPressed != null;

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

Future<void> _show(
  WidgetTester tester,
  _Store store,
  FakeSpeechService speech, {
  int openIndex = 0,
  Size size = const Size(800, 1600),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final open = store.pageList[openIndex];
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => SavedDocumentScreen(
                  document: SavedDocument(
                    id: 7,
                    title: 'Başlık',
                    category: DocumentCategory.note,
                    text: open.text,
                    createdAt: DateTime(2024),
                  ),
                  pageId: open.id,
                  pageNumber: openIndex + 1,
                  store: store,
                  speechService: speech,
                ),
              ),
            ),
            child: const Text('aç'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('page navigation', () {
    testWidgets('moves by stored order, ignoring position gaps', (
      tester,
    ) async {
      final store = _Store(_threePages());
      await _show(tester, store, FakeSpeechService());

      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(_enabled(_previous), isFalse);
      expect(_enabled(_next), isTrue);

      await _tap(tester, _next);
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(find.text('İkinci sayfa metni.'), findsOneWidget);
      expect(_enabled(_previous), isTrue);

      await _tap(tester, _next);
      expect(find.text('Üçüncü sayfa metni.'), findsOneWidget);
      expect(_enabled(_next), isFalse);

      await _tap(tester, _previous);
      expect(find.text('İkinci sayfa metni.'), findsOneWidget);
      expect(store.updates, isEmpty);
    });

    testWidgets('single page shows only the indicator', (tester) async {
      final store = _Store([_page(1, 0, 'Tek sayfa.')]);
      await _show(tester, store, FakeSpeechService());

      expect(find.text('Sayfa 1 / 1'), findsOneWidget);
      expect(_previous, findsNothing);
      expect(_next, findsNothing);
    });

    testWidgets('stops active reading first and does not auto-read', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      final store = _Store(_threePages());
      await _show(tester, store, speech);

      await _tap(tester, _button('Diğer kontroller'));
      await _tap(tester, find.text('1.5×'));
      await tester.tap(_button('Sesli oku'));
      await tester.pump();
      await tester.pump();
      expect(speech.spoken, ['Birinci sayfa metni.']);

      await _tap(tester, _next);
      expect(speech.stopCalls, greaterThan(0));
      expect(speech.isSpeaking, isFalse);
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(speech.spoken, hasLength(1));

      await tester.tap(_button('Sesli oku'));
      await tester.pump();
      await tester.pump();
      expect(speech.spoken.last, 'İkinci sayfa metni.');
      expect(speech.spokenRates.last, speech.spokenRates.first);
      expect(speech.spokenRates.last, 1.5);
    });

    testWidgets('paused reading is ended before the move', (tester) async {
      final speech = FakeSpeechService();
      final store = _Store(_threePages());
      await _show(tester, store, speech);

      await tester.tap(_button('Sesli oku'));
      await tester.pump();
      await tester.pump();
      await _tap(tester, _button('Duraklat'));
      await _tap(tester, _next);

      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(_button('Sesli oku'), findsOneWidget);
    });

    testWidgets('a failed stop keeps the current page', (tester) async {
      final speech = FakeSpeechService(stopError: StateError('x'));
      final store = _Store(_threePages());
      await _show(tester, store, speech);

      await tester.tap(_button('Sesli oku'));
      await tester.pump();
      await tester.pump();
      await _tap(tester, _next);

      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(find.text('Birinci sayfa metni.'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('a load failure keeps the page and shows a message', (
      tester,
    ) async {
      final store = _Store(_threePages());
      await _show(tester, store, FakeSpeechService());
      store.pagesError = StateError('db');
      await _tap(tester, _next);

      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(find.text('Birinci sayfa metni.'), findsOneWidget);
      expect(
        find.text('Sayfa açılamadı. Mevcut sayfa korundu.'),
        findsOneWidget,
      );
    });

    testWidgets('a missing page shows an error instead of crashing', (
      tester,
    ) async {
      final store = _Store(_threePages());
      await _show(tester, store, FakeSpeechService());
      store.pageList = [_page(99, 0, 'Başka.')];
      await _tap(tester, _next);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Bu sayfa bulunamadı. Sayfa değiştirilemedi.'),
        findsOneWidget,
      );
      expect(find.text('Birinci sayfa metni.'), findsOneWidget);
    });

    testWidgets('rapid presses start a single transition', (tester) async {
      final store = _Store(_threePages());
      await _show(tester, store, FakeSpeechService());

      final before = store.pagesCalls;
      store.pagesGate = Completer<void>();
      await tester.tap(_next);
      await tester.pump();
      expect(_enabled(_next), isFalse);
      expect(_enabled(_previous), isFalse);
      await tester.tap(_next, warnIfMissed: false);
      await tester.pump();
      expect(_button('Sesli oku').evaluate(), isNotEmpty);
      expect(
        (_button('Sesli oku').evaluate().single.widget as ButtonStyleButton)
            .onPressed,
        isNull,
      );
      store.pagesGate!.complete();
      await tester.pumpAndSettle();

      expect(store.pagesCalls - before, 1);
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
    });

    testWidgets('a result arriving after the screen closed is ignored', (
      tester,
    ) async {
      final store = _Store(_threePages());
      await _show(tester, store, FakeSpeechService());

      store.pagesGate = Completer<void>();
      await tester.tap(_next);
      await tester.pump();
      tester.binding.handlePopRoute();
      await tester.pump();
      // Pop is refused while the move runs; finish it, then leave.
      store.pagesGate!.complete();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('resets the scroll position after a move', (tester) async {
      final long = List.filled(200, 'Uzun satır.').join('\n');
      final store = _Store([_page(1, 0, long), _page(2, 1, long)]);
      await _show(
        tester,
        store,
        FakeSpeechService(),
        size: const Size(400, 600),
      );

      ScrollableState scrollable() => tester.state<ScrollableState>(
        find
            .ancestor(
              of: find.byType(SelectableText),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      scrollable().position.jumpTo(300);
      await tester.pumpAndSettle();
      expect(scrollable().position.pixels, 300);
      await _tap(tester, _next);

      expect(scrollable().position.pixels, 0);
    });

    testWidgets('does not overflow on narrow screens with large text', (
      tester,
    ) async {
      final store = _Store(_threePages());
      await _show(
        tester,
        store,
        FakeSpeechService(),
        size: const Size(320, 560),
        textScale: 2,
        openIndex: 1,
      );

      expect(tester.takeException(), isNull);
      for (final finder in [_previous, _next]) {
        final size = tester.getSize(finder);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      await _tap(tester, _button('Diğer kontroller'));
      expect(tester.takeException(), isNull);
    });
  });

  group('page navigation with unsaved edits', () {
    Future<void> editAndMove(WidgetTester tester, _Store store) async {
      await _show(tester, store, FakeSpeechService());
      await _tap(tester, _editButton);
      await tester.enterText(_textField, 'Taslak metin.');
      await tester.pump();
      await _tap(tester, _next);
    }

    testWidgets('keep editing preserves page and draft', (tester) async {
      final store = _Store(_threePages());
      await editAndMove(tester, store);
      expect(find.text('Kaydet ve geç'), findsOneWidget);

      await _tap(tester, find.text('Düzenlemeye devam et'));
      expect(find.text('Taslak metin.'), findsOneWidget);
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(store.updates, isEmpty);
    });

    testWidgets('discard opens the target page without writing', (
      tester,
    ) async {
      final store = _Store(_threePages());
      await editAndMove(tester, store);

      await _tap(tester, find.text('Kaydetmeden geç'));
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(find.text('İkinci sayfa metni.'), findsOneWidget);
      expect(_textField, findsNothing);
      expect(store.updates, isEmpty);
    });

    testWidgets('save and go writes the current page then moves', (
      tester,
    ) async {
      final store = _Store(_threePages());
      await editAndMove(tester, store);

      await _tap(tester, find.text('Kaydet ve geç'));
      expect(store.updates, [(pageId: 30, text: 'Taslak metin.')]);
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(find.text('İkinci sayfa metni.'), findsOneWidget);
    });

    testWidgets('a save error keeps the page and the draft', (tester) async {
      final store = _Store(_threePages())..updateError = StateError('db');
      await editAndMove(tester, store);

      await _tap(tester, find.text('Kaydet ve geç'));
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(find.text('Taslak metin.'), findsOneWidget);
      expect(find.textContaining('Kayıt güncellenemedi'), findsOneWidget);
    });

    testWidgets('invalid text keeps the page and the draft', (tester) async {
      final store = _Store(_threePages());
      await _show(tester, store, FakeSpeechService());
      await _tap(tester, _editButton);
      await tester.enterText(_textField, '   ');
      await tester.pump();
      await _tap(tester, _next);
      await _tap(tester, find.text('Kaydet ve geç'));

      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(find.text('Metin boş olamaz.'), findsOneWidget);
      expect(store.updates, isEmpty);
    });
  });
}

import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'fake_reading_positions.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';

import '../listening/fake_preferences_store.dart';
import '../listening/fake_speech_service.dart';

// Fake store and fake speech engine: these cover our own navigation and state
// handling, not the real SQLite file or the real TTS engine.
class _Store extends DocumentStore with FakeReadingPositions {
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

bool _pageButtonEnabled(Finder finder) =>
    (finder.evaluate().single.widget as IconButton).onPressed != null;

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
    ReadingPreferencesScope(
      preferences: ReadingPreferences(store: FakePreferencesStore()),
      child: MaterialApp(
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
    ),
  );
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();

  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason: 'Dokunulacak kontrol görünür ve erişilebilir olmalı.',
  );

  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openGoToPage(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('go-to-page')));
}

Future<void> _goToPage(WidgetTester tester, String number) async {
  await _openGoToPage(tester);
  await tester.enterText(
    find.byKey(const ValueKey('page-number-input')),
    number,
  );
  await _tap(tester, find.text('Git'));
}

void main() {
  group('direct page navigation', () {
    testWidgets('uses stored order with gaps and reordered pages', (
      tester,
    ) async {
      final store = _Store([
        _page(20, 1, 'Üçüncü sayfa metni.'),
        _page(30, 4, 'Birinci sayfa metni.'),
        _page(10, 12, 'İkinci sayfa metni.'),
      ]);
      await _show(tester, store, FakeSpeechService(), openIndex: 1);
      await _goToPage(tester, '3');
      expect(find.text('İkinci sayfa metni.'), findsOneWidget);
      expect(find.text('Sayfa 3 / 3'), findsOneWidget);
      await _goToPage(tester, '1');
      expect(find.text('Üçüncü sayfa metni.'), findsOneWidget);
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(store.updates, isEmpty);
      expect(store.positionWrites, 0);
    });

    testWidgets(
      'validates input without stopping reading; cancel and current page do nothing',
      (tester) async {
        final store = _Store(_threePages());
        final speech = FakeSpeechService();
        await _show(tester, store, speech);
        await _tap(tester, _button('Sesli oku'));
        final calls = store.pagesCalls;
        final writes = store.positionWrites;
        await _openGoToPage(tester);
        expect(find.text('Geçerli aralık: 1–3'), findsOneWidget);
        final field = find.byKey(const ValueKey('page-number-input'));
        expect(
          tester
              .widget<TextField>(
                find.descendant(of: field, matching: find.byType(TextField)),
              )
              .keyboardType,
          TextInputType.number,
        );
        await _tap(tester, find.text('Git'));
        expect(find.text('Sayfa numarası girin.'), findsOneWidget);
        await tester.enterText(field, '1.5');
        await _tap(tester, find.text('Git'));
        expect(find.text('Geçerli bir tam sayı girin.'), findsOneWidget);
        await tester.enterText(field, '4');
        await _tap(tester, find.text('Git'));
        expect(
          find.text('1–3 arasında bir sayfa numarası girin.'),
          findsOneWidget,
        );
        expect(speech.isSpeaking, isTrue);
        expect(speech.stopCalls, 0);
        await _tap(tester, find.text('Vazgeç'));
        expect(speech.isSpeaking, isTrue);
        await _goToPage(tester, '1');
        expect(speech.isSpeaking, isTrue);
        expect(speech.stopCalls, 0);
        expect(store.pagesCalls, calls);
        expect(store.positionWrites, writes);
        expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      },
    );

    testWidgets('moving stops playback and does not start the target', (
      tester,
    ) async {
      final store = _Store(_threePages());
      final speech = FakeSpeechService();
      await _show(tester, store, speech);
      await _tap(tester, _button('Sesli oku'));
      final writes = store.positionWrites;
      await _goToPage(tester, '3');
      expect(speech.stopCalls, 1);
      expect(speech.isSpeaking, isFalse);
      expect(speech.spoken, ['Birinci sayfa metni.']);
      expect(store.positionWrites, writes);
      expect(find.text('Üçüncü sayfa metni.'), findsOneWidget);
      await _tap(tester, _button('Sesli oku'));
      expect(speech.spoken.last, 'Üçüncü sayfa metni.');
    });

    testWidgets('single page indicator is not a button', (tester) async {
      await _show(
        tester,
        _Store([_page(1, 0, 'Tek sayfa.')]),
        FakeSpeechService(),
      );
      expect(find.byKey(const ValueKey('go-to-page')), findsNothing);
      expect(find.text('Sayfa 1 / 1'), findsOneWidget);
    });

    testWidgets('failed speech stop prevents direct navigation', (
      tester,
    ) async {
      final speech = FakeSpeechService(stopError: StateError('stop'));
      await _show(tester, _Store(_threePages()), speech);
      await _tap(tester, _button('Sesli oku'));
      await _goToPage(tester, '3');
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(find.text('Birinci sayfa metni.'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('rapid taps open only one dialog', (tester) async {
      await _show(tester, _Store(_threePages()), FakeSpeechService());
      final button = find.byKey(const ValueKey('go-to-page'));
      final center = tester.getCenter(button);
      final first = await tester.startGesture(center, pointer: 1);
      final second = await tester.startGesture(center, pointer: 2);
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(find.text('Sayfa numarası'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      await _tap(tester, find.text('Vazgeç'));
      await _goToPage(tester, '2');
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
    });

    testWidgets('indicator exposes a labelled accessible button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _show(tester, _Store(_threePages()), FakeSpeechService());
      expect(find.bySemanticsLabel('Sayfaya git. Sayfa 1 / 3'), findsOneWidget);
      final node = tester.getSemantics(
        find.byKey(const ValueKey('go-to-page')),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets(
      'load error and rapid touches keep the page and start one move',
      (tester) async {
        final store = _Store(_threePages());
        await _show(tester, store, FakeSpeechService());
        await _openGoToPage(tester);
        await tester.enterText(
          find.byKey(const ValueKey('page-number-input')),
          '3',
        );
        store.pagesGate = Completer<void>();
        final before = store.pagesCalls;
        await tester.tap(find.text('Git'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(_enabled(find.byKey(const ValueKey('go-to-page'))), isFalse);
        expect(store.pagesCalls, before + 1);
        store.pagesError = StateError('db');
        store.pagesGate!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Sayfa 1 / 3'), findsOneWidget);
        expect(find.text('Birinci sayfa metni.'), findsOneWidget);
        expect(
          find.text('Sayfa açılamadı. Mevcut sayfa korundu.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('dialog is usable at large text on a narrow screen', (
      tester,
    ) async {
      await _show(
        tester,
        _Store(_threePages()),
        FakeSpeechService(),
        size: const Size(320, 560),
        textScale: 2,
      );
      await _openGoToPage(tester);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const ValueKey('page-number-input')),
        '2',
      );
      await _tap(tester, find.text('Git'));
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('number dialog remains usable with the keyboard visible', (
      tester,
    ) async {
      await _show(
        tester,
        _Store(_threePages()),
        FakeSpeechService(),
        size: const Size(320, 650),
        textScale: 1.5,
      );
      addTearDown(tester.view.resetViewInsets);
      await _openGoToPage(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('page-number-input')),
        '2',
      );
      await _tap(tester, find.text('Git'));
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('page navigation', () {
    testWidgets('moves by stored order, ignoring position gaps', (
      tester,
    ) async {
      final store = _Store(_threePages());
      await _show(tester, store, FakeSpeechService());

      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(_pageButtonEnabled(_previous), isFalse);
      expect(_pageButtonEnabled(_next), isTrue);

      await _tap(tester, _next);
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(find.text('İkinci sayfa metni.'), findsOneWidget);
      expect(_pageButtonEnabled(_previous), isTrue);

      await _tap(tester, _next);
      expect(find.text('Üçüncü sayfa metni.'), findsOneWidget);
      expect(_pageButtonEnabled(_next), isFalse);

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

      await _tap(tester, find.byTooltip('Görünüm ve sesli okuma'));
      await _tap(tester, find.byKey(const ValueKey('reading-speed')));
      await _tap(tester, find.text('1.5×').last);
      await _tap(tester, find.text('Kapat'));
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
      expect(_pageButtonEnabled(_next), isFalse);
      expect(_pageButtonEnabled(_previous), isFalse);
      await tester.tap(_next);
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
              of: find.byKey(const ValueKey('saved-reading-text')),
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
      final indicator = find.byKey(const ValueKey('go-to-page'));
      for (final finder in [_previous, indicator, _next]) {
        final size = tester.getSize(finder);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(finder.hitTestable(), findsOneWidget);
      }
      final previousRect = tester.getRect(_previous);
      final indicatorRect = tester.getRect(indicator);
      final nextRect = tester.getRect(_next);
      expect(previousRect.center.dy, closeTo(indicatorRect.center.dy, 0.1));
      expect(nextRect.center.dy, closeTo(indicatorRect.center.dy, 0.1));
      expect(previousRect.right, lessThanOrEqualTo(indicatorRect.left));
      expect(indicatorRect.right, lessThanOrEqualTo(nextRect.left));
      await _tap(tester, indicator);
      expect(find.text('Sayfa numarası'), findsOneWidget);
      await _tap(tester, find.text('Vazgeç'));
      await _tap(tester, _previous);
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      await _tap(tester, _next);
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Paneli küçült'));
      await _tap(tester, find.byTooltip('Paneli küçült'));
      expect(tester.takeException(), isNull);
    });
  });

  group('page navigation during editing', () {
    void expectNavigationHidden() {
      expect(_previous, findsNothing);
      expect(_next, findsNothing);
      expect(find.byKey(const ValueKey('go-to-page')), findsNothing);
    }

    Future<void> edit(WidgetTester tester, _Store store) async {
      await _show(tester, store, FakeSpeechService());
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      await _tap(tester, _editButton);
      expectNavigationHidden();
      await tester.enterText(_textField, 'Taslak metin.');
      await tester.pump();
    }

    testWidgets('cancel unchanged restores the navigation bar', (tester) async {
      final store = _Store(_threePages());
      await _show(tester, store, FakeSpeechService());
      await _tap(tester, _editButton);
      expectNavigationHidden();
      await _tap(tester, find.text('Düzenlemekten vazgeç'));
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      await _tap(tester, _next);
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(store.updates, isEmpty);
    });

    testWidgets('keep editing or discard retains the expected state', (
      tester,
    ) async {
      final store = _Store(_threePages());
      await edit(tester, store);
      await _tap(tester, find.text('Düzenlemekten vazgeç'));
      await _tap(tester, find.text('Düzenlemeye devam et'));
      expect(find.text('Taslak metin.'), findsOneWidget);
      expectNavigationHidden();
      await _tap(tester, find.text('Düzenlemekten vazgeç'));
      await _tap(tester, find.text('Kaydetmeden vazgeç'));
      expect(find.text('Birinci sayfa metni.'), findsOneWidget);
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(store.updates, isEmpty);
      await _tap(tester, _next);
      expect(find.text('İkinci sayfa metni.'), findsOneWidget);
    });

    testWidgets('successful save restores navigation and updates the page', (
      tester,
    ) async {
      final store = _Store(_threePages());
      await edit(tester, store);
      await _tap(tester, find.byKey(const ValueKey('save-document')));
      expect(store.updates, [(pageId: 30, text: 'Taslak metin.')]);
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(find.text('Taslak metin.'), findsOneWidget);
      await _tap(tester, _next);
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(find.text('İkinci sayfa metni.'), findsOneWidget);
      expect(_textField, findsNothing);
    });

    testWidgets('saving from the cancel confirmation restores navigation', (
      tester,
    ) async {
      final store = _Store(_threePages());
      await edit(tester, store);
      await _tap(tester, find.text('Düzenlemekten vazgeç'));
      await _tap(tester, find.text('Kaydet ve bitir'));
      expect(store.updates, [(pageId: 30, text: 'Taslak metin.')]);
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(find.text('Taslak metin.'), findsOneWidget);
    });

    testWidgets(
      'save errors keep the draft and navigation hidden until retry',
      (tester) async {
        final store = _Store(_threePages())..updateError = StateError('db');
        await edit(tester, store);
        await _tap(tester, find.byKey(const ValueKey('save-document')));
        expectNavigationHidden();
        expect(find.text('Taslak metin.'), findsOneWidget);
        expect(find.textContaining('Kayıt güncellenemedi'), findsOneWidget);
        await _tap(tester, find.text('Düzenlemekten vazgeç'));
        await _tap(tester, find.text('Kaydet ve bitir'));
        expectNavigationHidden();
        expect(find.text('Taslak metin.'), findsOneWidget);
        expect(find.textContaining('Kayıt güncellenemedi'), findsOneWidget);
        store.updateError = null;
        await _tap(tester, find.byKey(const ValueKey('save-document')));
        expect(find.text('Sayfa 1 / 3'), findsOneWidget);
        expect(store.updates, [(pageId: 30, text: 'Taslak metin.')]);
      },
    );

    testWidgets('invalid text keeps the page and the draft', (tester) async {
      final store = _Store(_threePages());
      await _show(tester, store, FakeSpeechService());
      await _tap(tester, _editButton);
      await tester.enterText(_textField, '   ');
      await tester.pump();
      await _tap(tester, find.byKey(const ValueKey('save-document')));

      expectNavigationHidden();
      expect(find.text('Metin boş olamaz.'), findsOneWidget);
      expect(store.updates, isEmpty);
    });
  });
}

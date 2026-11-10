import 'dart:async';

import 'fake_reading_positions.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';
import 'package:reading_assistant/features/library/presentation/page_navigation_bar.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';

import '../listening/fake_speech_service.dart';
import '../listening/fake_preferences_store.dart';

// Fake store and fake speech engine: these cover our own sequencing and state
// handling, not the real SQLite file or the real TTS engine.
class _Store extends DocumentStore with FakeReadingPositions {
  _Store(this.pageList);

  List<DocumentPage> pageList;
  Object? pagesError;
  Completer<void>? pagesGate;
  int pagesCalls = 0;
  int updateCalls = 0;

  @override
  Future<void> completeReadingPage({
    required int documentId,
    required int pageId,
  }) async {
    if (pageList.isNotEmpty && pageList.last.id == pageId) {
      positions.remove(documentId);
    }
  }

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
    updateCalls++;
    return true;
  }
}

DocumentPage _page(int id, int position, String text) =>
    DocumentPage(id: id, documentId: 7, position: position, text: text);

// Positions have gaps and ids are not in order on purpose.
List<DocumentPage> _threePages() => [
  _page(30, 0, 'Birinci sayfa. İkinci cümle.'),
  _page(10, 4, 'Üçüncü cümle.'),
  _page(20, 9, 'Dördüncü cümle.'),
];

final _switch = find.byKey(const ValueKey('auto-next-page'));
final _next = find.byKey(const ValueKey('next-page'));
final _editButton = find.byIcon(Icons.edit_outlined);

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool _enabled(Finder finder) =>
    (finder.evaluate().single.widget as ButtonStyleButton).onPressed != null;

bool _pageButtonEnabled(Finder finder) =>
    (finder.evaluate().single.widget as IconButton).onPressed != null;

bool _switchOn(WidgetTester tester) => tester
    .widget<Switch>(find.descendant(of: _switch, matching: find.byType(Switch)))
    .value;

Future<void> _show(
  WidgetTester tester,
  _Store store,
  FakeSpeechService speech, {
  Size size = const Size(800, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final open = store.pageList.first;
  await tester.pumpWidget(
    ReadingPreferencesScope(
      preferences: ReadingPreferences(store: FakePreferencesStore()),
      child: MaterialApp(
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
                    pageNumber: 1,
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

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Okuma ayarları'));
  await tester.pumpAndSettle();
}

Future<void> _closeSettings(WidgetTester tester) async {
  await tester.tap(find.text('Kapat'));
  await tester.pumpAndSettle();
}

Future<void> _setSpeed(WidgetTester tester, String speed) async {
  await _openMore(tester);
  await tester.tap(find.byKey(const ValueKey('reading-speed')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(speed).last);
  await tester.pumpAndSettle();
  await _closeSettings(tester);
}

Future<void> _turnOn(WidgetTester tester) async {
  await _openMore(tester);
  await tester.tap(_switch);
  await tester.pumpAndSettle();
  await _closeSettings(tester);
}

Future<void> _read(WidgetTester tester) async {
  await tester.tap(_button('Sesli oku'));
  await tester.pump();
  await tester.pump();
}

/// Lets the current utterance end naturally and settles pending async work.
Future<void> _finish(WidgetTester tester, FakeSpeechService speech) async {
  speech.finishCurrent();
  await tester.pumpAndSettle();
}

void main() {
  group('automatic next page', () {
    testWidgets('is off by default and does not move at the end', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      await _show(tester, _Store(_threePages()), speech);
      await _openMore(tester);
      expect(_switchOn(tester), isFalse);
      await _closeSettings(tester);

      await _read(tester);
      await _finish(tester, speech); // first sentence
      await _finish(tester, speech); // last sentence
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(speech.spoken, ['Birinci sayfa. ', 'İkinci cümle.']);
      expect(find.text('Okuma tamamlandı.'), findsOneWidget);
    });

    testWidgets('turning it on alone starts nothing', (tester) async {
      final speech = FakeSpeechService();
      final store = _Store(_threePages());
      await _show(tester, store, speech);
      final before = store.pagesCalls;
      await _turnOn(tester);

      await _openMore(tester);
      expect(_switchOn(tester), isTrue);
      await _closeSettings(tester);
      expect(speech.spoken, isEmpty);
      expect(store.pagesCalls, before);
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
    });

    testWidgets('reads the next stored page from its first sentence, and '
        'ends on the last page', (tester) async {
      final speech = FakeSpeechService();
      final store = _Store(_threePages());
      await _show(tester, store, speech);
      await _turnOn(tester);

      await _read(tester);
      await _finish(tester, speech);
      expect(find.text('Sayfa 1 / 3'), findsOneWidget, reason: 'mid page');
      await _finish(tester, speech); // end of page 1

      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(speech.spoken.last, 'Üçüncü cümle.');
      expect(find.text('Cümle 1 / 1'), findsOneWidget);
      expect(store.positions[7]?.pageId, 10);
      expect(store.positions[7]?.sentenceIndex, 0);

      await _finish(tester, speech);
      expect(find.text('Sayfa 3 / 3'), findsOneWidget);
      expect(speech.spoken.last, 'Dördüncü cümle.');
      expect(store.positions[7]?.pageId, 20);

      await _finish(tester, speech); // end of the last page
      expect(find.text('Sayfa 3 / 3'), findsOneWidget);
      expect(speech.isSpeaking, isFalse);
      expect(speech.spoken, hasLength(4));
      expect(store.positions[7], isNull);
      expect(_button('Sesli oku'), findsOneWidget);
      await _openMore(tester);
      expect(_switchOn(tester), isTrue, reason: 'preference kept');
      expect(store.updateCalls, 0);
    });

    testWidgets('keeps the speed across pages', (tester) async {
      final speech = FakeSpeechService();
      await _show(tester, _Store(_threePages()), speech);
      await _turnOn(tester);
      await _setSpeed(tester, '1.5×');

      await _read(tester);
      await _finish(tester, speech);
      await _finish(tester, speech);

      expect(speech.spoken.last, 'Üçüncü cümle.');
      expect(speech.spokenRates.last, 1.5);
      await _openMore(tester);
      expect(find.text('1.5×'), findsOneWidget);
    });

    testWidgets('settings stay live during automatic page transition', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      await _show(tester, _Store(_threePages()), speech);
      await _turnOn(tester);
      await _read(tester);
      await _openMore(tester);
      expect(speech.stopCalls, 0);
      await _finish(tester, speech);
      await _finish(tester, speech);
      expect(speech.spoken.last, 'Üçüncü cümle.');
      expect(_switchOn(tester), isTrue);
      expect(find.text('1×'), findsOneWidget);
      await _closeSettings(tester);
      expect(speech.isSpeaking, isTrue);
      expect(speech.stopCalls, 0);
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
    });

    testWidgets('settings reflect a changed page count while open', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      final store = _Store(_threePages());
      await _show(tester, store, speech);
      await _turnOn(tester);
      await _read(tester);
      await _openMore(tester);
      expect(_switchOn(tester), isTrue);
      store.pageList = [store.pageList.first];
      await _finish(tester, speech);
      await _finish(tester, speech);
      expect(_switch, findsNothing);
      expect(find.text('1×'), findsOneWidget);
      await _closeSettings(tester);
      expect(find.text('Sayfa 1 / 1'), findsOneWidget);
      expect(speech.isSpeaking, isFalse);
    });

    testWidgets('pause, stop, error and sentence controls do not move', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      final store = _Store(_threePages());
      await _show(tester, store, speech);
      await _turnOn(tester);

      await _read(tester);
      await tester.tap(_button('Duraklat'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Devam et'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Sonraki cümle'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Başa dön'));
      await tester.pumpAndSettle();
      await _setSpeed(tester, '1.25×');
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);

      await tester.tap(_button('Durdur'));
      await tester.pumpAndSettle();
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(speech.isSpeaking, isFalse);

      await _read(tester);
      speech.failCurrent();
      await tester.pumpAndSettle();
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(
        find.text(
          'Sesli okuma sırasında bir hata oluştu. Tekrar deneyebilirsin.',
        ),
        findsOneWidget,
      );
      expect(speech.isSpeaking, isFalse);
    });

    testWidgets('turning it off keeps the current reading going', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      await _show(tester, _Store(_threePages()), speech);
      await _turnOn(tester);
      await _read(tester);

      await _openMore(tester);
      await tester.tap(_switch);
      await tester.pumpAndSettle();
      await _closeSettings(tester);
      expect(speech.isSpeaking, isTrue);
      expect(speech.stopCalls, 0);

      await _finish(tester, speech);
      await _finish(tester, speech);
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
    });

    testWidgets('manual page change stops reading and does not auto-read', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      await _show(tester, _Store(_threePages()), speech);
      await _turnOn(tester);
      await _read(tester);

      await tester.tap(_next);
      await tester.pumpAndSettle();
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(speech.isSpeaking, isFalse);
      expect(speech.spoken, hasLength(1));
      await _openMore(tester);
      expect(_switchOn(tester), isTrue);
    });

    testWidgets('Stop during the move cancels it', (tester) async {
      final speech = FakeSpeechService();
      final store = _Store(_threePages());
      await _show(tester, store, speech);
      await _turnOn(tester);
      await _read(tester);
      await _finish(tester, speech);

      store.pagesGate = Completer<void>();
      speech.finishCurrent();
      await tester.pump();
      await tester.pump();
      expect(find.text('Sonraki sayfa açılıyor…'), findsOneWidget);
      expect(_enabled(_button('Durdur')), isTrue);
      expect(_pageButtonEnabled(_next), isFalse);
      expect(_enabled(_button('Sesli oku')), isFalse);
      await tester.tap(_button('Durdur'));
      await tester.pump();
      expect(find.text('Sonraki sayfa açılıyor…'), findsNothing);
      expect(_pageButtonEnabled(_next), isTrue);

      store.pagesGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(speech.spoken, hasLength(2));
      expect(speech.isSpeaking, isFalse);
      expect(store.updateCalls, 0);
    });

    testWidgets('turning it off during the move cancels it', (tester) async {
      final speech = FakeSpeechService();
      final store = _Store(_threePages());
      await _show(tester, store, speech);
      await _turnOn(tester);
      await _read(tester);
      await _finish(tester, speech);

      store.pagesGate = Completer<void>();
      speech.finishCurrent();
      await tester.pump();
      await tester.pump();
      await _openMore(tester);
      await tester.tap(_switch);
      await tester.pump();
      await _closeSettings(tester);
      store.pagesGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(speech.spoken, hasLength(2));
    });

    testWidgets('moving locks edit, manual navigation and start', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      final store = _Store(_threePages());
      await _show(tester, store, speech);
      await _turnOn(tester);
      await _read(tester);
      await _finish(tester, speech);

      store.pagesGate = Completer<void>();
      speech.finishCurrent();
      await tester.pump();
      await tester.pump();

      expect(_pageButtonEnabled(_next), isFalse);
      expect(_enabled(_button('Sesli oku')), isFalse);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(of: _editButton, matching: find.byType(IconButton)),
            )
            .onPressed,
        isNull,
      );

      store.pagesGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(speech.spoken.last, 'Üçüncü cümle.');
    });

    testWidgets('going to the background cancels the pending move', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      final store = _Store(_threePages());
      await _show(tester, store, speech);
      await _turnOn(tester);
      await _read(tester);
      await _finish(tester, speech);

      store.pagesGate = Completer<void>();
      speech.finishCurrent();
      await tester.pump();
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      store.pagesGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(speech.spoken, hasLength(2));
      expect(speech.isSpeaking, isFalse);
    });

    testWidgets('closing the screen ignores the late page result', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      final store = _Store(_threePages());
      await _show(tester, store, speech);
      await _turnOn(tester);
      await _read(tester);
      await _finish(tester, speech);

      store.pagesGate = Completer<void>();
      speech.finishCurrent();
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      store.pagesGate!.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(speech.spoken, hasLength(2));
      expect(speech.isSpeaking, isFalse);
    });

    testWidgets('a repeated completion starts only one move', (tester) async {
      final speech = FakeSpeechService();
      final store = _Store(_threePages());
      await _show(tester, store, speech);
      await _turnOn(tester);
      await _read(tester);
      await _finish(tester, speech);

      final before = store.pagesCalls;
      speech.finishCurrent();
      speech.finishCurrent();
      await tester.pumpAndSettle();

      expect(store.pagesCalls - before, 1);
      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(speech.spoken.where((s) => s == 'Üçüncü cümle.'), hasLength(1));
    });

    testWidgets('a load failure keeps the page and stops continuing', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      final store = _Store(_threePages());
      await _show(tester, store, speech);
      await _turnOn(tester);
      await _read(tester);
      await _finish(tester, speech);

      store.pagesError = StateError('db');
      await _finish(tester, speech);

      expect(find.text('Sayfa 1 / 3'), findsOneWidget);
      expect(
        find.text('Sonraki sayfa açılamadı. Otomatik okuma durdu.'),
        findsOneWidget,
      );
      expect(speech.spoken, hasLength(2));
      expect(_pageButtonEnabled(_next), isTrue);
      expect(find.text('Birinci sayfa. İkinci cümle.'), findsOneWidget);
    });

    testWidgets('a blank next page ends reading and is not skipped', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      final store = _Store([
        _page(1, 0, 'Tek cümle.'),
        _page(2, 1, '   \n '),
        _page(3, 2, 'Sonraki dolu sayfa.'),
      ]);
      await _show(tester, store, speech);
      await _turnOn(tester);
      await _read(tester);
      await _finish(tester, speech);

      expect(find.text('Sayfa 2 / 3'), findsOneWidget);
      expect(
        find.text('Bu sayfa boş olduğu için otomatik okuma durdu.'),
        findsOneWidget,
      );
      expect(speech.spoken, ['Tek cümle.']);
      expect(speech.isSpeaking, isFalse);
    });

    testWidgets(
      'page row and panel stay full width and collapsed across pages',
      (tester) async {
        await _show(tester, _Store(_threePages()), FakeSpeechService());
        final panel = find.byKey(const ValueKey('listening-panel'));
        final row = find.byType(PageNavigationBar);
        expect(tester.getSize(panel).width, 800);
        expect(tester.getSize(row).width, 800);
        expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
        await tester.tap(find.byTooltip('Paneli küçült'));
        await tester.pumpAndSettle();
        expect(find.text('Sonraki cümle'), findsNothing);
        expect(find.text('Durdur'), findsOneWidget);
        await tester.tap(_next);
        await tester.pumpAndSettle();
        expect(find.text('Sayfa 2 / 3'), findsOneWidget);
        expect(find.byTooltip('Paneli genişlet'), findsOneWidget);
        expect(tester.getSize(panel).width, 800);
        expect(tester.getSize(row).width, 800);
      },
    );

    testWidgets('single-page content has no switch', (tester) async {
      final speech = FakeSpeechService();
      await _show(tester, _Store([_page(1, 0, 'Tek.')]), speech);
      expect(
        tester.getSize(find.byKey(const ValueKey('listening-panel'))).width,
        800,
      );
      final row = find.byType(PageNavigationBar);
      expect(tester.getSize(row).width, 800);
      await _openMore(tester);
      expect(_switch, findsNothing);
    });

    testWidgets('is available on narrow screens with large text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _show(
        tester,
        _Store(_threePages()),
        FakeSpeechService(),
        size: const Size(320, 560),
      );
      await _openMore(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Sonraki sayfayı otomatik oku'), findsOneWidget);
    });
  });
}

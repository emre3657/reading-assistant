import 'dart:async';
import 'dart:ui' as ui;

import 'fake_reading_positions.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/reading_position.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';
import 'package:reading_assistant/features/library/presentation/page_navigation_bar.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';
import 'package:reading_assistant/features/listening/presentation/page_transition.dart';
import 'package:reading_assistant/features/listening/presentation/bookmark_artwork.dart';

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
  ReadingPreferences? preferences,
  bool disableAnimations = false,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  Future<ui.Image> Function(GlobalKey, double)? capturePageImage,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final open = store.pageList.first;
  await tester.pumpWidget(
    ReadingPreferencesScope(
      preferences:
          preferences ?? ReadingPreferences(store: FakePreferencesStore()),
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            textScaler: TextScaler.linear(textScale),
          ),
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
                    pageNumber: 1,
                    store: store,
                    speechService: speech,
                    capturePageImage: capturePageImage,
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
  await tester.tap(find.byTooltip('Görünüm ve sesli okuma'));
  await tester.pumpAndSettle();
}

Future<void> _closeSettings(WidgetTester tester) async {
  await tester.tap(find.text('Kapat'));
  await tester.pumpAndSettle();
}

Future<void> _setSpeed(WidgetTester tester, String speed) async {
  await _openMore(tester);
  await tester.ensureVisible(find.byKey(const ValueKey('reading-speed')));
  await tester.tap(find.byKey(const ValueKey('reading-speed')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(speed).last);
  await tester.pumpAndSettle();
  await _closeSettings(tester);
}

Future<void> _turnOn(WidgetTester tester) async {
  await _openMore(tester);
  await tester.ensureVisible(_switch);
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
  testWidgets(
    'bookmark appearance settings preview and persist without adding a bookmark',
    (tester) async {
      final settingsStore = FakePreferencesStore();
      final preferences = ReadingPreferences(store: settingsStore);
      await preferences.load();
      final store = _Store(_threePages());
      await _show(
        tester,
        store,
        FakeSpeechService(),
        preferences: preferences,
        size: const Size(320, 700),
        textScale: 1.5,
      );
      await _openMore(tester);
      await tester.ensureVisible(find.text('Ayraç görünümü'));
      await tester.pumpAndSettle();
      for (final shape in BookmarkShape.values) {
        await tester.ensureVisible(find.text(shape.label));
        await tester.tap(find.text(shape.label));
        await tester.pumpAndSettle();
        expect(preferences.bookmarkShape, shape);
        expect(find.byType(BookmarkArtwork), findsNWidgets(3));
      }
      await tester.ensureVisible(find.text('Mavi'));
      await tester.tap(find.text('Mavi'));
      await tester.pumpAndSettle();
      expect(preferences.bookmarkColor, BookmarkColor.blue);
      await preferences.pendingWrites;
      final restored = ReadingPreferences(store: settingsStore);
      await restored.load();
      expect(restored.bookmarkShape, BookmarkShape.corner);
      expect(restored.bookmarkColor, BookmarkColor.blue);
      expect(store.bookmarks, isEmpty);
      await _closeSettings(tester);
      expect(find.byKey(const ValueKey('visual-bookmark')), findsNothing);
      await tester.tap(find.byTooltip('Ayraç seçenekleri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayraç koy'));
      await tester.pumpAndSettle();
      final artwork = tester.widget<BookmarkArtwork>(
        find.descendant(
          of: find.byKey(const ValueKey('visual-bookmark')),
          matching: find.byType(BookmarkArtwork),
        ),
      );
      expect(artwork.shape, BookmarkShape.corner);
      expect(artwork.color, BookmarkColor.blue.light);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bookmark artwork reveals its location without changing progress',
    (tester) async {
      final text = List.generate(80, (index) => 'Cümle $index.').join('\n\n');
      final store = _Store([_page(30, 0, text), _page(10, 1, 'Sonraki.')]);
      store.bookmarks[7] = ReadingPosition(
        pageId: 30,
        sentenceIndex: 60,
        pageText: text,
      );
      store.positions[7] = ReadingPosition(
        pageId: 30,
        sentenceIndex: 1,
        pageText: text,
      );
      final speech = FakeSpeechService();
      await _show(tester, store, speech);
      final bookmark = find.byTooltip('İşaretlediğin yere git');
      expect(bookmark, findsOneWidget);
      expect(tester.getSize(bookmark).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(bookmark).height, greaterThanOrEqualTo(48));
      await tester.tap(bookmark);
      await tester.pumpAndSettle();
      final scroll = tester.widget<SingleChildScrollView>(
        find
            .descendant(
              of: find.byType(SavedDocumentScreen),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
      );
      expect(scroll.controller!.offset, greaterThan(0));
      final scrollFinder = find
          .descendant(
            of: find.byType(SavedDocumentScreen),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      expect(
        tester.getRect(bookmark).overlaps(tester.getRect(scrollFinder)),
        isFalse,
      );
      expect(store.positions[7]?.sentenceIndex, 1);
      expect(store.bookmarks[7]?.sentenceIndex, 60);
      expect(speech.spoken, isEmpty);
    },
  );

  testWidgets(
    'retraction precedes speech and stop restores the unchanged bookmark',
    (tester) async {
      final store = _Store(_threePages());
      store.bookmarks[7] = const ReadingPosition(
        pageId: 30,
        sentenceIndex: 1,
        pageText: 'Birinci sayfa. İkinci cümle.',
      );
      final speech = FakeSpeechService();
      await _show(tester, store, speech);
      final bookmark = find.byKey(const ValueKey('visual-bookmark'));
      expect(bookmark, findsOneWidget);
      await tester.tap(_button('Sesli oku'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(speech.prepareCalls, 0);
      expect(store.positionWrites, 0);
      expect(_enabled(_button('Sesli oku')), isFalse);
      await tester.pumpAndSettle();
      expect(speech.spoken.single, 'Birinci sayfa. ');
      expect(bookmark, findsNothing);
      await tester.tap(_button('Duraklat'));
      await tester.pumpAndSettle();
      expect(bookmark, findsNothing);
      await tester.tap(_button('Durdur'));
      await tester.pumpAndSettle();
      expect(bookmark, findsOneWidget);
      expect(store.bookmarks[7]?.sentenceIndex, 1);
      expect(store.positions[7]?.sentenceIndex, 0);
    },
  );

  testWidgets('retraction can be stopped or closed without starting speech', (
    tester,
  ) async {
    final store = _Store(_threePages());
    store.bookmarks[7] = const ReadingPosition(
      pageId: 30,
      sentenceIndex: 0,
      pageText: 'Birinci sayfa. İkinci cümle.',
    );
    final speech = FakeSpeechService();
    await _show(tester, store, speech);
    await tester.tap(_button('Sesli oku'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(_button('Durdur'));
    await tester.pumpAndSettle();
    expect(speech.prepareCalls, 0);
    expect(find.byKey(const ValueKey('visual-bookmark')), findsOneWidget);
    await tester.tap(_button('Sesli oku'));
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('aç'), findsOneWidget);
    expect(speech.prepareCalls, 0);
    expect(store.bookmarks[7], isNotNull);
  });

  testWidgets(
    'bookmark waits for page transition and reduced motion starts immediately',
    (tester) async {
      final preferences = ReadingPreferences(store: FakePreferencesStore());
      await preferences.load();
      preferences.setPageAnimationEnabled(true);
      preferences.setPageAnimationEffect(PageAnimationEffect.slide);
      final store = _Store(_threePages());
      store.bookmarks[7] = const ReadingPosition(
        pageId: 10,
        sentenceIndex: 0,
        pageText: 'Üçüncü cümle.',
      );
      final speech = FakeSpeechService();
      await _show(tester, store, speech, preferences: preferences);
      expect(find.byKey(const ValueKey('visual-bookmark')), findsNothing);
      await tester.tap(_next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(const ValueKey('visual-bookmark')), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('visual-bookmark')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _show(
        tester,
        store,
        speech,
        preferences: preferences,
        disableAnimations: true,
      );
      await tester.tap(_next);
      await tester.pumpAndSettle();
      await tester.tap(_button('Sesli oku'));
      await tester.pump();
      await tester.pump();
      expect(speech.spoken, ['Üçüncü cümle.']);
      expect(find.byKey(const ValueKey('visual-bookmark')), findsNothing);
    },
  );

  testWidgets(
    'automatic next page does not retract its bookmark before speech',
    (tester) async {
      final preferences = ReadingPreferences(store: FakePreferencesStore());
      await preferences.load();
      preferences.setAutoNextPage(true);
      final store = _Store([_page(30, 0, 'Birinci.'), _page(10, 1, 'İkinci.')]);
      store.bookmarks[7] = const ReadingPosition(
        pageId: 10,
        sentenceIndex: 0,
        pageText: 'İkinci.',
      );
      final speech = FakeSpeechService();
      await _show(tester, store, speech, preferences: preferences);
      await _read(tester);
      speech.finishCurrent();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(speech.spoken, ['Birinci.', 'İkinci.']);
      expect(find.byKey(const ValueKey('visual-bookmark')), findsNothing);
      expect(store.bookmarks[7]?.pageId, 10);
    },
  );

  testWidgets('bookmark is accessible on a narrow dark screen', (tester) async {
    final store = _Store(_threePages());
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setPageView(ReadingPageView.book);
    preferences.setBookmarkColor(BookmarkColor.purple);
    store.bookmarks[7] = const ReadingPosition(
      pageId: 30,
      sentenceIndex: 0,
      pageText: 'Birinci sayfa. İkinci cümle.',
    );
    final semantics = tester.ensureSemantics();
    await _show(
      tester,
      store,
      FakeSpeechService(),
      size: const Size(320, 700),
      textScale: 2,
      brightness: Brightness.dark,
      preferences: preferences,
    );
    final bookmark = find.byTooltip('İşaretlediğin yere git');
    expect(bookmark.hitTestable(), findsOneWidget);
    expect(tester.getSize(bookmark), const Size(48, 48));
    final artwork = tester.widget<BookmarkArtwork>(
      find.descendant(of: bookmark, matching: find.byType(BookmarkArtwork)),
    );
    expect(artwork.color, BookmarkColor.purple.dark);
    expect(find.bySemanticsLabel('İşaretlediğin yere git'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('İşaretlediğin yere git'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('background cancels bookmark retraction', (tester) async {
    final store = _Store(_threePages());
    store.bookmarks[7] = const ReadingPosition(
      pageId: 30,
      sentenceIndex: 0,
      pageText: 'Birinci sayfa. İkinci cümle.',
    );
    final speech = FakeSpeechService();
    await _show(tester, store, speech);
    await tester.tap(_button('Sesli oku'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(speech.prepareCalls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('visual-bookmark')), findsOneWidget);
    expect(store.bookmarks[7]?.pageId, 30);
  });

  testWidgets(
    'bookmark navigation animates only between pages and reveals text',
    (tester) async {
      final preferences = ReadingPreferences(store: FakePreferencesStore());
      await preferences.load();
      preferences.setPageAnimationEnabled(true);
      final text = List.generate(80, (index) => 'Cümle $index.').join('\n\n');
      final store = _Store([
        _page(30, 0, 'Birinci sayfa.'),
        _page(10, 4, text),
      ]);
      store.positions[7] = const ReadingPosition(
        pageId: 30,
        sentenceIndex: 0,
        pageText: 'Birinci sayfa.',
      );
      store.bookmarks[7] = ReadingPosition(
        pageId: 10,
        sentenceIndex: 60,
        pageText: text,
      );
      final speech = FakeSpeechService();
      await _show(tester, store, speech, preferences: preferences);

      Future<void> jump() async {
        await tester.tap(find.byTooltip('Ayraç seçenekleri'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ayraca git'));
        await tester.pump();
      }

      await jump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester
            .widget<ReadingPageTransition>(find.byType(ReadingPageTransition))
            .previous,
        isNotNull,
      );
      await tester.pumpAndSettle();
      expect(find.text('Sayfa 2 / 2'), findsOneWidget);
      final scroll = tester.widget<SingleChildScrollView>(
        find
            .descendant(
              of: find.byType(SavedDocumentScreen),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
      );
      expect(scroll.controller!.offset, greaterThan(0));
      expect(store.positions[7]?.pageId, 30);
      expect(speech.spoken, isEmpty);
      await jump();
      expect(
        tester
            .widget<ReadingPageTransition>(find.byType(ReadingPageTransition))
            .previous,
        isNull,
      );
      await tester.pumpAndSettle();
      await _read(tester);
      await tester.pumpAndSettle();
      expect(speech.spoken.single, startsWith('Cümle 60.'));
    },
  );

  for (final effect in PageAnimationEffect.values) {
    final expectedDuration = switch (effect) {
      PageAnimationEffect.fade => const Duration(milliseconds: 500),
      PageAnimationEffect.slide => const Duration(milliseconds: 500),
      PageAnimationEffect.turn => const Duration(milliseconds: 800),
    };
    testWidgets(
      '${effect.name} transitions both directions and removes old page',
      (tester) async {
        final preferences = ReadingPreferences(store: FakePreferencesStore());
        await preferences.load();
        preferences.setPageAnimationEnabled(true);
        preferences.setPageAnimationEffect(effect);
        final speech = FakeSpeechService();
        await _show(
          tester,
          _Store(_threePages()),
          speech,
          preferences: preferences,
        );
        var transition = tester.widget<ReadingPageTransition>(
          find.byType(ReadingPageTransition),
        );
        expect(transition.previous, isNull);
        await tester.tap(_next);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        transition = tester.widget<ReadingPageTransition>(
          find.byType(ReadingPageTransition),
        );
        expect(transition.previous, isNotNull);
        expect(transition.forward, isTrue);
        expect(transition.effect, effect);
        expect(
          (transition.animation as AnimationController).duration,
          expectedDuration,
        );
        expect(
          find.descendant(
            of: find.byType(ReadingPageTransition),
            matching: find.byType(ExcludeSemantics),
          ),
          findsWidgets,
        );
        expect(_pageButtonEnabled(_next), isFalse);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ReadingPageTransition>(find.byType(ReadingPageTransition))
              .previous,
          isNull,
        );
        expect(find.text('Sayfa 2 / 3'), findsOneWidget);
        expect(speech.spoken, isEmpty);
        await tester.tap(find.byKey(const ValueKey('previous-page')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        transition = tester.widget<ReadingPageTransition>(
          find.byType(ReadingPageTransition),
        );
        expect(transition.previous, isNotNull);
        expect(transition.forward, isFalse);
        await tester.pumpAndSettle();
        expect(find.text('Sayfa 1 / 3'), findsOneWidget);
        expect(
          tester
              .widget<ReadingPageTransition>(find.byType(ReadingPageTransition))
              .previous,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final effect in PageAnimationEffect.values) {
    testWidgets('${effect.name} preview uses the same duration as the reader', (
      tester,
    ) async {
      final preferences = ReadingPreferences(store: FakePreferencesStore());
      await preferences.load();
      preferences.setPageAnimationEnabled(true);
      preferences.setPageAnimationEffect(effect);
      await _show(
        tester,
        _Store(_threePages()),
        FakeSpeechService(),
        preferences: preferences,
      );
      await _openMore(tester);
      final preview = find.text('Önizlemeyi oynat');
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      await tester.tap(preview);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final transition = tester
          .widgetList<ReadingPageTransition>(find.byType(ReadingPageTransition))
          .singleWhere((item) => item.previous != null);
      expect(
        (transition.animation as AnimationController).duration,
        pageTransitionDuration(effect),
      );
      if (effect == PageAnimationEffect.turn) {
        expect(transition.snapshot, isNotNull);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('background cancels a curl preview and releases its snapshot', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setPageAnimationEnabled(true);
    preferences.setPageAnimationEffect(PageAnimationEffect.turn);
    await _show(
      tester,
      _Store(_threePages()),
      FakeSpeechService(),
      preferences: preferences,
    );
    await _openMore(tester);
    final preview = find.text('Önizlemeyi oynat');
    await tester.ensureVisible(preview);
    await tester.pumpAndSettle();
    await tester.tap(preview);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final snapshot = tester
        .widgetList<ReadingPageTransition>(find.byType(ReadingPageTransition))
        .singleWhere((item) => item.snapshot != null)
        .snapshot!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(snapshot.debugDisposed, isTrue);
    expect(_enabled(_button('Önizlemeyi oynat')), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('curl captures the visible scrolled viewport', (tester) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setPageAnimationEnabled(true);
    preferences.setPageAnimationEffect(PageAnimationEffect.turn);
    final text = List.generate(120, (index) => 'Satır $index.').join('\n\n');
    await _show(
      tester,
      _Store([_page(30, 0, text), _page(10, 1, 'Sonraki.')]),
      FakeSpeechService(),
      preferences: preferences,
      size: const Size(360, 700),
    );
    final scroll = find
        .descendant(
          of: find.byType(SavedDocumentScreen),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    await tester.drag(scroll, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SingleChildScrollView>(scroll).controller!.offset,
      greaterThan(0),
    );
    final boundaryFinder = find.ancestor(
      of: find.byKey(const ValueKey('saved-reading-text')),
      matching: find.byWidgetPredicate(
        (widget) => widget is RepaintBoundary && widget.key is GlobalKey,
      ),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      boundaryFinder.first,
    );
    final before = boundary.toImageSync();
    final expected = await tester.runAsync(
      () => before.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    before.dispose();

    await tester.tap(_next);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (tester
              .widget<ReadingPageTransition>(find.byType(ReadingPageTransition))
              .snapshot !=
          null) {
        break;
      }
    }
    final snapshot = tester
        .widget<ReadingPageTransition>(find.byType(ReadingPageTransition))
        .snapshot!;
    expect(snapshot.width, boundary.size.width.round());
    expect(snapshot.height, boundary.size.height.round());
    final actual = await tester.runAsync(
      () => snapshot.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(
      actual!.buffer.asUint8List(),
      orderedEquals(expected!.buffer.asUint8List()),
    );
    await tester.pumpAndSettle();
    expect(snapshot.debugDisposed, isTrue);
  });

  testWidgets('capture failure falls back to a direct readable page', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setPageAnimationEnabled(true);
    preferences.setPageAnimationEffect(PageAnimationEffect.turn);
    final oldDebugPrint = debugPrint;
    final messages = <String?>[];
    debugPrint = (String? message, {int? wrapWidth}) => messages.add(message);
    addTearDown(() => debugPrint = oldDebugPrint);
    await _show(
      tester,
      _Store(_threePages()),
      FakeSpeechService(),
      preferences: preferences,
      capturePageImage: (_, _) => Future.error(StateError('capture failed')),
    );
    await tester.tap(_next);
    await tester.pumpAndSettle();
    expect(find.text('Sayfa 2 / 3'), findsOneWidget);
    expect(
      tester
          .widget<ReadingPageTransition>(find.byType(ReadingPageTransition))
          .previous,
      isNull,
    );
    expect(
      messages.any((message) => message?.contains('capture failed') ?? false),
      isTrue,
    );
    expect(_pageButtonEnabled(_next), isTrue);
    debugPrint = oldDebugPrint;
  });

  testWidgets('closing while capture is pending disposes its late image', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setPageAnimationEnabled(true);
    preferences.setPageAnimationEffect(PageAnimationEffect.turn);
    final capture = Completer<ui.Image>();
    final store = _Store(_threePages());
    await _show(
      tester,
      store,
      FakeSpeechService(),
      preferences: preferences,
      capturePageImage: (_, _) => capture.future,
    );
    await tester.tap(_next);
    await tester.pump();
    await tester.pump();
    expect(find.text('Sayfa 1 / 3'), findsOneWidget);
    expect(_pageButtonEnabled(_next), isFalse);
    final pagesCalls = store.pagesCalls;
    await tester.tap(_next);
    await tester.pump();
    expect(store.pagesCalls, pagesCalls);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('aç'), findsOneWidget);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(1, 1);
    capture.complete(image);
    await tester.pump();
    expect(image.debugDisposed, isTrue);
    picture.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatic reading waits for animation and starts once', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setPageAnimationEnabled(true);
    preferences.setPageAnimationEffect(PageAnimationEffect.turn);
    preferences.setAutoNextPage(true);
    final store = _Store(_threePages());
    final speech = FakeSpeechService();
    await _show(tester, store, speech, preferences: preferences);
    await _read(tester);
    await _finish(tester, speech);
    speech.finishCurrent();
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (tester
              .widget<ReadingPageTransition>(find.byType(ReadingPageTransition))
              .previous !=
          null) {
        break;
      }
    }
    expect(
      tester
          .widget<ReadingPageTransition>(find.byType(ReadingPageTransition))
          .previous,
      isNotNull,
    );
    expect(speech.spoken, ['Birinci sayfa. ', 'İkinci cümle.']);
    await tester.pump(const Duration(milliseconds: 350));
    expect(speech.spoken, ['Birinci sayfa. ', 'İkinci cümle.']);
    await tester.pumpAndSettle();
    expect(speech.spoken, [
      'Birinci sayfa. ',
      'İkinci cümle.',
      'Üçüncü cümle.',
    ]);
    expect(store.positions[7]?.pageId, 10);
  });

  testWidgets('reduced motion moves immediately and preserves the preference', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setPageAnimationEnabled(true);
    preferences.setPageAnimationEffect(PageAnimationEffect.turn);
    var captures = 0;
    await _show(
      tester,
      _Store(_threePages()),
      FakeSpeechService(),
      preferences: preferences,
      disableAnimations: true,
      capturePageImage: (_, _) {
        captures++;
        return Future.error(StateError('capture should not run'));
      },
    );
    await tester.tap(_next);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ReadingPageTransition>(find.byType(ReadingPageTransition))
          .previous,
      isNull,
    );
    expect(find.text('Sayfa 2 / 3'), findsOneWidget);
    expect(preferences.pageAnimationEnabled, isTrue);
    expect(preferences.pageAnimationEffect, PageAnimationEffect.turn);
    expect(captures, 0);
  });

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

    testWidgets(
      'settings preview plays only on request and keeps selected effect',
      (tester) async {
        final preferences = ReadingPreferences(store: FakePreferencesStore());
        await preferences.load();
        preferences.setPageView(ReadingPageView.book);
        await _show(
          tester,
          _Store(_threePages()),
          FakeSpeechService(),
          preferences: preferences,
          size: const Size(320, 700),
          textScale: 1.6,
        );
        await _openMore(tester);
        final toggle = find.byKey(const ValueKey('page-animation-enabled'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(preferences.pageAnimationEffect, PageAnimationEffect.fade);
        final option = find.text('Dikey kayma');
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(preferences.pageAnimationEffect, PageAnimationEffect.slide);
        final preview = find.text('Önizlemeyi oynat');
        await tester.ensureVisible(preview);
        await tester.pumpAndSettle();
        expect(find.text('Örnek sayfa 1'), findsOneWidget);
        expect(find.text('Örnek sayfa 2'), findsNothing);
        await tester.tap(preview);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final transitions = tester.widgetList<ReadingPageTransition>(
          find.byType(ReadingPageTransition),
        );
        expect(
          transitions.where(
            (t) => t.previous != null && t.effect == PageAnimationEffect.slide,
          ),
          hasLength(1),
        );
        await tester.pumpAndSettle();
        expect(find.text('Örnek sayfa 2'), findsOneWidget);
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(preferences.pageAnimationEffect, PageAnimationEffect.slide);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'load failure and closing during an animation keep navigation safe',
      (tester) async {
        final preferences = ReadingPreferences(store: FakePreferencesStore());
        await preferences.load();
        preferences.setPageAnimationEnabled(true);
        final store = _Store(_threePages());
        final speech = FakeSpeechService();
        await _show(tester, store, speech, preferences: preferences);
        store.pagesError = StateError('disk');
        await tester.tap(_next);
        await tester.pumpAndSettle();
        expect(find.text('Sayfa 1 / 3'), findsOneWidget);
        expect(
          find.text('Sayfa açılamadı. Mevcut sayfa korundu.'),
          findsOneWidget,
        );
        store.pagesError = null;
        await tester.tap(_next);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(_pageButtonEnabled(_next), isFalse);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('aç'), findsOneWidget);
        expect(speech.spoken, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('background during animation cancels automatic speech', (
      tester,
    ) async {
      final preferences = ReadingPreferences(store: FakePreferencesStore());
      await preferences.load();
      preferences.setPageAnimationEnabled(true);
      preferences.setPageAnimationEffect(PageAnimationEffect.turn);
      preferences.setAutoNextPage(true);
      final speech = FakeSpeechService();
      await _show(
        tester,
        _Store(_threePages()),
        speech,
        preferences: preferences,
      );
      await _read(tester);
      await _finish(tester, speech);
      speech.finishCurrent();
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (tester
                .widget<ReadingPageTransition>(
                  find.byType(ReadingPageTransition),
                )
                .snapshot !=
            null) {
          break;
        }
      }
      final snapshot = tester
          .widget<ReadingPageTransition>(find.byType(ReadingPageTransition))
          .snapshot!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(snapshot.debugDisposed, isTrue);
      expect(speech.spoken, ['Birinci sayfa. ', 'İkinci cümle.']);
      expect(
        tester
            .widget<ReadingPageTransition>(find.byType(ReadingPageTransition))
            .previous,
        isNull,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
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

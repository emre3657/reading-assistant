import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';

import '../library/fake_reading_positions.dart';
import '../image_import/test_doubles.dart';
import 'fake_preferences_store.dart';
import 'fake_speech_service.dart';

class _Store extends DocumentStore with FakeReadingPositions {
  _Store(this.pagesList);
  final List<DocumentPage> pagesList;

  @override
  Future<List<DocumentPage>> pages(int documentId) async => pagesList;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<ScrollController> _show(
  WidgetTester tester, {
  required String text,
  required FakeSpeechService speech,
  required ReadingPreferences preferences,
  int? initialSentence,
  String? nextPage,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final pages = [
    DocumentPage(id: 1, documentId: 7, position: 0, text: text),
    if (nextPage != null)
      DocumentPage(id: 2, documentId: 7, position: 1, text: nextPage),
  ];
  await tester.pumpWidget(
    ReadingPreferencesScope(
      preferences: preferences,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: SavedDocumentScreen(
          document: SavedDocument(
            id: 7,
            title: 'Not',
            category: DocumentCategory.note,
            text: text,
            createdAt: DateTime(2024),
          ),
          pageId: 1,
          initialSentence: initialSentence,
          store: _Store(pages),
          speechService: speech,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final scroll = find
      .ancestor(
        of: find.byKey(const ValueKey('saved-reading-text')),
        matching: find.byType(SingleChildScrollView),
      )
      .first;
  return tester.widget<SingleChildScrollView>(scroll).controller!;
}

String get _longText => List.generate(
  30,
  (i) => 'Cümle numarası $i burada yer alıyor ve okunuyor.',
).join('\n\n');

void main() {
  testWidgets('reduced motion moves immediately without disturbing selection', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setFollowSentence(true);
    final speech = FakeSpeechService();
    final scroll = await _show(
      tester,
      text: _longText,
      speech: speech,
      preferences: preferences,
      initialSentence: 20,
      disableAnimations: true,
    );
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('saved-reading-text')),
    );
    const selection = TextSelection(baseOffset: 2, extentOffset: 8);
    field.controller!.selection = selection;
    await tester.tap(find.text('Sesli oku'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    final offset = scroll.offset;
    expect(offset, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(scroll.offset, offset);
    expect(field.controller!.selection, selection);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  for (final newPage in [false, true]) {
    testWidgets('follow works in ${newPage ? 'new page' : 'import'} draft', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final preferences = ReadingPreferences(store: FakePreferencesStore());
      await preferences.load();
      preferences.setFollowSentence(true);
      final speech = FakeSpeechService();
      await tester.pumpWidget(
        ReadingPreferencesScope(
          preferences: preferences,
          child: MaterialApp(
            home: ImageImportScreen(
              pickerService: FakeImagePickerService(),
              speechService: speech,
              onSavePage: newPage ? (_) async {} : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Metin yaz veya yapıştır'));
      final field = find.byKey(
        ValueKey(newPage ? 'new-page-text' : 'import-text'),
      );
      await tester.enterText(field, _longText);
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('content-scroll')),
          )
          .controller!;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Sesli oku'));
      for (var i = 0; i < 15; i++) {
        speech.finishCurrent();
        await tester.pumpAndSettle();
      }
      expect(scroll.offset, greaterThan(0));
      expect(tester.widget<TextField>(field).controller!.text, _longText);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(speech.isSpeaking, isTrue);
    });
  }

  testWidgets('disabled or visible sentence does not move the reader', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    final speech = FakeSpeechService();
    final scroll = await _show(
      tester,
      text: _longText,
      speech: speech,
      preferences: preferences,
      initialSentence: 20,
    );
    await _tap(tester, find.text('Sesli oku'));
    expect(scroll.offset, 0);
    preferences.setFollowSentence(true);
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(speech.isSpeaking, isTrue);
  });

  testWidgets('manual scroll suspends follow; return works while paused', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setFollowSentence(true);
    final speech = FakeSpeechService();
    final scroll = await _show(
      tester,
      text: _longText,
      speech: speech,
      preferences: preferences,
      initialSentence: 20,
    );
    await _tap(tester, find.text('Sesli oku'));
    expect(scroll.offset, greaterThan(0));
    await tester.dragFrom(const Offset(200, 170), const Offset(0, 170));
    await tester.pumpAndSettle();
    expect(find.text('Okunan cümleye dön'), findsOneWidget);
    await _tap(tester, find.text('Duraklat'));
    final pausedOffset = scroll.offset;
    await _tap(tester, find.text('Sonraki cümle'));
    await tester.pump(const Duration(seconds: 1));
    expect(scroll.offset, pausedOffset);
    await _tap(tester, find.text('Okunan cümleye dön'));
    expect(find.text('Okunan cümleye dön'), findsNothing);
    expect(scroll.offset, greaterThan(pausedOffset));
    expect(speech.isSpeaking, isFalse);
    await _tap(tester, find.text('Devam et'));
    expect(speech.isSpeaking, isTrue);
    expect(preferences.followSentence, isTrue);
  });

  testWidgets('a drag interrupts an in-flight automatic scroll', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setFollowSentence(true);
    final speech = FakeSpeechService();
    final scroll = await _show(
      tester,
      text: _longText,
      speech: speech,
      preferences: preferences,
      initialSentence: 20,
    );
    await tester.tap(find.text('Sesli oku'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(scroll.offset, greaterThan(0));
    await tester.dragFrom(const Offset(200, 170), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(find.text('Okunan cümleye dön'), findsOneWidget);
    final afterDrag = scroll.offset;
    await tester.pump(const Duration(seconds: 1));
    expect(scroll.offset, afterDrag);
    expect(speech.isSpeaking, isTrue);
  });

  testWidgets('suspension survives resume and automatic page advance', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setFollowSentence(true);
    preferences.setAutoNextPage(true);
    final speech = FakeSpeechService();
    final scroll = await _show(
      tester,
      text: _longText,
      nextPage: _longText,
      speech: speech,
      preferences: preferences,
      initialSentence: 29,
    );
    await _tap(tester, find.text('Sesli oku'));
    await tester.dragFrom(const Offset(200, 170), const Offset(0, 170));
    await tester.pumpAndSettle();
    expect(find.text('Okunan cümleye dön'), findsOneWidget);
    await _tap(tester, find.text('Duraklat'));
    await _tap(tester, find.text('Devam et'));
    expect(find.text('Okunan cümleye dön'), findsOneWidget);
    speech.finishCurrent();
    await tester.pumpAndSettle();
    expect(speech.spoken.length, 3);
    expect(find.text('Okunan cümleye dön'), findsOneWidget);
    expect(scroll.offset, 0);
    expect(preferences.followSentence, isTrue);
  });

  testWidgets('long sentence aligns its start without repeated movement', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setFollowSentence(true);
    final speech = FakeSpeechService();
    final prefix =
        '${List.generate(15, (i) => 'Önceki cümle $i.').join('\n\n')}\n\n';
    final text = '$prefix${List.filled(350, 'uzun').join(' ')}.';
    final scroll = await _show(
      tester,
      text: text,
      speech: speech,
      preferences: preferences,
      initialSentence: 15,
    );
    await _tap(tester, find.text('Sesli oku'));
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final firstCharacter = editable
        .getBoxesForSelection(
          TextSelection(
            baseOffset: prefix.length,
            extentOffset: prefix.length + 1,
          ),
        )
        .first;
    final y = editable
        .localToGlobal(Offset(firstCharacter.left, firstCharacter.top))
        .dy;
    expect(y, greaterThanOrEqualTo(kToolbarHeight));
    expect(y, lessThan(350));
    final offset = scroll.offset;
    expect(offset, greaterThan(0));
    await tester.pump(const Duration(seconds: 2));
    expect(scroll.offset, offset);
    expect(speech.isSpeaking, isTrue);
  });

  testWidgets('a long sentence already starting in view does not scroll', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setFollowSentence(true);
    final speech = FakeSpeechService();
    final scroll = await _show(
      tester,
      text: '${List.filled(350, 'uzun').join(' ')}.',
      speech: speech,
      preferences: preferences,
    );
    await _tap(tester, find.text('Sesli oku'));
    expect(scroll.offset, 0);
    expect(speech.isSpeaking, isTrue);
  });

  testWidgets(
    'disabled or stopped before a pending frame ignores old requests',
    (tester) async {
      final preferences = ReadingPreferences(store: FakePreferencesStore());
      final speech = FakeSpeechService();
      final scroll = await _show(
        tester,
        text: _longText,
        speech: speech,
        preferences: preferences,
        initialSentence: 20,
      );
      await _tap(tester, find.text('Sesli oku'));
      preferences.setFollowSentence(true);
      preferences.setFollowSentence(false);
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      preferences.setFollowSentence(true);
      await tester.tap(find.text('Durdur'));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(speech.isSpeaking, isFalse);
    },
  );

  testWidgets('a pending request cannot scroll the next manually opened page', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    final speech = FakeSpeechService();
    final scroll = await _show(
      tester,
      text: _longText,
      nextPage: _longText,
      speech: speech,
      preferences: preferences,
      initialSentence: 20,
    );
    await _tap(tester, find.text('Sesli oku'));
    preferences.setFollowSentence(true);
    await tester.tap(find.byKey(const ValueKey('next-page')));
    await tester.pumpAndSettle();
    expect(find.text('Sayfa 2 / 2'), findsOneWidget);
    expect(scroll.offset, 0);
    expect(speech.isSpeaking, isFalse);
  });

  testWidgets('speech failure cancels an active automatic scroll', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setFollowSentence(true);
    final speech = FakeSpeechService();
    final scroll = await _show(
      tester,
      text: _longText,
      speech: speech,
      preferences: preferences,
      initialSentence: 20,
    );
    await tester.tap(find.text('Sesli oku'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(scroll.offset, greaterThan(0));
    speech.failCurrent();
    await tester.pump();
    await tester.pump();
    final afterFailure = scroll.offset;
    await tester.pump(const Duration(seconds: 1));
    expect(scroll.offset, afterFailure);
    expect(speech.isSpeaking, isFalse);
  });

  testWidgets('enabling while paused waits for resume', (tester) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    final speech = FakeSpeechService();
    final scroll = await _show(
      tester,
      text: _longText,
      speech: speech,
      preferences: preferences,
      initialSentence: 20,
    );
    await _tap(tester, find.text('Sesli oku'));
    await _tap(tester, find.text('Duraklat'));
    preferences.setFollowSentence(true);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(speech.isSpeaking, isFalse);
    await _tap(tester, find.text('Devam et'));
    expect(scroll.offset, greaterThan(0));
    expect(speech.isSpeaking, isTrue);
  });

  testWidgets(
    'visible sentence stays still and stopping cancels pending follow',
    (tester) async {
      final preferences = ReadingPreferences(store: FakePreferencesStore());
      await preferences.load();
      preferences.setFollowSentence(true);
      final speech = FakeSpeechService();
      final scroll = await _show(
        tester,
        text: _longText,
        speech: speech,
        preferences: preferences,
      );
      await _tap(tester, find.text('Sesli oku'));
      expect(scroll.offset, 0);
      await _tap(tester, find.text('Durdur'));
      expect(scroll.offset, 0);
      expect(speech.isSpeaking, isFalse);
    },
  );
}

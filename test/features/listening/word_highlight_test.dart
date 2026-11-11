import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';
import 'package:reading_assistant/features/listening/presentation/listening_controller.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';
import 'package:reading_assistant/features/listening/presentation/sentence_highlight.dart';
import 'package:reading_assistant/features/listening/services/sentence_splitter.dart';
import 'package:reading_assistant/features/listening/services/speech_service.dart';

import '../image_import/test_doubles.dart';
import '../library/fake_reading_positions.dart';
import 'fake_preferences_store.dart';
import 'fake_speech_service.dart';

class _Tts extends FlutterTts {
  final List<Completer<dynamic>> calls = [];

  @override
  Future<dynamic> speak(String text, {bool focus = false}) {
    final result = Completer<dynamic>();
    calls.add(result);
    return result.future;
  }

  @override
  Future<dynamic> stop() async => 1;

  void emit(String text, int start, int end, String word) =>
      progressHandler?.call(text, start, end, word);
}

class _PageStore extends DocumentStore with FakeReadingPositions {
  @override
  Future<List<DocumentPage>> pages(int documentId) async => [
    const DocumentPage(id: 1, documentId: 7, position: 0, text: 'Bir iki.'),
    const DocumentPage(id: 2, documentId: 7, position: 1, text: 'Üç dört.'),
  ];
}

Future<void> _start(
  WidgetTester tester,
  ListeningController controller,
  String text,
) async {
  unawaited(controller.start(text));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'source offsets follow repeated words and chunks, without text search',
    (tester) async {
      final speech = FakeSpeechService(
        setup: const SpeechSetup(SpeechAvailability.ready, maxInputLength: 10),
      );
      final listening = ListeningController(speechService: speech);
      addTearDown(listening.dispose);
      await _start(tester, listening, 'Aynı aynı aynı aynı. Son cümle.');
      expect(speech.spoken.first, 'Aynı aynı ');
      speech.progress(5, 9);
      expect(
        listening.wordForText('Aynı aynı aynı aynı. Son cümle.'),
        const SentenceSpan(5, 9),
      );
      final old = speech.progressCallbacks.last!;
      speech.finishCurrent();
      await tester.pump();
      expect(speech.spoken[1], 'aynı aynı.');
      expect(listening.wordProgress.value, isNull);
      speech.progress(5, 9);
      expect(listening.wordProgress.value, const SentenceSpan(15, 19));
      old(0, 4);
      expect(listening.wordProgress.value, const SentenceSpan(15, 19));
      speech.finishCurrent();
      await tester.pump();
      expect(listening.wordProgress.value, isNull);
      expect(listening.currentSentence, 2);
      speech.progress(0, 3);
      expect(listening.wordProgress.value, const SentenceSpan(21, 24));
      expect(listening.wordForText('Başka'), isNull);
    },
  );

  testWidgets(
    'invalid progress falls back to sentence; pause keeps and stop clears word',
    (tester) async {
      final speech = FakeSpeechService();
      final listening = ListeningController(speechService: speech);
      addTearDown(listening.dispose);
      await _start(tester, listening, 'Bir 😀 kelime. İki.');
      expect(listening.wordProgress.value, isNull);
      speech.progress(0, 3);
      expect(listening.wordProgress.value, const SentenceSpan(0, 3));
      speech.progress(5, 6);
      expect(listening.wordProgress.value, isNull);
      expect(listening.sentenceForText('Bir 😀 kelime. İki.'), isNotNull);
      speech.progress(7, 13);
      expect(listening.wordProgress.value, const SentenceSpan(7, 13));
      final old = speech.progressCallbacks.last!;
      await listening.pause();
      expect(listening.wordProgress.value, const SentenceSpan(7, 13));
      old(0, 3);
      expect(listening.wordProgress.value, const SentenceSpan(7, 13));
      await listening.nextSentence();
      expect(listening.wordProgress.value, isNull);
      await listening.resume();
      await tester.pump();
      old(0, 3);
      expect(listening.wordProgress.value, isNull);
      speech.progress(0, 3);
      expect(listening.wordProgress.value, const SentenceSpan(15, 18));
      await listening.stop();
      expect(listening.wordProgress.value, isNull);
    },
  );

  testWidgets(
    'real plugin callback rejects stale identical utterances and invalid events',
    (tester) async {
      final tts = _Tts();
      final service = SpeechService(tts: tts);
      addTearDown(service.dispose);
      final progress = <(int, int)>[];
      final first = service.speak(
        'Benzersiz-test kelime',
        onProgress: (a, b) => progress.add((a, b)),
      );
      tts.emit('Benzersiz-test kelime', 0, 14, 'Benzersiz-test');
      expect(progress, [(0, 14)]);
      tts.emit('Benzersiz-test kelime', 0, 21, 'Benzersiz-test kelime');
      tts.emit('Benzersiz-test kelime', 15, 21, 'yanlış');
      expect(progress, [(0, 14), (-1, -1), (-1, -1)]);
      await service.stop();
      expect(await first, SpeechOutcome.stopped);
      final second = service.speak(
        'Benzersiz-test kelime',
        onProgress: (a, b) => progress.add((a, b)),
      );
      tts.emit('Benzersiz-test kelime', 15, 21, 'kelime');
      expect(progress.length, 3);
      tts.calls.last.complete(1);
      expect(await second, SpeechOutcome.completed);
      final third = service.speak(
        'Başka-benzersiz kelime',
        onProgress: (a, b) => progress.add((a, b)),
      );
      tts.emit('Benzersiz-test kelime', 0, 14, 'Benzersiz-test');
      tts.emit('Başka-benzersiz kelime', 0, 15, 'Başka-benzersiz');
      expect(progress.last, (0, 15));
      expect(progress.length, 4);
      tts.calls.last.complete(1);
      await third;
      final otherTts = _Tts();
      final otherService = SpeechService(tts: otherTts);
      addTearDown(otherService.dispose);
      final repeated = otherService.speak(
        'Başka-benzersiz kelime',
        onProgress: (a, b) => progress.add((a, b)),
      );
      otherTts.emit('Başka-benzersiz kelime', 0, 15, 'Başka-benzersiz');
      expect(progress.length, 4);
      otherTts.calls.last.complete(1);
      await repeated;
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'word and sentence rendering preserve selection in $brightness',
      (tester) async {
        final speech = FakeSpeechService();
        final listening = ListeningController(speechService: speech);
        final controller =
            HighlightingTextEditingController(neutralReading: true)
              ..text = 'Aynı aynı.'
              ..attachListening(listening);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(body: TextField(controller: controller)),
          ),
        );
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 4,
        );
        await _start(tester, listening, controller.text);
        speech.progress(5, 9);
        await tester.pump();
        final context = tester.element(find.byType(TextField));
        final span = controller.buildTextSpan(
          context: context,
          style: Theme.of(context).textTheme.bodyLarge,
          withComposing: false,
        );
        final pieces = span.children!.cast<TextSpan>();
        expect(pieces.map((p) => p.text).join(), 'Aynı aynı.');
        expect(
          pieces.first.style!.backgroundColor,
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
        );
        expect(pieces[1].text, 'aynı');
        final yellow = pieces[1].style!.backgroundColor!;
        expect(yellow, Colors.amber.withValues(alpha: 0.24));
        final foreground = Theme.of(context).textTheme.bodyLarge!.color!;
        final background = Color.alphaBlend(
          yellow,
          Theme.of(context).colorScheme.surface,
        );
        final a = foreground.computeLuminance() + 0.05;
        final b = background.computeLuminance() + 0.05;
        expect(a > b ? a / b : b / a, greaterThanOrEqualTo(4.5));
        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 4),
        );
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        listening.dispose();
      },
    );
  }

  for (final newPage in [false, true]) {
    testWidgets(
      'word progress highlights ${newPage ? 'new page' : 'import'} draft without changing text',
      (tester) async {
        final speech = FakeSpeechService();
        await tester.pumpWidget(
          ReadingPreferencesScope(
            preferences: ReadingPreferences(store: FakePreferencesStore()),
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
        await tester.tap(find.text('Metin yaz veya yapıştır'));
        await tester.pumpAndSettle();
        final field = find.byKey(
          ValueKey(newPage ? 'new-page-text' : 'import-text'),
        );
        await tester.enterText(field, 'Bir iki iki.');
        FocusManager.instance.primaryFocus?.unfocus();
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sesli oku'));
        await tester.pump();
        await tester.pump();
        speech.progress(8, 11);
        await tester.pump();
        final controller = tester.widget<TextField>(field).controller!;
        final span = controller.buildTextSpan(
          context: tester.element(field),
          style: const TextStyle(),
          withComposing: false,
        );
        expect(span.toPlainText(), 'Bir iki iki.');
        expect(
          span.children!
              .cast<TextSpan>()
              .where(
                (s) =>
                    s.style?.backgroundColor ==
                    Colors.amber.withValues(alpha: 0.24),
              )
              .single
              .text,
          'iki',
        );
      },
    );
  }

  testWidgets('saved reader shows progress for the current text', (
    tester,
  ) async {
    final speech = FakeSpeechService();
    await tester.pumpWidget(
      ReadingPreferencesScope(
        preferences: ReadingPreferences(store: FakePreferencesStore()),
        child: MaterialApp(
          home: SavedDocumentScreen(
            document: SavedDocument(
              id: 1,
              title: 'Not',
              category: DocumentCategory.note,
              text: 'Bir iki.',
              createdAt: DateTime(2024),
            ),
            speechService: speech,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sesli oku'));
    await tester.pump();
    await tester.pump();
    speech.progress(4, 7);
    await tester.pump();
    final field = find.byKey(const ValueKey('saved-reading-text'));
    final controller = tester.widget<TextField>(field).controller!;
    final span = controller.buildTextSpan(
      context: tester.element(field),
      style: const TextStyle(),
      withComposing: false,
    );
    expect(
      span.children!
          .cast<TextSpan>()
          .where(
            (s) =>
                s.style?.backgroundColor ==
                Colors.amber.withValues(alpha: 0.24),
          )
          .single
          .text,
      'iki',
    );
  });

  testWidgets(
    'automatic page advance clears stale word and uses new page offsets',
    (tester) async {
      final speech = FakeSpeechService();
      final preferences = ReadingPreferences(store: FakePreferencesStore());
      await preferences.load();
      preferences.setAutoNextPage(true);
      await tester.pumpWidget(
        ReadingPreferencesScope(
          preferences: preferences,
          child: MaterialApp(
            home: SavedDocumentScreen(
              document: SavedDocument(
                id: 7,
                title: 'Not',
                category: DocumentCategory.note,
                text: 'Bir iki.',
                createdAt: DateTime(2024),
              ),
              pageId: 1,
              store: _PageStore(),
              speechService: speech,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sesli oku'));
      await tester.pump();
      await tester.pump();
      speech.progress(4, 7);
      await tester.pump();
      final old = speech.progressCallbacks.last!;
      speech.finishCurrent();
      await tester.pumpAndSettle();
      expect(speech.spoken.last, 'Üç dört.');
      final field = find.byKey(const ValueKey('saved-reading-text'));
      final controller = tester.widget<TextField>(field).controller!;
      TextSpan current() => controller.buildTextSpan(
        context: tester.element(field),
        style: const TextStyle(),
        withComposing: false,
      );
      old(4, 7);
      await tester.pump();
      expect(
        current().children!.cast<TextSpan>().where(
          (s) =>
              s.style?.backgroundColor == Colors.amber.withValues(alpha: 0.24),
        ),
        isEmpty,
      );
      speech.progress(3, 7);
      await tester.pump();
      expect(
        current().children!
            .cast<TextSpan>()
            .where(
              (s) =>
                  s.style?.backgroundColor ==
                  Colors.amber.withValues(alpha: 0.24),
            )
            .single
            .text,
        'dört',
      );
    },
  );
}

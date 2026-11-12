import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';
import 'package:reading_assistant/features/listening/presentation/listening_controller.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';

import '../image_import/test_doubles.dart';
import '../library/fake_reading_positions.dart';
import 'fake_preferences_store.dart';
import 'fake_speech_service.dart';

class _PageStore extends DocumentStore with FakeReadingPositions {
  @override
  Future<List<DocumentPage>> pages(int documentId) async => [
    DocumentPage(id: 1, documentId: documentId, position: 0, text: 'Bir.'),
    DocumentPage(id: 2, documentId: documentId, position: 3, text: 'İki.'),
  ];
}

Widget _app(ReadingPreferences preferences, Widget child) =>
    ReadingPreferencesScope(
      preferences: preferences,
      child: MaterialApp(home: child),
    );

Widget _import(FakeSpeechService speech, {bool newPage = false}) =>
    ImageImportScreen(
      pickerService: FakeImagePickerService(),
      speechService: speech,
      onSavePage: newPage ? (_) async {} : null,
    );

Future<void> _createText(WidgetTester tester) async {
  await tester.tap(find.text('Metin yaz veya yapıştır'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('import-text')), 'Bir.');
  FocusManager.instance.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'edit appearance settings preserve draft and do not mark it dirty',
    (tester) async {
      final preferences = ReadingPreferences(store: FakePreferencesStore());
      await preferences.load();
      await tester.pumpWidget(
        _app(
          preferences,
          SavedDocumentScreen(
            document: SavedDocument(
              id: 7,
              title: 'Not',
              category: DocumentCategory.note,
              text: 'Bir iki.',
              createdAt: DateTime(2024),
            ),
            store: _PageStore(),
            speechService: FakeSpeechService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Düzenle'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Görünüm'));
      await tester.pumpAndSettle();
      expect(find.text('Görünüm'), findsOneWidget);
      expect(find.text('Yazı boyutu'), findsOneWidget);
      expect(find.text('Metin hizalaması'), findsOneWidget);
      expect(find.text('Okuma hızı'), findsNothing);
      expect(find.byKey(const ValueKey('auto-next-page')), findsNothing);
      expect(find.byKey(const ValueKey('follow-sentence')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('reading-text-size')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Büyük').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reading-text-alignment')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ortaya').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();
      final edit = find.descendant(
        of: find.byKey(const ValueKey('document-text')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(edit).style!.fontSize, 20);
      expect(tester.widget<TextField>(edit).textAlign, TextAlign.center);
      await tester.tap(find.text('Düzenlemekten vazgeç'));
      await tester.pumpAndSettle();
      expect(find.text('Kaydedilmemiş değişiklikler var'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('saved-reading-text')))
            .textAlign,
        TextAlign.center,
      );
      await tester.tap(find.byTooltip('Düzenle'));
      await tester.pumpAndSettle();
      await tester.enterText(edit, 'Korunan taslak.');
      final controller = tester.widget<TextField>(edit).controller!;
      const selection = TextSelection(baseOffset: 2, extentOffset: 7);
      controller.selection = selection;
      await tester.pump();
      await tester.tap(find.byTooltip('Görünüm'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reading-text-alignment')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sağa').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Korunan taslak.');
      expect(controller.selection, selection);
      expect(tester.widget<TextField>(edit).textAlign, TextAlign.right);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.text('Düzenlemekten vazgeç'));
      await tester.pumpAndSettle();
      expect(find.text('Kaydedilmemiş değişiklikler var'), findsOneWidget);
    },
  );

  testWidgets('text size applies immediately without restarting speech', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    final speech = FakeSpeechService();
    final store = _PageStore();
    await tester.pumpWidget(
      _app(
        preferences,
        SavedDocumentScreen(
          document: SavedDocument(
            id: 7,
            title: 'Not',
            category: DocumentCategory.note,
            text: 'Bir.',
            createdAt: DateTime(2024),
          ),
          pageId: 1,
          store: store,
          speechService: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('saved-reading-text'));
    final originalSize = tester.widget<TextField>(field).style!.fontSize!;
    expect(originalSize, 16);
    await tester.tap(find.text('Sesli oku'));
    await tester.pumpAndSettle();
    speech.progress(0, 3);
    await tester.pumpAndSettle();
    expect(store.positionWrites, 1);
    final stopCalls = speech.stopCalls;
    await tester.tap(find.byTooltip('Görünüm ve sesli okuma'));
    await tester.pumpAndSettle();
    expect(find.text('Normal'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reading-text-size')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Çok büyük').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('reading-text-alignment')),
    );
    await tester.tap(find.byKey(const ValueKey('reading-text-alignment')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('İki yana').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).style!.fontSize, originalSize * 1.5);
    expect(tester.widget<TextField>(field).textAlign, TextAlign.justify);
    expect(speech.spoken, ['Bir.']);
    expect(speech.stopCalls, stopCalls);
    expect(speech.isSpeaking, isTrue);
    expect(store.positionWrites, 1);
    final span =
        tester
                .state<EditableTextState>(find.byType(EditableText).first)
                .renderEditable
                .text!
            as TextSpan;
    expect(span.toPlainText(), 'Bir.');
    expect(span.children![0].toPlainText(), 'Bir');
    expect(
      (span.children![0] as TextSpan).style!.backgroundColor,
      Colors.amber.withValues(alpha: 0.24),
    );
    expect(span.children![1].toPlainText(), '.');
    expect((span.children![1] as TextSpan).style!.backgroundColor, isNotNull);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Durdur'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Düzenle'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('document-text')),
              matching: find.byType(TextField),
            ),
          )
          .style!
          .fontSize,
      originalSize * 1.5,
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('document-text')),
              matching: find.byType(TextField),
            ),
          )
          .textAlign,
      TextAlign.justify,
    );
  });

  for (final newPage in [false, true]) {
    testWidgets(
      'text size persists through draft playback states (${newPage ? 'new page' : 'home'})',
      (tester) async {
        final store = FakePreferencesStore();
        final preferences = ReadingPreferences(store: store);
        final speech = FakeSpeechService();
        await preferences.load();
        await tester.pumpWidget(
          _app(preferences, _import(speech, newPage: newPage)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Metin yaz veya yapıştır'));
        await tester.pumpAndSettle();
        final field = find.byKey(
          ValueKey(newPage ? 'new-page-text' : 'import-text'),
        );
        await tester.enterText(field, 'Bir iki.');
        await tester.pumpAndSettle();
        final controller = tester.widget<TextField>(field).controller!;
        controller.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 4,
        );
        await tester.pump();
        final selection = controller.selection;
        final focus = FocusManager.instance.primaryFocus;
        expect(focus?.hasFocus, isTrue);
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        final baseSize = editable.renderEditable.text!.style!.fontSize!;
        expect(baseSize, 16);
        expect(tester.widget<TextField>(field).textAlign, TextAlign.start);
        preferences.setTextSize(ReadingTextSize.large);
        preferences.setTextAlignment(ReadingTextAlignment.center);
        await tester.pumpAndSettle();
        expect(editable.renderEditable.text!.style!.fontSize, baseSize * 1.25);
        expect(tester.widget<TextField>(field).textAlign, TextAlign.center);
        expect(controller.selection, selection);
        expect(controller.text, 'Bir iki.');
        expect(FocusManager.instance.primaryFocus, same(focus));
        expect(tester.testTextInput.isVisible, isTrue);

        FocusManager.instance.primaryFocus?.unfocus();
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sesli oku'));
        await tester.pumpAndSettle();
        speech.progress(0, 3);
        await tester.pumpAndSettle();
        final stopCalls = speech.stopCalls;
        preferences.setTextSize(ReadingTextSize.extraLarge);
        preferences.setTextAlignment(ReadingTextAlignment.right);
        await tester.pumpAndSettle();
        expect(editable.renderEditable.text!.style!.fontSize, baseSize * 1.5);
        expect(tester.widget<TextField>(field).textAlign, TextAlign.right);
        expect(speech.spoken, ['Bir iki.']);
        expect(speech.stopCalls, stopCalls);
        expect(speech.isSpeaking, isTrue);
        final span = editable.renderEditable.text! as TextSpan;
        expect(span.children![0].toPlainText(), 'Bir');
        expect(
          (span.children![0] as TextSpan).style!.backgroundColor,
          Colors.amber.withValues(alpha: 0.24),
        );
        expect(
          (span.children![1] as TextSpan).style!.backgroundColor,
          isNotNull,
        );
        await tester.tap(find.text('Duraklat'));
        await tester.pumpAndSettle();
        expect(editable.renderEditable.text!.style!.fontSize, baseSize * 1.5);
        expect(tester.widget<TextField>(field).textAlign, TextAlign.right);
        await tester.tap(find.text('Devam et'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Durdur'));
        await tester.pumpAndSettle();
        expect(editable.renderEditable.text!.style!.fontSize, baseSize * 1.5);
        expect(tester.widget<TextField>(field).textAlign, TextAlign.right);
        expect(controller.text, 'Bir iki.');
        await tester.tap(find.text('Sesli oku'));
        await tester.pumpAndSettle();
        speech.finishCurrent();
        await tester.pumpAndSettle();
        expect(editable.renderEditable.text!.style!.fontSize, baseSize * 1.5);
        expect(tester.widget<TextField>(field).textAlign, TextAlign.right);
        expect(controller.text, 'Bir iki.');

        await preferences.pendingWrites;
        final reopened = ReadingPreferences(store: store);
        await reopened.load();
        expect(reopened.textSize, ReadingTextSize.extraLarge);
        expect(reopened.textAlignment, ReadingTextAlignment.right);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          _app(reopened, _import(FakeSpeechService(), newPage: newPage)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Metin yaz veya yapıştır'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).style!.fontSize, baseSize * 1.5);
        expect(tester.widget<TextField>(field).textAlign, TextAlign.right);
      },
    );

    testWidgets(
      'large system scale keeps draft scrollable (${newPage ? 'new page' : 'home'})',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final preferences = ReadingPreferences(store: FakePreferencesStore());
        await preferences.load();
        preferences.setTextSize(ReadingTextSize.extraLarge);
        await tester.pumpWidget(
          ReadingPreferencesScope(
            preferences: preferences,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.7)),
                child: child!,
              ),
              home: _import(FakeSpeechService(), newPage: newPage),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final create = find.text('Metin yaz veya yapıştır');
        await tester.ensureVisible(create);
        await tester.pumpAndSettle();
        expect(create.hitTestable(), findsOneWidget);
        await tester.tap(create);
        await tester.pumpAndSettle();
        final field = find.byKey(
          ValueKey(newPage ? 'new-page-text' : 'import-text'),
        );
        await tester.enterText(
          field,
          List.filled(30, 'Uzun metin burada okunur.').join('\n\n'),
        );
        FocusManager.instance.primaryFocus?.unfocus();
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        final render = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        expect(render.text!.style!.fontSize, 24);
        expect(render.textScaler.scale(24), closeTo(40.8, 0.001));
        final scroll = tester
            .widget<SingleChildScrollView>(
              find.byKey(const ValueKey('content-scroll')),
            )
            .controller!;
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.dragFrom(const Offset(160, 300), const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(0));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('large system text scale and narrow reader remain scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setTextSize(ReadingTextSize.extraLarge);
    final text = List.filled(30, 'Uzun metin burada okunur.').join('\n\n');
    await tester.pumpWidget(
      ReadingPreferencesScope(
        preferences: preferences,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
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
            store: _PageStore(),
            speechService: FakeSpeechService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('saved-reading-text'));
    expect(tester.widget<TextField>(field).style!.fontSize, 24);
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(editable.textScaler.scale(24), 48);
    final scroll = tester
        .widget<SingleChildScrollView>(
          find
              .ancestor(of: field, matching: find.byType(SingleChildScrollView))
              .first,
        )
        .controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await tester.dragFrom(const Offset(160, 300), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    await tester.tap(find.byTooltip('Görünüm ve sesli okuma'));
    await tester.pumpAndSettle();
    expect(find.text('Yazı boyutu'), findsOneWidget);
    expect(find.text('Çok büyük'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('appearance and speech settings remain usable at large scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    await tester.pumpWidget(
      _app(
        preferences,
        SavedDocumentScreen(
          document: SavedDocument(
            id: 7,
            title: 'Not',
            category: DocumentCategory.note,
            text: 'Bir iki.',
            createdAt: DateTime(2024),
          ),
          pageId: 1,
          store: _PageStore(),
          speechService: FakeSpeechService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> tapVisible(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      expect(finder.hitTestable(), findsOneWidget);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tapVisible(find.byTooltip('Görünüm ve sesli okuma'));
    await tapVisible(find.byKey(const ValueKey('reading-text-size')));
    await tapVisible(find.text('Çok büyük').last);
    await tapVisible(find.byKey(const ValueKey('reading-text-alignment')));
    await tapVisible(find.text('İki yana').last);
    await tapVisible(find.byKey(const ValueKey('reading-speed')));
    await tapVisible(find.text('1.25×').last);
    await tapVisible(find.byKey(const ValueKey('follow-sentence')));
    await tapVisible(find.byKey(const ValueKey('auto-next-page')));
    await tapVisible(find.text('Kapat'));
    expect(preferences.textSize, ReadingTextSize.extraLarge);
    expect(preferences.textAlignment, ReadingTextAlignment.justify);
    expect(preferences.speed, ReadingSpeed.fast);
    expect(preferences.followSentence, isTrue);
    expect(preferences.autoNextPage, isTrue);
    await tapVisible(find.byTooltip('Düzenle'));
    await tapVisible(find.byTooltip('Görünüm'));
    await tapVisible(find.byKey(const ValueKey('reading-text-alignment')));
    await tapVisible(find.text('Sola').last);
    await tapVisible(find.text('Kapat'));
    expect(preferences.textAlignment, ReadingTextAlignment.start);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first playback waits for loaded speed without starting itself', (
    tester,
  ) async {
    final store = FakePreferencesStore()
      ..values = {'speed': 'faster', 'auto_next_page': 1}
      ..loadGate = Completer<void>();
    final preferences = ReadingPreferences(store: store);
    final speech = FakeSpeechService();
    await tester.pumpWidget(_app(preferences, _import(speech)));
    await _createText(tester);
    final readButton = find.ancestor(
      of: find.text('Sesli oku'),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(readButton).onPressed, isNull);
    expect(store.saveCalls, 0);
    expect(speech.spoken, isEmpty);
    store.loadGate!.complete();
    await tester.pumpAndSettle();
    expect(speech.spoken, isEmpty);
    await tester.tap(readButton);
    await tester.pump();
    await tester.pump();
    expect(speech.spokenRates, [1.5]);
  });

  testWidgets('shared settings apply to import, new page and saved reader', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    final speech = FakeSpeechService();
    await tester.pumpWidget(_app(preferences, _import(speech)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Görünüm ve sesli okuma'));
    await tester.pumpAndSettle();
    expect(find.text('Sonraki sayfayı otomatik oku'), findsNothing);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('follow-sentence')))
          .value,
      isFalse,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('follow-sentence')));
    await tester.tap(find.byKey(const ValueKey('follow-sentence')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reading-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.25×').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('reading-text-size')));
    await tester.tap(find.byKey(const ValueKey('reading-text-size')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Büyük').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    expect(preferences.speed, ReadingSpeed.fast);
    expect(preferences.textSize, ReadingTextSize.large);

    await tester.pumpWidget(_app(preferences, _import(speech, newPage: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Görünüm ve sesli okuma'));
    await tester.pumpAndSettle();
    expect(find.text('1.25×'), findsOneWidget);
    expect(find.text('Büyük'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('follow-sentence')))
          .value,
      isTrue,
    );
    expect(find.text('Sonraki sayfayı otomatik oku'), findsNothing);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _app(
        preferences,
        SavedDocumentScreen(
          document: SavedDocument(
            id: 7,
            title: 'Not',
            category: DocumentCategory.note,
            text: 'Bir.',
            createdAt: DateTime(2024),
          ),
          pageId: 1,
          pageNumber: 1,
          store: _PageStore(),
          speechService: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Görünüm ve sesli okuma'));
    await tester.pumpAndSettle();
    expect(find.text('1.25×'), findsOneWidget);
    expect(find.text('Büyük'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('follow-sentence')))
          .value,
      isTrue,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('auto-next-page')));
    await tester.tap(find.byKey(const ValueKey('auto-next-page')));
    await tester.pumpAndSettle();
    expect(preferences.autoNextPage, isTrue);
    expect(speech.spoken, isEmpty);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sesli oku'));
    await tester.pump();
    await tester.pump();
    expect(speech.spokenRates, [1.25]);
  });

  testWidgets('save error is reported without stopping playback', (
    tester,
  ) async {
    final store = FakePreferencesStore()..saveError = StateError('save');
    final preferences = ReadingPreferences(store: store);
    final speech = FakeSpeechService();
    await tester.pumpWidget(_app(preferences, _import(speech)));
    await tester.pumpAndSettle();
    await _createText(tester);
    await tester.tap(find.text('Sesli oku'));
    await tester.pump();
    await tester.pump();
    preferences.setFollowSentence(true);
    await preferences.pendingWrites;
    await tester.pump();
    await tester.pump();
    expect(find.text('Okuma tercihleri kalıcı kaydedilemedi.'), findsOneWidget);
    expect(speech.isSpeaking, isTrue);
    expect(preferences.followSentence, isTrue);
  });

  testWidgets('older live screen adopts changes made on a pushed reader', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    final speech = FakeSpeechService();
    await tester.pumpWidget(_app(preferences, _import(speech)));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ImageImportScreen));
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SavedDocumentScreen(
          document: SavedDocument(
            id: 7,
            title: 'Not',
            category: DocumentCategory.note,
            text: 'Bir.',
            createdAt: DateTime(2024),
          ),
          pageId: 1,
          pageNumber: 1,
          store: _PageStore(),
          speechService: FakeSpeechService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Görünüm ve sesli okuma'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reading-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0.75×').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('auto-next-page')));
    await tester.tap(find.byKey(const ValueKey('auto-next-page')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(SavedDocumentScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Görünüm ve sesli okuma'));
    await tester.pumpAndSettle();
    expect(find.text('0.75×'), findsOneWidget);
    expect(find.text('Sonraki sayfayı otomatik oku'), findsNothing);
    expect(preferences.autoNextPage, isTrue);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    await _createText(tester);
    await tester.tap(find.text('Sesli oku'));
    await tester.pump();
    await tester.pump();
    expect(speech.spokenRates, [0.75]);
  });

  testWidgets('failure in settings is shown after closing the dialog', (
    tester,
  ) async {
    final store = FakePreferencesStore()..saveError = StateError('save');
    final preferences = ReadingPreferences(store: store);
    await tester.pumpWidget(_app(preferences, _import(FakeSpeechService())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Görünüm ve sesli okuma'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reading-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5×').last);
    await tester.pumpAndSettle();
    await preferences.pendingWrites;
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    expect(find.text('Okuma tercihleri kalıcı kaydedilemedi.'), findsOneWidget);
    expect(preferences.speed, ReadingSpeed.faster);
  });
}

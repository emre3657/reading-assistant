import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/add_page_screen.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';
import 'package:reading_assistant/features/listening/presentation/listening_controller.dart';
import 'package:reading_assistant/features/listening/presentation/sentence_highlight.dart';

import '../image_import/test_doubles.dart';
import '../library/fake_reading_positions.dart';
import 'fake_preferences_store.dart';
import 'fake_speech_service.dart';

class _Store extends DocumentStore with FakeReadingPositions {
  final pagesList = [
    const DocumentPage(id: 1, documentId: 7, position: 0, text: 'Aynı. Aynı.'),
    const DocumentPage(id: 2, documentId: 7, position: 5, text: 'Son sayfa.'),
  ];
  int? savedOwner;
  String? savedText;

  @override
  Future<List<DocumentPage>> pages(int documentId) async => pagesList;

  @override
  Future<DocumentPage> appendPage({
    required int documentId,
    required String text,
  }) async {
    savedOwner = documentId;
    savedText = text;
    return DocumentPage(id: 3, documentId: documentId, position: 6, text: text);
  }
}

Widget _app(Widget child, {Brightness brightness = Brightness.light}) =>
    ReadingPreferencesScope(
      preferences: ReadingPreferences(store: FakePreferencesStore()),
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: child,
      ),
    );

List<(int, int, String)> _highlighted(TextSpan span) {
  final ranges = <(int, int, String)>[];
  var offset = 0;
  void visit(InlineSpan item, bool inheritedHighlight) {
    if (item is! TextSpan) return;
    final highlighted =
        item.style?.backgroundColor != null || inheritedHighlight;
    final text = item.text ?? '';
    if (highlighted && text.isNotEmpty) {
      ranges.add((offset, offset + text.length, text));
    }
    offset += text.length;
    for (final child in item.children ?? <InlineSpan>[]) {
      visit(child, highlighted);
    }
  }

  visit(span, false);
  return ranges;
}

TextSpan _editableSpan(WidgetTester tester) =>
    tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable
            .text!
        as TextSpan;

TextSpan _savedSpan(WidgetTester tester) => _editableSpan(tester);

Future<void> _tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump();
}

SavedDocument _document() => SavedDocument(
  id: 7,
  title: 'Kitap',
  category: DocumentCategory.book,
  text: 'Aynı. Aynı.',
  createdAt: DateTime(2024),
);

void main() {
  testWidgets('stale text has no highlight and composing is preserved', (
    tester,
  ) async {
    final speech = FakeSpeechService();
    final listening = ListeningController(speechService: speech);
    final controller = HighlightingTextEditingController()
      ..attachListening(listening)
      ..value = const TextEditingValue(
        text: 'Bir. İki.',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );
    unawaited(listening.start(controller.text));
    await tester.pump();
    await tester.pump();
    final context = tester.element(find.byType(TextField));
    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(fontSize: 20),
      withComposing: true,
    );
    expect(_highlighted(span), [(0, 3, 'Bir'), (3, 4, '.')]);
    expect(span.children!.first.style!.decoration, TextDecoration.underline);
    expect(span.toPlainText(), 'Bir. İki.');
    controller.text = 'Başka metin.';
    await tester.pump();
    expect(_highlighted(_editableSpan(tester)), isEmpty);
    expect(listening.sentenceForText(controller.text), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    listening.dispose();
  });

  testWidgets('saved text selection survives sentence highlight updates', (
    tester,
  ) async {
    final speech = FakeSpeechService();
    await tester.pumpWidget(
      _app(
        SavedDocumentScreen(
          document: _document(),
          pageId: 1,
          store: _Store(),
          speechService: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, 'Sesli oku');
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('saved-reading-text')),
    );
    expect(field.readOnly, isTrue);
    field.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 4,
    );
    await tester.pump();
    speech.finishCurrent();
    await tester.pumpAndSettle();
    expect(_highlighted(_savedSpan(tester)), [(6, 11, 'Aynı.')]);
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('highlight retains readable contrast in light and dark themes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final speech = FakeSpeechService();
      await tester.pumpWidget(
        _app(
          SavedDocumentScreen(
            document: _document(),
            pageId: 1,
            store: _Store(),
            speechService: speech,
          ),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'Sesli oku');
      final span = _savedSpan(tester);
      final highlight = span.children!.whereType<TextSpan>().firstWhere(
        (child) => child.style?.backgroundColor != null,
      );
      final theme = Theme.of(
        tester.element(find.byKey(const ValueKey('saved-reading-text'))),
      );
      final background = Color.alphaBlend(
        highlight.style!.backgroundColor!,
        theme.colorScheme.surface,
      );
      final foreground = theme.textTheme.bodyLarge!.color!;
      final contrast =
          (foreground.computeLuminance() + 0.05) /
          (background.computeLuminance() + 0.05);
      expect(contrast > 1 ? contrast : 1 / contrast, greaterThanOrEqualTo(4.5));
      expect(highlight.style!.color, isNull);
      expect(highlight.style!.fontWeight, isNull);
      expect(highlight.style!.fontSize, isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('manual and pasted draft highlights exact repeated sentence, '
      'pause and navigation; stop preserves draft without keyboard', (
    tester,
  ) async {
    final speech = FakeSpeechService();
    await tester.pumpWidget(
      _app(
        ImageImportScreen(
          pickerService: FakeImagePickerService(),
          speechService: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, 'Metin yaz veya yapıştır');
    final field = find.byKey(const ValueKey('import-text'));
    await tester.enterText(field, 'Aynı. ');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, Object>{'text': 'Aynı.'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    final paste = state.pasteText(SelectionChangedCause.toolbar);
    await tester.pump();
    await paste;
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'Aynı. Aynı.');
    await _tap(tester, 'Sesli oku');
    expect(_highlighted(_editableSpan(tester)), [(0, 5, 'Aynı.')]);
    await _tap(tester, 'Sonraki cümle');
    expect(_highlighted(_editableSpan(tester)), [(6, 11, 'Aynı.')]);
    await _tap(tester, 'Duraklat');
    expect(_highlighted(_editableSpan(tester)), [(6, 11, 'Aynı.')]);
    await _tap(tester, 'Önceki cümle');
    expect(_highlighted(_editableSpan(tester)), [(0, 5, 'Aynı.')]);
    await _tap(tester, 'Başa dön');
    expect(_highlighted(_editableSpan(tester)), [(0, 5, 'Aynı.')]);
    await _tap(tester, 'Durdur');
    expect(_highlighted(_editableSpan(tester)), isEmpty);
    expect(tester.widget<TextField>(field).controller!.text, 'Aynı. Aynı.');
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.widget<TextField>(field).readOnly, isFalse);
  });

  testWidgets('OCR draft is highlighted and natural end clears it', (
    tester,
  ) async {
    final speech = FakeSpeechService();
    await tester.pumpWidget(
      _app(
        ImageImportScreen(
          pickerService: FakeImagePickerService(
            onPick: () async => XFile('/a'),
          ),
          textRecognitionService: FakeTextRecognitionService(
            (_) async => 'Bir. İki.',
          ),
          previewImageBuilder: (_) => ControlledImageProvider(),
          speechService: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, 'Galeriden görsel seç');
    await _tap(tester, 'Metni çıkar');
    await _tap(tester, 'Sesli oku');
    expect(_highlighted(_editableSpan(tester)), [(0, 4, 'Bir.')]);
    speech.finishCurrent();
    await tester.pumpAndSettle();
    expect(_highlighted(_editableSpan(tester)), [(5, 9, 'İki.')]);
    speech.finishCurrent();
    await tester.pumpAndSettle();
    expect(_highlighted(_editableSpan(tester)), isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('import-text')))
          .controller!
          .text,
      'Bir. İki.',
    );
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets(
    'new page reads and highlights edited draft and saves it to owner',
    (tester) async {
      final store = _Store();
      final speech = FakeSpeechService();
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => AddPageScreen(
                      documentId: 7,
                      documentTitle: 'Kitap',
                      store: store,
                      pickerService: FakeImagePickerService(),
                      speechService: speech,
                    ),
                  ),
                ),
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      );
      await _tap(tester, 'Aç');
      await _tap(tester, 'Metin yaz veya yapıştır');
      final field = find.byKey(const ValueKey('new-page-text'));
      await tester.enterText(field, 'Taslak. Yeni.');
      await tester.pumpAndSettle();
      await _tap(tester, 'Sesli oku');
      expect(_highlighted(_editableSpan(tester)), [(0, 7, 'Taslak.')]);
      expect(speech.spoken.first, 'Taslak. ');
      await _tap(tester, 'Durdur');
      expect(_highlighted(_editableSpan(tester)), isEmpty);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byKey(const ValueKey('save-page')));
      await tester.pumpAndSettle();
      expect(store.savedOwner, 7);
      expect(store.savedText, 'Taslak. Yeni.');
    },
  );

  testWidgets(
    'saved resume, manual navigation and speech failure clear old ranges',
    (tester) async {
      final store = _Store();
      final speech = FakeSpeechService();
      await tester.pumpWidget(
        _app(
          SavedDocumentScreen(
            document: _document(),
            pageId: 1,
            initialSentence: 1,
            store: store,
            speechService: speech,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_highlighted(_savedSpan(tester)), isEmpty);
      await _tap(tester, 'Sesli oku');
      expect(_highlighted(_savedSpan(tester)), [(6, 11, 'Aynı.')]);
      expect(speech.spoken.single, 'Aynı.');
      await tester.tap(find.byKey(const ValueKey('next-page')));
      await tester.pumpAndSettle();
      expect(_highlighted(_savedSpan(tester)), isEmpty);
      expect(speech.spoken, hasLength(1));
      await _tap(tester, 'Sesli oku');
      expect(_highlighted(_savedSpan(tester)), [(0, 10, 'Son sayfa.')]);
      speech.failCurrent();
      await tester.pumpAndSettle();
      expect(_highlighted(_savedSpan(tester)), isEmpty);
    },
  );

  testWidgets('automatic next page changes highlight with the spoken text', (
    tester,
  ) async {
    final store = _Store();
    final speech = FakeSpeechService();
    await tester.pumpWidget(
      _app(
        SavedDocumentScreen(
          document: _document(),
          pageId: 1,
          store: store,
          speechService: speech,
        ),
        brightness: Brightness.dark,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Okuma ayarları'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auto-next-page')));
    await tester.pumpAndSettle();
    await _tap(tester, 'Kapat');
    await _tap(tester, 'Sesli oku');
    expect(_highlighted(_savedSpan(tester)), [(0, 5, 'Aynı.')]);
    speech.finishCurrent();
    await tester.pumpAndSettle();
    expect(_highlighted(_savedSpan(tester)), [(6, 11, 'Aynı.')]);
    speech.finishCurrent();
    await tester.pumpAndSettle();
    expect(speech.spoken.last, 'Son sayfa.');
    expect(_highlighted(_savedSpan(tester)), [(0, 10, 'Son sayfa.')]);
    speech.finishCurrent();
    await tester.pumpAndSettle();
    expect(_highlighted(_savedSpan(tester)), isEmpty);
  });
}

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
    await tester.tap(find.byTooltip('Okuma ayarları'));
    await tester.pumpAndSettle();
    expect(find.text('Sonraki sayfayı otomatik oku'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('reading-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.25×').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    expect(preferences.speed, ReadingSpeed.fast);

    await tester.pumpWidget(_app(preferences, _import(speech, newPage: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Okuma ayarları'));
    await tester.pumpAndSettle();
    expect(find.text('1.25×'), findsOneWidget);
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
    await tester.tap(find.byTooltip('Okuma ayarları'));
    await tester.pumpAndSettle();
    expect(find.text('1.25×'), findsOneWidget);
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
    preferences.setAutoNextPage(true);
    await preferences.pendingWrites;
    await tester.pump();
    await tester.pump();
    expect(find.text('Okuma tercihleri kalıcı kaydedilemedi.'), findsOneWidget);
    expect(speech.isSpeaking, isTrue);
    expect(preferences.autoNextPage, isTrue);
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
    await tester.tap(find.byTooltip('Okuma ayarları'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reading-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0.75×').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auto-next-page')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(SavedDocumentScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Okuma ayarları'));
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
    await tester.tap(find.byTooltip('Okuma ayarları'));
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

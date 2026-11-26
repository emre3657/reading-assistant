import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/app.dart';
import 'package:reading_assistant/features/listening/services/speech_service.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/save_document_dialog.dart';

import '../image_import/test_doubles.dart';
import 'fake_preferences_store.dart';
import 'fake_speech_service.dart';
import 'reader_controls_test_utils.dart';

// A fake engine is used: these tests cover the screen's controls and the
// blocking rules, not real speech output.
const _readLabel = 'Sesli oku';
const _stopLabel = 'Durdur';

final _fieldFinder = find.byType(TextField);

Finder _button(String label) =>
    {
      'Sesli oku',
      'Duraklat',
      'Devam et',
      'Önceki cümle',
      'Sonraki cümle',
    }.contains(label)
    ? find.byWidgetPredicate((w) => w is IconButton && w.tooltip == label)
    : find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );

bool _enabled(WidgetTester tester, String label) {
  final widget = tester.widget(_button(label));
  if (widget is IconButton) return widget.onPressed != null;
  return (widget as ButtonStyleButton).onPressed != null;
}

class _HomeStore extends FakePreferencesStore {
  final List<SavedDocument> documents = [];

  @override
  Future<List<DocumentCategory>> categories() async => DocumentCategory.values;

  @override
  Future<List<SavedDocument>> list() async => List.of(documents);

  @override
  Future<int> save({
    required String title,
    required DocumentCategory category,
    required String text,
  }) async {
    documents.add(
      SavedDocument(
        id: 1,
        title: title,
        category: category,
        text: text,
        createdAt: DateTime(2024),
      ),
    );
    return 1;
  }
}

Future<bool> _menuEnabled(WidgetTester tester, String label) async {
  await tester.tap(playbackMenu);
  await tester.pumpAndSettle();
  final item = tester.widget<PopupMenuItem<String>>(
    find.ancestor(
      of: find.text(label),
      matching: find.byType(PopupMenuItem<String>),
    ),
  );
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  return item.enabled;
}

Future<FakeSpeechService> _openWithText(
  WidgetTester tester, {
  String text = 'Okunacak metin.',
  FakeSpeechService? speech,
  FakePreferencesStore? store,
}) async {
  speech ??= FakeSpeechService();
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ReadingAssistantApp(
      store: store ?? FakePreferencesStore(),
      pickerService: FakeImagePickerService(
        onPick: () async => XFile('/tmp/a.jpg'),
      ),
      textRecognitionService: FakeTextRecognitionService((_) async => text),
      previewImageBuilder: (file) => ControlledImageProvider(),
      speechService: speech,
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Galeriden görsel seç'));
  await tester.pump();
  await tester.tap(find.text('Metni çıkar'));
  await tester.pump();
  await tester.pump();
  return speech;
}

void main() {
  for (final initiallyPaused in [false, true]) {
    testWidgets(
      'home save and library preserve ${initiallyPaused ? 'paused' : 'active'} reading position',
      (tester) async {
        final store = _HomeStore();
        final speech = await _openWithText(
          tester,
          text: 'Bir. İki.',
          store: store,
        );
        await tapReadingControl(tester, 'Sesli oku');
        await tester.pumpAndSettle();
        await tapReadingControl(tester, 'Sonraki cümle');
        await tester.pumpAndSettle();
        if (initiallyPaused) {
          await tapReadingControl(tester, 'Duraklat');
          await tester.pumpAndSettle();
        }

        await tester.tap(find.byTooltip('Metni kaydet'));
        await tester.pumpAndSettle();
        expect(find.byType(SaveDocumentDialog), findsOneWidget);
        expect(speech.isSpeaking, isFalse);
        await tester.tap(find.text('Vazgeç'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Devam et'), findsOneWidget);
        expect(speech.isSpeaking, isFalse);
        if (!initiallyPaused) {
          await tapReadingControl(tester, 'Devam et');
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('Metni kaydet'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byType(SaveDocumentDialog),
            matching: find.byType(TextFormField),
          ),
          'Örnek',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
        await tester.pumpAndSettle();
        expect(store.documents.single.text, 'Bir. İki.');
        expect(find.byTooltip('Devam et'), findsOneWidget);

        if (!initiallyPaused) {
          await tapReadingControl(tester, 'Devam et');
          await tester.pumpAndSettle();
          expect(speech.isSpeaking, isTrue);
        }
        await tester.tap(find.byTooltip('Kayıtlarım'));
        await tester.pumpAndSettle();
        expect(find.text('Örnek'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byTooltip('Devam et'), findsOneWidget);
        expect(
          tester.widget<TextField>(_fieldFinder).controller!.text,
          'Bir. İki.',
        );
        expect(speech.isSpeaking, isFalse);
        await tapReadingControl(tester, 'Devam et');
        await tester.pumpAndSettle();
        expect(speech.spoken.last, 'İki.');
      },
    );
  }

  testWidgets('pause failure keeps home open and reports the error', (
    tester,
  ) async {
    final speech = FakeSpeechService(stopError: StateError('stop'));
    await _openWithText(tester, speech: speech, store: _HomeStore());
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kayıtlarım'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Okuma durdurulamadı.'), findsOneWidget);
    expect(find.byTooltip('Kayıtlarım'), findsOneWidget);
  });

  testWidgets('backgrounding during pause cancels pending library navigation', (
    tester,
  ) async {
    final speech = await _openWithText(tester, store: _HomeStore());
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pumpAndSettle();
    final gate = speech.transitionStopGate = Completer<void>();
    await tester.tap(find.byTooltip('Kayıtlarım'));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Kayıtlarım',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Metni kaydet',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<PopupMenuButton<String>>(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.byType(PopupMenuButton<String>),
            ),
          )
          .enabled,
      isFalse,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Kayıtlarım'), findsOneWidget);
    expect(find.byType(SaveDocumentDialog), findsNothing);
  });

  testWidgets('controls appear with the text; stop is disabled when idle', (
    tester,
  ) async {
    await _openWithText(tester);
    expect(_button(_readLabel), findsOneWidget);
    expect(_enabled(tester, _readLabel), isTrue);
    expect(await _menuEnabled(tester, _stopLabel), isFalse);
  });

  testWidgets('reads the visible, edited text, not the raw OCR result', (
    tester,
  ) async {
    final speech = await _openWithText(tester, text: 'ham metin');
    // Edit confirmation applies only to replacing the text, not to speaking.
    await tester.enterText(_fieldFinder, 'düzenlenmiş metin');
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();

    expect(speech.spoken, ['düzenlenmiş metin']);
    expect(find.text('Okunuyor…'), findsNothing);
  });

  testWidgets('blocks editing and image actions while reading; stop works', (
    tester,
  ) async {
    final speech = await _openWithText(tester);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();

    expect(
      find.byTooltip(_readLabel),
      findsNothing,
      reason: 'replaced by Duraklat',
    );
    expect(_enabled(tester, 'Duraklat'), isTrue);
    expect(await _menuEnabled(tester, _stopLabel), isTrue);
    expect(tester.widget<TextField>(_fieldFinder).readOnly, isTrue);
    for (final label in [
      'Metni çıkar',
      'Görseli değiştir',
      'Görseli kaldır',
      'Sola döndür',
      'Sağa döndür',
    ]) {
      expect(_enabled(tester, label), isFalse, reason: label);
    }
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );

    await tapReadingControl(tester, 'Durdur');
    await tester.pump();
    await tester.pump();

    expect(speech.stopCalls, 1);
    expect(_enabled(tester, _readLabel), isTrue);
    expect(_enabled(tester, 'Metni çıkar'), isTrue);
    expect(tester.widget<TextField>(_fieldFinder).readOnly, isFalse);
  });

  testWidgets('shows completion and allows reading again', (tester) async {
    final speech = await _openWithText(tester);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();
    speech.finishCurrent();
    await tester.pump();
    await tester.pump();

    expect(find.text('Okuma tamamlandı.'), findsNothing);
    expect(_enabled(tester, _readLabel), isTrue);
  });

  testWidgets('tells the user to install a Turkish voice', (tester) async {
    final speech = await _openWithText(
      tester,
      speech: FakeSpeechService(
        setup: const SpeechSetup(SpeechAvailability.noOfflineTurkishVoice),
      ),
    );
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Türkçe sesi yükleyin'), findsOneWidget);
    expect(speech.spoken, isEmpty);
    expect(_enabled(tester, _readLabel), isTrue);
  });

  testWidgets('hides playback for whitespace-only text', (tester) async {
    final speech = await _openWithText(tester, text: 'x');

    await tester.enterText(_fieldFinder, '   ');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('listening-panel')), findsNothing);
    expect(find.byTooltip(_readLabel), findsNothing);
    expect(speech.prepareCalls, 0);
  });

  testWidgets('stops reading when the app goes to the background', (
    tester,
  ) async {
    final speech = await _openWithText(tester);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(speech.stopCalls, 0, reason: 'inactive keeps reading');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();
    expect(speech.stopCalls, 1);
    expect(_enabled(tester, _readLabel), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('closing the screen stops reading without errors', (
    tester,
  ) async {
    final speech = await _openWithText(tester);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    speech.finishCurrent();
    await tester.pump();

    expect(speech.stopCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lock icon shows only during a session and explains itself', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _openWithText(tester);
    const message = 'Düzenlemek için okumayı durdur';
    final lock = find.byIcon(Icons.lock_outline);
    expect(lock, findsNothing);

    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();
    expect(lock, findsOneWidget);
    // Right next to the label, not inside the field.
    final label = tester.getRect(find.text('Çıkarılan metin'));
    final icon = tester.getRect(lock);
    expect(icon.left, greaterThanOrEqualTo(label.right));
    expect((icon.center.dy - label.center.dy).abs(), lessThan(30));
    expect(
      tester
          .getSize(
            find.ancestor(of: lock, matching: find.byType(SizedBox)).first,
          )
          .shortestSide,
      greaterThanOrEqualTo(48),
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == message,
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(lock),
      matchesSemantics(label: 'Düzenleme kilitli. $message'),
    );

    // Touch: tapping the icon shows the explanation.
    await tester.tap(lock);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(message), findsWidgets);
    // Tapping does not stop reading.
    expect(find.byTooltip('Duraklat'), findsOneWidget);

    await tapReadingControl(tester, 'Durdur');
    await tester.pump();
    await tester.pump();
    expect(lock, findsNothing);
    handle.dispose();
  });

  testWidgets('the old "not saved" helper text is gone', (tester) async {
    await _openWithText(tester);
    expect(find.textContaining('kaydedilmedi'), findsNothing);
    expect(find.textContaining('düzeltebilirsin'), findsNothing);
  });

  Future<void> expectNoFocusAfter(
    WidgetTester tester,
    Future<void> Function() endSession,
  ) async {
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    // Touching the locked field neither focuses it nor stops the reading.
    await tester.tap(_fieldFinder);
    await tester.pump();
    expect(editable.widget.focusNode.hasFocus, isFalse);
    expect(
      find.byTooltip('Duraklat').evaluate().isNotEmpty ||
          find.byTooltip('Devam et').evaluate().isNotEmpty,
      isTrue,
    );

    await endSession();
    expect(editable.widget.focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  }

  testWidgets('touching the locked field then Stop does not focus or open '
      'the keyboard; editing works again afterwards', (tester) async {
    await _openWithText(tester);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();

    await expectNoFocusAfter(tester, () async {
      await tapReadingControl(tester, 'Durdur');
      await tester.pump();
      await tester.pump();
    });

    // After the session a new tap edits normally.
    await tester.tap(_fieldFinder);
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('same behaviour while paused', (tester) async {
    await _openWithText(tester);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();
    await tapReadingControl(tester, 'Duraklat');
    await tester.pump();
    await tester.pump();

    await expectNoFocusAfter(tester, () async {
      await tapReadingControl(tester, 'Durdur');
      await tester.pump();
      await tester.pump();
    });
  });

  testWidgets('no auto focus after completion or an error', (tester) async {
    final speech = await _openWithText(tester);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();
    await tester.tap(_fieldFinder);
    await tester.pump();
    speech.finishCurrent();
    await tester.pump();
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('starting to read removes an existing focus', (tester) async {
    await _openWithText(tester);
    await tester.tap(_fieldFinder);
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasFocus, isTrue);

    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();
    expect(editable.widget.focusNode.hasFocus, isFalse);
  });

  testWidgets('sentence controls: states, indicator and pause lock', (
    tester,
  ) async {
    final speech = await _openWithText(tester, text: 'Bir. İki. Üç.');
    expect(find.byTooltip('Duraklat'), findsNothing);
    expect(find.byTooltip('Devam et'), findsNothing);
    expect(find.byTooltip('Önceki cümle'), findsOneWidget);
    for (final label in ['Önceki cümle', 'Sonraki cümle']) {
      expect(_enabled(tester, label), isFalse, reason: label);
    }
    expect(await _menuEnabled(tester, 'Başa dön'), isFalse);
    expect(find.textContaining('Cümle 1'), findsNothing);
    expect(
      find.text('Sonraki sayfayı otomatik oku'),
      findsNothing,
      reason: 'the OCR / new page screen has no automatic page switch',
    );

    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();
    expect(find.text('Cümle 1 / 3'), findsNothing);
    expect(find.text('Hız 1×'), findsNothing);
    expect(_enabled(tester, 'Duraklat'), isTrue);
    expect(_enabled(tester, 'Sonraki cümle'), isTrue);
    expect(_enabled(tester, 'Önceki cümle'), isFalse);
    expect(await _menuEnabled(tester, 'Başa dön'), isTrue);

    await tapReadingControl(tester, 'Sonraki cümle');
    await tester.pump();
    await tester.pump();
    expect(find.text('Cümle 2 / 3'), findsNothing);
    expect(speech.spoken, ['Bir. ', 'İki. ']);
    expect(_enabled(tester, 'Önceki cümle'), isTrue);
    expect(await _menuEnabled(tester, 'Başa dön'), isTrue);

    await tapReadingControl(tester, 'Duraklat');
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Devam et'), findsOneWidget);
    expect(find.text('Duraklatıldı.'), findsNothing);
    expect(_enabled(tester, 'Devam et'), isTrue);
    expect(find.byTooltip(_readLabel), findsNothing);
    expect(tester.widget<TextField>(_fieldFinder).readOnly, isTrue);
    for (final label in ['Metni çıkar', 'Görseli değiştir', 'Görseli kaldır']) {
      expect(_enabled(tester, label), isFalse, reason: label);
    }

    await tapReadingControl(tester, 'Başa dön');
    await tester.pump();
    expect(find.text('Cümle 1 / 3'), findsNothing);
    expect(find.byTooltip('Devam et'), findsOneWidget, reason: 'still paused');

    await tapReadingControl(tester, 'Devam et');
    await tester.pump();
    await tester.pump();
    expect(speech.spoken.last, 'Bir. ');
    expect(find.byTooltip('Duraklat'), findsOneWidget);

    await tapReadingControl(tester, 'Duraklat');
    await tester.pump();
    await tester.pump();
    await tapReadingControl(tester, 'Durdur');
    await tester.pump();
    await tester.pump();
    expect(_enabled(tester, _readLabel), isTrue);
    expect(_enabled(tester, 'Metni çıkar'), isTrue);
    expect(tester.widget<TextField>(_fieldFinder).readOnly, isFalse);
    expect(find.textContaining('Cümle 1'), findsNothing);
  });

  testWidgets('a paused reading stops when the app goes to the background', (
    tester,
  ) async {
    final speech = await _openWithText(tester, text: 'Bir. İki.');
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pump();
    await tester.pump();
    await tapReadingControl(tester, 'Duraklat');
    await tester.pump();
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();
    expect(speech.stopCalls, 2);
    expect(_enabled(tester, _readLabel), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('stays usable with large text', (tester) async {
    await _openWithText(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip(_readLabel));
    expect(find.byTooltip(_readLabel), findsOneWidget);
  });
}

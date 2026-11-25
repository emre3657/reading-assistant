import '../listening/reader_controls_test_utils.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/reading_position.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/saved_document_screen.dart';
import 'package:reading_assistant/features/listening/presentation/listening_controller.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';
import 'package:reading_assistant/theme/app_theme.dart';

import '../listening/fake_preferences_store.dart';
import '../listening/fake_speech_service.dart';
import 'fake_reading_positions.dart';

const _text = 'Aynı. Aynı. Son cümle.';

class _Store extends DocumentStore with FakeReadingPositions {
  _Store({this.firstText = _text});

  final String firstText;
  Completer<void>? pagesGate;

  @override
  Future<List<DocumentPage>> pages(int documentId) async {
    await pagesGate?.future;
    return [
      DocumentPage(id: 1, documentId: 7, position: 0, text: firstText),
      const DocumentPage(
        id: 2,
        documentId: 7,
        position: 1,
        text: 'Başka sayfa.',
      ),
    ];
  }
}

class _SlowStop extends FakeSpeechService {
  final gate = Completer<void>();

  @override
  Future<void> stop() async {
    await gate.future;
    await super.stop();
  }
}

Future<void> _show(
  WidgetTester tester,
  _Store store,
  FakeSpeechService speech, {
  ReadingPreferences? preferences,
  int? initialSentence,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ReadingPreferencesScope(
      preferences:
          preferences ?? ReadingPreferences(store: FakePreferencesStore()),
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: SavedDocumentScreen(
          document: SavedDocument(
            id: 7,
            title: 'Kitap',
            category: DocumentCategory.note,
            text: store.firstText,
            createdAt: DateTime(2024),
          ),
          pageId: 1,
          store: store,
          speechService: speech,
          initialSentence: initialSentence,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _field => find.byKey(const ValueKey('saved-reading-text'));
Finder get _readFrom => find.byKey(const ValueKey('read-from-sentence'));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Offset _character(WidgetTester tester, int index) {
  final render = tester
      .state<EditableTextState>(find.byType(EditableText))
      .renderEditable;
  final box = render
      .getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: index + 1),
      )
      .first
      .toRect();
  return render.localToGlobal(box.center);
}

List<(int, int, TextStyle?)> _segments(WidgetTester tester) {
  final span =
      tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable
              .text!
          as TextSpan;
  var offset = 0;
  final result = <(int, int, TextStyle?)>[];
  void visit(InlineSpan item) {
    if (item is! TextSpan) return;
    final length = item.text?.length ?? 0;
    if (length > 0) result.add((offset, offset + length, item.style));
    offset += length;
    for (final child in item.children ?? <InlineSpan>[]) {
      visit(child);
    }
  }

  visit(span);
  return result;
}

void main() {
  testWidgets('word progress starts at the selected sentence', (tester) async {
    const text = 'İlk cümle. Şimdi, güzel sözler!';
    final speech = FakeSpeechService();
    await _show(tester, _Store(firstText: text), speech);
    await tester.tapAt(_character(tester, text.indexOf('Şimdi')));
    await tester.pumpAndSettle();
    await _tap(tester, _readFrom);
    expect(speech.spoken.last, 'Şimdi, güzel sözler!');
    speech.progress(7, 12);
    await tester.pump();
    final word = _segments(tester)
        .singleWhere((segment) => segment.$1 == text.indexOf('güzel'));
    expect(text.substring(word.$1, word.$2), 'güzel');
    final field = tester.element(find.byType(EditableText));
    expect(word.$3!.backgroundColor, ReadingColors.of(field).wordHighlight);
    expect(word.$3!.decoration, isNull);
  });

  testWidgets(
    'reading from selected sentence retracts bookmark without jumping to it',
    (tester) async {
      final store = _Store();
      store.bookmarks[7] = const ReadingPosition(
        pageId: 1,
        sentenceIndex: 0,
        pageText: _text,
      );
      final speech = FakeSpeechService();
      await _show(tester, store, speech);
      await tester.tapAt(_character(tester, 7));
      await tester.pumpAndSettle();
      await tester.tap(_readFrom);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(speech.spoken, isEmpty);
      await tester.pumpAndSettle();
      expect(speech.spoken.single, 'Aynı. ');
      expect(store.positions[7]?.sentenceIndex, 1);
      expect(store.bookmarks[7]?.sentenceIndex, 0);
    },
  );

  testWidgets('sentence selection and reading work after animated navigation', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setPageAnimationEnabled(true);
    preferences.setPageAnimationEffect(PageAnimationEffect.turn);
    preferences.setPageView(ReadingPageView.book);
    final store = _Store();
    final speech = FakeSpeechService();
    await _show(tester, store, speech, preferences: preferences);
    await tester.tap(find.byKey(const ValueKey('next-page')));
    await tester.pumpAndSettle();
    await tester.tapAt(_character(tester, 1));
    await tester.pumpAndSettle();
    expect(_readFrom.hitTestable(), findsOneWidget);
    await _tap(tester, _readFrom);
    expect(speech.spoken, ['Başka sayfa.']);
    expect(store.positions[7]?.pageId, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'size reflow reanchors selection bubble and preserves tap target',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final preferences = ReadingPreferences(store: FakePreferencesStore());
      await preferences.load();
      final speech = FakeSpeechService();
      await _show(
        tester,
        _Store(firstText: 'Aynı.\nAynı. Son cümle.'),
        speech,
        preferences: preferences,
        textScale: 1.5,
      );
      await tester.tapAt(_character(tester, 7));
      await tester.pumpAndSettle();
      expect(_readFrom.hitTestable(), findsOneWidget);
      final before = tester.getTopLeft(_readFrom);
      preferences.setTextSize(ReadingTextSize.extraLarge);
      await tester.pumpAndSettle();
      expect(_readFrom.hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(_readFrom), isNot(before));
      expect(
        _segments(tester)
            .where((s) => s.$3?.backgroundColor != null)
            .map((s) => (s.$1, s.$2)),
        [(6, 11)],
      );
      final beforeAlignment = tester.getTopLeft(_readFrom);
      preferences.setTextAlignment(ReadingTextAlignment.right);
      await tester.pumpAndSettle();
      expect(_readFrom.hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(_readFrom), isNot(beforeAlignment));
      final beforeSpacing = tester.getTopLeft(_readFrom);
      preferences.setLineSpacing(ReadingLineSpacing.wide);
      await tester.pumpAndSettle();
      expect(_readFrom.hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(_readFrom), isNot(beforeSpacing));
      final beforePage = tester.getTopLeft(_readFrom);
      preferences.setPageView(ReadingPageView.book);
      await tester.pumpAndSettle();
      expect(_readFrom.hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(_readFrom), isNot(beforePage));
      await _tap(tester, _readFrom);
      expect(speech.spoken, ['Aynı. ']);
    },
  );

  testWidgets(
    'repeated sentence tap selects only the tapped occurrence; reading starts on request',
    (tester) async {
      final store = _Store();
      final speech = FakeSpeechService();
      await _show(tester, store, speech);
      final before = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final size = before.size;
      final characterBoxes = before.getBoxesForSelection(
        const TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.tapAt(_character(tester, 7));
      await tester.pumpAndSettle();
      final after = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      expect(after.size, size);
      expect(
        after
            .getBoxesForSelection(
              const TextSelection(baseOffset: 6, extentOffset: 11),
            )
            .map((box) => box.toRect()),
        characterBoxes.map((box) => box.toRect()),
      );
      expect(_readFrom, findsOneWidget);
      expect(speech.spoken, isEmpty);
      expect(store.positionWrites, 0);
      final segments = _segments(tester);
      expect(
        segments
            .where((s) => s.$3?.backgroundColor != null)
            .map((s) => (s.$1, s.$2)),
        [(6, 11)],
      );
      expect(
        segments.where((s) => s.$3?.decoration == TextDecoration.underline),
        isEmpty,
      );
      expect(tester.testTextInput.isVisible, isFalse);
      await _tap(tester, _readFrom);
      expect(speech.spoken, ['Aynı. ']);
      expect(store.positions[7]!.sentenceIndex, 1);
      final speaking = _segments(tester);
      expect(_readFrom, findsNothing);
      expect(
        speaking
            .where((s) => s.$3?.backgroundColor != null)
            .map((s) => (s.$1, s.$2)),
        [(6, 11)],
      );
      speech.finishCurrent();
      await tester.pumpAndSettle();
      expect(speech.spoken, ['Aynı. ', 'Son cümle.']);
      expect(store.positions[7]!.sentenceIndex, 2);
    },
  );

  testWidgets('a failed speech setup keeps the selection and bubble', (
    tester,
  ) async {
    final speech = FakeSpeechService(prepareError: StateError('setup'));
    await _show(tester, _Store(), speech);
    await tester.tapAt(_character(tester, 7));
    await tester.pumpAndSettle();
    await _tap(tester, _readFrom);
    expect(_readFrom, findsOneWidget);
    expect(speech.spoken, isEmpty);
    expect(find.textContaining('Sesli okuma başlatılamadı'), findsOneWidget);
    expect(
      _segments(tester)
          .where((s) => s.$3?.backgroundColor != null)
          .map((s) => (s.$1, s.$2)),
      [(6, 11)],
    );
  });

  testWidgets(
    'tap during playback does not interrupt; explicit action restarts with selected sentence',
    (tester) async {
      final store = _Store();
      final speech = FakeSpeechService();
      final preferences = ReadingPreferences(store: FakePreferencesStore());
      await preferences.load();
      preferences.setSpeed(ReadingSpeed.fast);
      preferences.setAutoNextPage(true);
      preferences.setFollowSentence(true);
      await _show(tester, store, speech, preferences: preferences);
      await tapReadingControl(tester, 'Sesli oku');
      await tester.pumpAndSettle();
      expect(speech.spoken, ['Aynı. ']);
      await tester.tapAt(_character(tester, 13));
      await tester.pumpAndSettle();
      expect(speech.stopCalls, 0);
      expect(speech.spoken, ['Aynı. ']);
      expect(store.positions[7]!.sentenceIndex, 0);
      final segments = _segments(tester);
      final scheme = Theme.of(tester.element(_field)).colorScheme;
      expect(
        segments
            .where(
              (s) =>
                  s.$3?.backgroundColor ==
                  scheme.onSurface.withValues(alpha: 0.12),
            )
            .map((s) => (s.$1, s.$2)),
        [(0, 5)],
      );
      expect(
        segments
            .where(
              (s) =>
                  s.$3?.backgroundColor ==
                  scheme.primary.withValues(alpha: 0.18),
            )
            .map((s) => (s.$1, s.$2)),
        [(12, 22)],
      );
      await _tap(tester, _readFrom);
      expect(speech.stopCalls, 1);
      expect(speech.spoken, ['Aynı. ', 'Son cümle.']);
      expect(speech.spokenRates.last, 1.25);
      expect(store.positions[7]!.sentenceIndex, 2);
      expect(preferences.autoNextPage, isTrue);
      expect(preferences.followSentence, isTrue);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('selection colors and playing precedence in $brightness', (
      tester,
    ) async {
      final speech = FakeSpeechService();
      await _show(tester, _Store(), speech, brightness: brightness);
      await tester.tapAt(_character(tester, 7));
      await tester.pumpAndSettle();
      final scheme = Theme.of(tester.element(_field)).colorScheme;
      final color = _segments(tester)
          .singleWhere((s) => s.$1 == 6 && s.$2 == 11)
          .$3!
          .backgroundColor!;
      expect(color, scheme.primary.withValues(alpha: 0.18));
      final foreground = Theme.of(tester.element(_field))
          .textTheme
          .bodyLarge!
          .color!;
      final background = Color.alphaBlend(color, scheme.surface);
      final a = foreground.computeLuminance() + 0.05;
      final b = background.computeLuminance() + 0.05;
      expect(a > b ? a / b : b / a, greaterThanOrEqualTo(4.5));
      await tapReadingControl(tester, 'Sesli oku');
      await tester.pumpAndSettle();
      await tester.tapAt(_character(tester, 1));
      await tester.pumpAndSettle();
      final selectedAndPlaying = _segments(tester)
          .singleWhere((s) => s.$1 == 0 && s.$2 == 5)
          .$3!
          .backgroundColor;
      expect(selectedAndPlaying, scheme.onSurface.withValues(alpha: 0.12));
      expect(speech.spoken, ['Aynı. ']);
    });
  }

  testWidgets('bubble follows taps, toggles, and does not change layout', (
    tester,
  ) async {
    await _show(tester, _Store(), FakeSpeechService());
    final textBefore = tester.getRect(_field);
    final panelBefore = tester.getRect(
      find.byKey(const ValueKey('listening-panel')),
    );
    final navigationBefore = tester.getRect(
      find.byKey(const ValueKey('next-page')),
    );
    await tester.tapAt(_character(tester, 1));
    await tester.pumpAndSettle();
    final firstBubble = tester.getRect(_readFrom);
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final firstBox = editable
        .getBoxesForSelection(
          const TextSelection(baseOffset: 1, extentOffset: 2),
        )
        .first
        .toRect();
    final firstLine = firstBox.shift(editable.localToGlobal(Offset.zero));
    expect(firstBubble.overlaps(firstLine), isFalse);
    expect(firstBubble.height, greaterThanOrEqualTo(48));
    expect(tester.getRect(_field), textBefore);
    expect(
      tester.getRect(find.byKey(const ValueKey('listening-panel'))),
      panelBefore,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('next-page'))),
      navigationBefore,
    );
    await tester.tapAt(_character(tester, 13));
    await tester.pumpAndSettle();
    final secondBubble = tester.getRect(_readFrom);
    expect(secondBubble.center.dx, greaterThan(firstBubble.center.dx));
    expect(
      _segments(tester)
          .where((s) => s.$3?.backgroundColor != null)
          .map((s) => (s.$1, s.$2)),
      [(12, 22)],
    );
    await tester.tapAt(_character(tester, 13));
    await tester.pumpAndSettle();
    expect(_readFrom, findsNothing);
    expect(
      _segments(tester).where((s) => s.$3?.backgroundColor != null),
      isEmpty,
    );
    expect(tester.getRect(_field), textBefore);
  });

  testWidgets('one tap on stop dismisses selection and stops playback', (
    tester,
  ) async {
    final speech = FakeSpeechService();
    await _show(tester, _Store(), speech);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pumpAndSettle();
    await tester.tapAt(_character(tester, 7));
    await tester.pumpAndSettle();
    expect(_readFrom, findsOneWidget);
    await tapReadingControl(tester, 'Durdur');
    await tester.pumpAndSettle();
    expect(_readFrom, findsNothing);
    expect(speech.isSpeaking, isFalse);
    expect(speech.stopCalls, 1);
    expect(
      _segments(tester).where((s) => s.$3?.backgroundColor != null),
      isEmpty,
    );
  });

  testWidgets(
    'blank taps, drags and long press dismiss the bubble and retain selection menu',
    (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });
      await _show(tester, _Store(), FakeSpeechService());
      await tester.tapAt(_character(tester, 1));
      await tester.pumpAndSettle();
      final rect = tester.getRect(_field);
      await tester.tapAt(Offset(rect.right - 5, _character(tester, 1).dy));
      await tester.pumpAndSettle();
      expect(_readFrom, findsNothing);
      await tester.tapAt(_character(tester, 1));
      await tester.pumpAndSettle();
      await tester.dragFrom(_character(tester, 1), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(_readFrom, findsNothing);
      await tester.tapAt(_character(tester, 7));
      await tester.pumpAndSettle();
      await tester.longPressAt(_character(tester, 1));
      await tester.pumpAndSettle();
      expect(_readFrom, findsNothing);
      final controller = tester.widget<TextField>(_field).controller!;
      expect(controller.selection.isCollapsed, isFalse);
      expect(find.text('Copy'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      final selected = controller.selection.textInside(controller.text);
      await _tap(tester, find.text('Copy'));
      expect(copied, selected);
    },
  );

  testWidgets('iOS selection menu can copy the selected text', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await _show(tester, _Store(), FakeSpeechService());
    await tester.longPressAt(_character(tester, 1));
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(_field).controller!;
    expect(controller.selection.isCollapsed, isFalse);
    expect(find.text('Copy'), findsOneWidget);
    final selected = controller.selection.textInside(controller.text);
    await _tap(tester, find.text('Copy'));
    expect(copied, selected);
  });

  testWidgets(
    'bubble fits a narrow screen with large text without moving content',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _show(tester, _Store(), FakeSpeechService(), textScale: 1.8);
      final before = tester.getRect(_field);
      final panel = tester.getRect(
        find.byKey(const ValueKey('listening-panel')),
      );
      await tester.tapAt(_character(tester, 1));
      await tester.pumpAndSettle();
      final bubble = tester.getRect(_readFrom);
      expect(bubble.left, greaterThanOrEqualTo(0));
      expect(bubble.right, lessThanOrEqualTo(320));
      expect(
        bubble.top,
        greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
      );
      expect(bubble.bottom, lessThanOrEqualTo(panel.top));
      expect(_readFrom.hitTestable(), findsOneWidget);
      expect(tester.getRect(_field), before);
      expect(tester.takeException(), isNull);
      await _tap(tester, _readFrom);
    },
  );

  testWidgets(
    'bubble goes below a line near the top and tracks layout changes',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final text =
          '$_text\n\n${List.filled(80, 'Uzun metin burada.').join('\n\n')}';
      await _show(tester, _Store(firstText: text), FakeSpeechService());
      final scroll = tester
          .widget<SingleChildScrollView>(
            find
                .ancestor(
                  of: _field,
                  matching: find.byType(SingleChildScrollView),
                )
                .first,
          )
          .controller!;
      final appBarBottom = tester.getRect(find.byType(AppBar)).bottom;
      scroll.jumpTo(_character(tester, 1).dy - appBarBottom - 12);
      await tester.pumpAndSettle();
      final point = _character(tester, 1);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(tester.getRect(_readFrom).top, greaterThan(point.dy));
      expect(_readFrom.hitTestable(), findsOneWidget);
      tester.view.physicalSize = const Size(320, 800);
      await tester.pumpAndSettle();
      final resizedPoint = _character(tester, 1);
      final bubble = tester.getRect(_readFrom);
      expect(bubble.top, greaterThan(resizedPoint.dy));
      expect(bubble.right, lessThanOrEqualTo(320));
      expect(_readFrom.hitTestable(), findsOneWidget);
    },
  );

  testWidgets('paused session is stopped before selected playback', (
    tester,
  ) async {
    final speech = FakeSpeechService();
    await _show(tester, _Store(), speech, initialSentence: 1);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pumpAndSettle();
    await tapReadingControl(tester, 'Duraklat');
    await tester.pumpAndSettle();
    final previousStops = speech.stopCalls;
    await tester.tapAt(_character(tester, 1));
    await tester.pumpAndSettle();
    expect(speech.stopCalls, previousStops);
    await _tap(tester, _readFrom);
    expect(speech.stopCalls, previousStops + 1);
    expect(speech.spoken, ['Aynı. ', 'Aynı. ']);
  });

  testWidgets('stop error preserves position and prevents restarting', (
    tester,
  ) async {
    final store = _Store();
    final speech = FakeSpeechService(stopError: StateError('stop'));
    await _show(tester, store, speech);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pumpAndSettle();
    await tester.tapAt(_character(tester, 13));
    await tester.pumpAndSettle();
    await _tap(tester, _readFrom);
    expect(speech.spoken, ['Aynı. ']);
    expect(store.positions[7]!.sentenceIndex, 0);
    expect(find.textContaining('Okuma durdurulamadı'), findsWidgets);
    expect(_readFrom, findsOneWidget);
  });

  testWidgets('selection is cleared on page navigation and editing', (
    tester,
  ) async {
    final speech = FakeSpeechService();
    await _show(tester, _Store(), speech);
    await tester.tapAt(_character(tester, 7));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('next-page')));
    expect(_readFrom, findsNothing);
    await _tap(tester, find.byKey(const ValueKey('previous-page')));
    expect(_readFrom, findsNothing);
    await tester.tapAt(_character(tester, 1));
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Düzenle'));
    expect(_readFrom, findsNothing);
    await _tap(tester, find.text('Düzenlemekten vazgeç'));
    expect(_readFrom, findsNothing);
  });

  testWidgets('blank space, drag and long press do not select a sentence', (
    tester,
  ) async {
    await _show(tester, _Store(), FakeSpeechService());
    final rect = tester.getRect(_field);
    final textPoint = _character(tester, 1);
    await tester.tapAt(Offset(rect.right - 5, textPoint.dy));
    await tester.pumpAndSettle();
    expect(_readFrom, findsNothing);
    await tester.dragFrom(textPoint, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(_readFrom, findsNothing);
    await tester.longPressAt(_character(tester, 1));
    await tester.pumpAndSettle();
    expect(_readFrom, findsNothing);
    final controller = tester.widget<TextField>(_field).controller!;
    expect(controller.selection.isCollapsed, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('pending stop prevents duplicate starts and leaving the page', (
    tester,
  ) async {
    final speech = _SlowStop();
    await _show(tester, _Store(), speech);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pumpAndSettle();
    await tester.tapAt(_character(tester, 13));
    await tester.pumpAndSettle();
    await tester.tap(_readFrom);
    await tester.pump();
    expect(tester.widget<TextButton>(_readFrom).onPressed, isNull);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('next-page')))
          .onPressed,
      isNull,
    );
    speech.gate.complete();
    await tester.pumpAndSettle();
    expect(speech.spoken, ['Aynı. ', 'Son cümle.']);
  });

  testWidgets('automatic page advance clears the previous sentence selection', (
    tester,
  ) async {
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    preferences.setAutoNextPage(true);
    final speech = FakeSpeechService();
    await _show(tester, _Store(), speech, preferences: preferences);
    await tester.tapAt(_character(tester, 13));
    await tester.pumpAndSettle();
    await _tap(tester, _readFrom);
    speech.finishCurrent();
    await tester.pumpAndSettle();
    expect(_readFrom, findsNothing);
    expect(speech.spoken, ['Son cümle.', 'Başka sayfa.']);
  });

  testWidgets(
    'reading from selection cancels a pending automatic page advance',
    (tester) async {
      final preferences = ReadingPreferences(store: FakePreferencesStore());
      await preferences.load();
      preferences.setAutoNextPage(true);
      final speech = FakeSpeechService();
      final store = _Store();
      await _show(tester, store, speech, preferences: preferences);
      await tester.tapAt(_character(tester, 13));
      await tester.pumpAndSettle();
      await _tap(tester, _readFrom);
      await tester.tapAt(_character(tester, 13));
      await tester.pumpAndSettle();
      store.pagesGate = Completer<void>();
      speech.finishCurrent();
      await tester.pump();
      await tester.pump();
      expect(find.text('Sonraki sayfa açılıyor…'), findsNothing);
      await _tap(tester, _readFrom);
      expect(speech.spoken, ['Son cümle.', 'Son cümle.']);
      store.pagesGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sayfa 1 / 2'), findsOneWidget);
      expect(speech.spoken, ['Son cümle.', 'Son cümle.']);
    },
  );

  testWidgets('backgrounding while waiting for stop cancels restart', (
    tester,
  ) async {
    final speech = _SlowStop();
    await _show(tester, _Store(), speech);
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pumpAndSettle();
    await tester.tapAt(_character(tester, 13));
    await tester.pumpAndSettle();
    await tester.tap(_readFrom);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    speech.gate.complete();
    await tester.pumpAndSettle();
    expect(speech.spoken, ['Aynı. ']);
    expect(speech.isSpeaking, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('next-page')))
          .onPressed,
      isNotNull,
    );
  });
}

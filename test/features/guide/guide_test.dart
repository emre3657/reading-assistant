import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/app.dart';
import 'package:reading_assistant/features/guide/guide_host.dart';
import 'package:reading_assistant/features/guide/guide_manager.dart';
import 'package:reading_assistant/features/library/data/document_page.dart';
import 'package:reading_assistant/features/library/data/reading_position.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/startup/intro_screen.dart';

import '../image_import/test_doubles.dart';
import '../listening/fake_preferences_store.dart';
import '../listening/fake_speech_service.dart';
import '../library/fake_reading_positions.dart';

class _DocumentStore extends FakePreferencesStore with FakeReadingPositions {
  _DocumentStore({this.text = 'Bir cümle.'});

  final String text;
  late final document = SavedDocument(
    id: 1,
    title: 'Belge',
    category: DocumentCategory.note,
    text: text,
    createdAt: DateTime(2026),
  );
  late final page = DocumentPage(
    id: 10,
    documentId: 1,
    position: 0,
    text: text,
  );

  @override
  Future<List<SavedDocument>> list() async => [document];

  @override
  Future<SavedDocument?> getDocument(int id) async => document;

  @override
  Future<List<DocumentPage>> pages(int documentId) async => [page];
}

class _GatedGuideStore extends FakePreferencesStore {
  final started = Completer<void>();
  final gate = Completer<void>();
  bool first = true;

  @override
  Future<void> completeGuides(Set<String> keys) async {
    if (first) {
      first = false;
      started.complete();
      await gate.future;
    }
    await super.completeGuides(keys);
  }
}

Future<void> openApp(
  WidgetTester tester,
  FakePreferencesStore store, {
  FakeImagePickerService? picker,
  FakeSpeechService? speech,
}) async {
  await tester.pumpWidget(
    ReadingAssistantApp(
      store: store,
      pickerService: picker ?? FakeImagePickerService(),
      speechService: speech ?? FakeSpeechService(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openReader(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Kayıtlarım'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('document-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('page-10')));
  await tester.pumpAndSettle();
}

Offset characterPosition(WidgetTester tester) {
  final field = find.byKey(const ValueKey('saved-reading-text'));
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  final render = tester.state<EditableTextState>(editable).renderEditable;
  final box = render
      .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1))
      .first
      .toRect();
  return render.localToGlobal(box.center);
}

void main() {
  test('reset is serialized after pending completion', () async {
    final store = _GatedGuideStore()..guides.clear();
    final manager = GuideManager(store);
    await manager.load();
    expect(manager.begin(GuideGroup.text), isTrue);
    manager.complete(GuideGroup.text);
    await store.started.future;
    manager.restart();
    expect(manager.begin(GuideGroup.home), isTrue);
    manager.complete(GuideGroup.home);
    store.gate.complete();
    await manager.pendingWrites;
    expect(store.guides, {'guide_home'});
    manager.dispose();
  });

  testWidgets('intro precedes home guide; steps block controls and persist', (
    tester,
  ) async {
    final store = FakePreferencesStore()
      ..introCompleted = false
      ..guides.clear();
    var pickerCalls = 0;
    await tester.pumpWidget(
      ReadingAssistantApp(
        store: store,
        pickerService: FakeImagePickerService(
          onPickMultiple: () async {
            pickerCalls++;
            return [];
          },
        ),
        speechService: FakeSpeechService(),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(IntroScreen), findsOneWidget);
    expect(
      find.text('Bir veya birden fazla sayfa fotoğrafı seçebilirsin.'),
      findsNothing,
    );
    await tester.tap(find.text('Atla'));
    await tester.pumpAndSettle();
    expect(
      find.text('Bir veya birden fazla sayfa fotoğrafı seçebilirsin.'),
      findsOneWidget,
    );
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(
        'Adım 1/3. Bir veya birden fazla sayfa fotoğrafı seçebilirsin.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<ExcludeSemantics>(
            find.ancestor(
              of: find.text('Galeriden görsel seç'),
              matching: find.byType(ExcludeSemantics),
            ),
          )
          .any((widget) => widget.excluding),
      isTrue,
    );
    semantics.dispose();
    await tester.tap(find.text('Galeriden görsel seç'), warnIfMissed: false);
    expect(pickerCalls, 0);
    await tester.tap(find.text('İleri'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sayfanın fotoğrafını çekerek başlayabilirsin.'),
      findsOneWidget,
    );
    await tester.tap(find.text('İleri'));
    await tester.pumpAndSettle();
    expect(
      find.text('Metni kendin yazabilir veya yapıştırabilirsin.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    expect(store.guides, contains('guide_home'));
    expect(store.introCompleted, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await openApp(tester, store);
    expect(
      find.text('Bir veya birden fazla sayfa fotoğrafı seçebilirsin.'),
      findsNothing,
    );
  });

  testWidgets('back completes only active group and menu restarts all guides', (
    tester,
  ) async {
    final store = FakePreferencesStore()..guides.clear();
    await openApp(tester, store);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(store.guides, {'guide_home'});
    await tester.tap(find.byTooltip('Diğer seçenekler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kullanım rehberi'));
    await tester.pumpAndSettle();
    expect(
      find.text('Bir veya birden fazla sayfa fotoğrafı seçebilirsin.'),
      findsOneWidget,
    );
    expect(store.guides, isEmpty);
    expect(store.introCompleted, isTrue);
  });

  testWidgets('restarting while a draft is open waits for home controls', (
    tester,
  ) async {
    final store = FakePreferencesStore();
    await openApp(tester, store);
    await tester.tap(find.text('Metin yaz veya yapıştır'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Diğer seçenekler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kullanım rehberi'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Ana ekran rehberi başlangıç seçenekleri görünür olduğunda başlayacak.',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Kapat'));
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    expect(
      find.text('Bir veya birden fazla sayfa fotoğrafı seçebilirsin.'),
      findsOneWidget,
    );
  });

  testWidgets('valid text guide waits for keyboard and keeps draft', (
    tester,
  ) async {
    final store = FakePreferencesStore()..guides.remove('guide_text');
    await openApp(tester, store);
    await tester.tap(find.text('Metin yaz veya yapıştır'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('import-text')),
      'Bir taslak',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Metni kontrol edip gerektiğinde düzeltebilirsin.'),
      findsNothing,
    );
    final controller = tester
        .widget<TextField>(find.byKey(const ValueKey('import-text')))
        .controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(
      find.text('Metni kontrol edip gerektiğinde düzeltebilirsin.'),
      findsNothing,
    );
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pumpAndSettle();
    expect(
      find.text('Metni kontrol edip gerektiğinde düzeltebilirsin.'),
      findsOneWidget,
    );
    await tester.tap(find.text('İleri'));
    await tester.pumpAndSettle();
    expect(find.text('Metni dinleyebilirsin.'), findsOneWidget);
    await tester.tap(find.text('İleri'));
    await tester.pumpAndSettle();
    expect(
      find.text('İstersen daha sonra devam etmek için kaydedebilirsin.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('import-text')))
          .controller!
          .text,
      'Bir taslak',
    );
    expect(store.guides, contains('guide_text'));
    addTearDown(tester.view.resetViewInsets);
  });

  testWidgets(
    'missing target waits, route changes suspend and retain progress',
    (tester) async {
      final store = FakePreferencesStore()..guides.clear();
      final manager = GuideManager(store);
      await manager.load();
      final first = GlobalKey();
      final second = GlobalKey();
      final navigator = GlobalKey<NavigatorState>();
      var showSecond = false;
      var firstTaps = 0;
      late StateSetter update;
      await tester.pumpWidget(
        GuideScope(
          manager: manager,
          child: MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [manager.routes],
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return GuideHost(
                  offers: [
                    GuideOffer(
                      group: GuideGroup.home,
                      enabled: true,
                      steps: [
                        GuideStep(first, 'İlk hedef'),
                        GuideStep(second, 'İkinci hedef'),
                      ],
                    ),
                  ],
                  child: Scaffold(
                    body: Column(
                      children: [
                        ElevatedButton(
                          key: first,
                          onPressed: () => firstTaps++,
                          child: const Text('Bir'),
                        ),
                        if (showSecond)
                          ElevatedButton(
                            key: second,
                            onPressed: () {},
                            child: const Text('İki'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('İlk hedef'), findsOneWidget);
      await tester.tap(find.text('İleri'));
      await tester.pumpAndSettle();
      expect(find.text('İkinci hedef'), findsNothing);
      expect(store.guides, isNot(contains('guide_home')));
      await tester.tap(find.text('Bir'));
      expect(firstTaps, 1);
      update(() => showSecond = true);
      await tester.pumpAndSettle();
      expect(find.text('İkinci hedef'), findsOneWidget);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Başka ekran')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('İkinci hedef'), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('İkinci hedef'), findsOneWidget);
      await tester.tap(find.text('Atla'));
      await tester.pumpAndSettle();
      expect(store.guides, contains('guide_home'));
      await tester.pumpWidget(const SizedBox.shrink());
      manager.dispose();
    },
  );

  testWidgets(
    'bookmark and later available resume guide appear on their own screens',
    (tester) async {
      final store = _DocumentStore()
        ..guides.remove('guide_resume')
        ..guides.remove('guide_bookmark');
      await openApp(tester, store);
      await tester.tap(find.byTooltip('Kayıtlarım'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('document-1')));
      await tester.pumpAndSettle();
      expect(find.text('Son okuduğun konuma dönebilirsin.'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('page-10')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'İşaretlediğin konumu saklamak için ayraç koyabilirsin. Okumaya devam etsen de ayraç yerinde kalır.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      expect(store.guides, contains('guide_bookmark'));
      expect(find.byTooltip('Ayraç seçenekleri'), findsOneWidget);
      expect(store.guides, isNot(contains('guide_resume')));
      store.positions[1] = const ReadingPosition(
        pageId: 10,
        sentenceIndex: 0,
        pageText: 'Bir cümle.',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Son okuduğun konuma dönebilirsin.'), findsOneWidget);
      await tester.tap(find.text('Atla'));
      await tester.pumpAndSettle();
      expect(store.guides, contains('guide_resume'));
    },
  );

  testWidgets('new reader sees ordered guides and can read from one tap', (
    tester,
  ) async {
    final store = _DocumentStore()
      ..guides.remove('guide_read_from')
      ..guides.remove('guide_bookmark');
    final speech = FakeSpeechService();
    await openApp(tester, store, speech: speech);
    await openReader(tester);
    const description =
        'Bir cümleye dokun, ardından ‘Buradan oku’yu seçerek o konumdan dinlemeye başla.';
    expect(find.text('Buradan oku'), findsOneWidget);
    expect(find.text(description), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('Adım 1/2. Buradan oku. $description'),
      findsOneWidget,
    );
    semantics.dispose();
    await tester.tapAt(characterPosition(tester));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('read-from-sentence')), findsNothing);
    expect(speech.spoken, isEmpty);
    await tester.tap(find.text('İleri'));
    await tester.pumpAndSettle();
    expect(store.guides, contains('guide_read_from'));
    expect(find.text('Adım 2/2'), findsOneWidget);
    expect(
      find.text(
        'İşaretlediğin konumu saklamak için ayraç koyabilirsin. Okumaya devam etsen de ayraç yerinde kalır.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    expect(store.guides, contains('guide_bookmark'));
    await tester.tapAt(characterPosition(tester));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('read-from-sentence')));
    await tester.pumpAndSettle();
    expect(speech.spoken, ['Bir cümle.']);
    expect(store.positions[1]?.sentenceIndex, 0);
  });

  testWidgets('existing bookmark completion shows only the new step once', (
    tester,
  ) async {
    final store = _DocumentStore()..guides.remove('guide_read_from');
    await openApp(tester, store);
    await openReader(tester);
    expect(find.text('Buradan oku'), findsOneWidget);
    expect(find.text('Adım 1/1'), findsOneWidget);
    expect(find.text('İleri'), findsNothing);
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    expect(store.guides, containsAll(['guide_read_from', 'guide_bookmark']));
    expect(
      find.textContaining(
        'İşaretlediğin konumu saklamak için ayraç koyabilirsin.',
      ),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await openApp(tester, store);
    await openReader(tester);
    expect(find.text('Buradan oku'), findsNothing);
  });

  testWidgets('restarting guides includes the new reading step', (
    tester,
  ) async {
    final store = _DocumentStore();
    await openApp(tester, store);
    await tester.tap(find.byTooltip('Diğer seçenekler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kullanım rehberi'));
    await tester.pumpAndSettle();
    expect(store.guides, isNot(contains('guide_read_from')));
    await tester.tap(find.text('Atla'));
    await tester.pumpAndSettle();
    await openReader(tester);
    expect(find.text('Buradan oku'), findsOneWidget);
    expect(find.text('İleri'), findsOneWidget);
  });

  testWidgets('back skips new reading and bookmark guides without exiting', (
    tester,
  ) async {
    final store = _DocumentStore()
      ..guides.remove('guide_read_from')
      ..guides.remove('guide_bookmark');
    await openApp(tester, store);
    await openReader(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ayraç seçenekleri'), findsOneWidget);
    expect(
      store.guides,
      containsAll(['guide_resume', 'guide_read_from', 'guide_bookmark']),
    );
  });

  testWidgets(
    'blank page defers read-from guide without hiding bookmark guide',
    (tester) async {
      final store = _DocumentStore(text: '   ')
        ..guides.remove('guide_read_from')
        ..guides.remove('guide_bookmark');
      await openApp(tester, store);
      await openReader(tester);
      expect(find.text('Buradan oku'), findsNothing);
      expect(
        find.textContaining(
          'İşaretlediğin konumu saklamak için ayraç koyabilirsin.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      expect(store.guides, contains('guide_bookmark'));
      expect(store.guides, isNot(contains('guide_read_from')));
    },
  );

  testWidgets('reader text selection defers the new guide', (tester) async {
    final store = _DocumentStore();
    await openApp(tester, store);
    await openReader(tester);
    await tester.longPressAt(characterPosition(tester));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('saved-reading-text')),
    );
    expect(field.controller!.selection.isCollapsed, isFalse);
    final manager = tester.widget<GuideScope>(find.byType(GuideScope)).manager;
    manager.restart();
    expect(manager.begin(GuideGroup.home), isTrue);
    manager.complete(GuideGroup.home);
    await tester.pumpAndSettle();
    expect(find.text('Buradan oku'), findsNothing);
    final editable = tester.state<EditableTextState>(
      find.descendant(
        of: find.byKey(const ValueKey('saved-reading-text')),
        matching: find.byType(EditableText),
      ),
    );
    editable.hideToolbar();
    field.controller!.selection = const TextSelection.collapsed(offset: 0);
    await tester.pumpAndSettle();
    expect(find.text('Buradan oku'), findsOneWidget);
  });

  testWidgets('reader guidance waits for listening to stop', (tester) async {
    final store = _DocumentStore();
    final speech = FakeSpeechService();
    await openApp(tester, store, speech: speech);
    await openReader(tester);
    await tester.tap(find.text('Sesli oku'));
    await tester.pumpAndSettle();
    expect(speech.isSpeaking, isTrue);
    final manager = tester.widget<GuideScope>(find.byType(GuideScope)).manager;
    manager.restart();
    expect(manager.begin(GuideGroup.home), isTrue);
    manager.complete(GuideGroup.home);
    await tester.pumpAndSettle();
    expect(find.text('Buradan oku'), findsNothing);
    await tester.tap(find.text('Durdur'));
    await tester.pumpAndSettle();
    expect(find.text('Buradan oku'), findsOneWidget);
  });

  testWidgets('reader guidance waits until editing ends', (tester) async {
    final store = _DocumentStore();
    await openApp(tester, store);
    await openReader(tester);
    await tester.tap(find.byTooltip('Düzenle'));
    await tester.pumpAndSettle();
    final manager = tester.widget<GuideScope>(find.byType(GuideScope)).manager;
    manager.restart();
    expect(manager.begin(GuideGroup.home), isTrue);
    manager.complete(GuideGroup.home);
    await tester.pumpAndSettle();
    expect(find.text('Buradan oku'), findsNothing);
    await tester.ensureVisible(find.text('Düzenlemekten vazgeç'));
    await tester.tap(find.text('Düzenlemekten vazgeç'));
    await tester.pumpAndSettle();
    expect(find.text('Buradan oku'), findsOneWidget);
  });

  testWidgets('new reader guide is usable with large text on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = _DocumentStore()
      ..guides.remove('guide_read_from')
      ..guides.remove('guide_bookmark');
    await openApp(tester, store);
    await openReader(tester);
    expect(find.text('Buradan oku'), findsOneWidget);
    await tester.ensureVisible(find.text('İleri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('İleri'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tamam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    expect(store.guides, containsAll(['guide_read_from', 'guide_bookmark']));
    expect(tester.takeException(), isNull);
  });

  testWidgets('back skips the recorded-document group without leaving reader', (
    tester,
  ) async {
    final store = _DocumentStore()
      ..guides.remove('guide_resume')
      ..guides.remove('guide_bookmark');
    await openApp(tester, store);
    await tester.tap(find.byTooltip('Kayıtlarım'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('document-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('page-10')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ayraç seçenekleri'), findsOneWidget);
    expect(store.guides, containsAll(['guide_resume', 'guide_bookmark']));
  });

  testWidgets('OCR guide waits for recognition to finish', (tester) async {
    final store = FakePreferencesStore()..guides.remove('guide_text');
    final result = Completer<String>();
    final image = MemoryImage(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    await tester.pumpWidget(
      ReadingAssistantApp(
        store: store,
        pickerService: FakeImagePickerService(
          onPickMultiple: () async => [XFile('a')],
        ),
        textRecognitionService: FakeTextRecognitionService(
          (_) => result.future,
        ),
        previewImageBuilder: (_) => image,
        speechService: FakeSpeechService(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galeriden görsel seç'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Metni çıkar'));
    await tester.tap(find.text('Metni çıkar'));
    await tester.pump();
    expect(
      find.text('Metni kontrol edip gerektiğinde düzeltebilirsin.'),
      findsNothing,
    );
    result.complete('Tanınan metin.');
    await tester.pumpAndSettle();
    expect(
      find.text('Metni kontrol edip gerektiğinde düzeltebilirsin.'),
      findsOneWidget,
    );
  });

  testWidgets('active listening postpones the text guide until stopped', (
    tester,
  ) async {
    final store = FakePreferencesStore();
    final speech = FakeSpeechService();
    await tester.pumpWidget(
      ReadingAssistantApp(
        store: store,
        pickerService: FakeImagePickerService(),
        speechService: speech,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Metin yaz veya yapıştır'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('import-text')),
      'Bir metin.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sesli oku'));
    await tester.pumpAndSettle();
    expect(speech.isSpeaking, isTrue);
    final manager = tester.widget<GuideScope>(find.byType(GuideScope)).manager;
    manager.restart();
    expect(manager.begin(GuideGroup.home), isTrue);
    manager.complete(GuideGroup.home);
    await tester.pumpAndSettle();
    expect(
      find.text('Metni kontrol edip gerektiğinde düzeltebilirsin.'),
      findsNothing,
    );
    await tester.tap(find.text('Durdur'));
    await tester.pumpAndSettle();
    expect(
      find.text('Metni kontrol edip gerektiğinde düzeltebilirsin.'),
      findsOneWidget,
    );
  });

  testWidgets('background and dialog defer guidance until route is ready', (
    tester,
  ) async {
    final store = FakePreferencesStore()..guides.clear();
    final manager = GuideManager(store);
    await manager.load();
    final target = GlobalKey();
    final nav = GlobalKey<NavigatorState>();
    var enabled = false;
    late StateSetter update;
    await tester.pumpWidget(
      GuideScope(
        manager: manager,
        child: MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [manager.routes],
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return GuideHost(
                offers: [
                  GuideOffer(
                    group: GuideGroup.home,
                    enabled: enabled,
                    steps: [GuideStep(target, 'Rehber')],
                  ),
                ],
                child: Scaffold(
                  body: ElevatedButton(
                    key: target,
                    onPressed: () {},
                    child: const Text('Hedef'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    showDialog<void>(
      context: nav.currentContext!,
      builder: (_) => const AlertDialog(content: Text('Açık diyalog')),
    );
    await tester.pumpAndSettle();
    update(() => enabled = true);
    await tester.pumpAndSettle();
    expect(find.text('Rehber'), findsNothing);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Rehber'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(manager.active, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Rehber'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    manager.dispose();
  });
  testWidgets('guide read and write failures leave app usable', (tester) async {
    final failedRead = FakePreferencesStore()
      ..guideReadError = StateError('read');
    await openApp(tester, failedRead);
    expect(
      find.text('Kullanım rehberi yüklenemedi. Uygulamayı kullanabilirsin.'),
      findsOneWidget,
    );
    expect(find.text('Galeriden görsel seç'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final failedWrite = FakePreferencesStore()
      ..guides.clear()
      ..guideWriteError = StateError('write');
    await openApp(tester, failedWrite);
    await tester.tap(find.text('Atla'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Kullanım rehberi kaydedilemedi. Daha sonra tekrar gösterilebilir.',
      ),
      findsOneWidget,
    );
    expect(find.text('Galeriden görsel seç'), findsOneWidget);
  });

  testWidgets('guide remains usable in landscape with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 480);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = FakePreferencesStore()..guides.clear();
    await openApp(tester, store);
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.text('İleri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İleri'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Tamam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    expect(store.guides, contains('guide_home'));
    expect(tester.takeException(), isNull);
  });
}

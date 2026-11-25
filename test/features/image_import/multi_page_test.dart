import '../listening/reader_controls_test_utils.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
import 'package:reading_assistant/features/image_import/presentation/multi_page_screen.dart';
import 'package:reading_assistant/features/image_import/presentation/widgets/image_preview.dart';
import 'package:reading_assistant/features/image_import/services/image_picker_service.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/add_page_screen.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';

import '../listening/fake_preferences_store.dart';
import '../listening/fake_speech_service.dart';
import 'test_doubles.dart';

final _image = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

class _DelayedImage extends ImageProvider<_DelayedImage> {
  final ready = Completer<ui.Image>();
  final Uint8List bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 20, height: 60)),
  );

  @override
  Future<_DelayedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _DelayedImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    ready.future.then((image) => ImageInfo(image: image.clone())),
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, Widget screen) async {
  final preferences = ReadingPreferences(store: FakePreferencesStore());
  await preferences.load();
  await tester.pumpWidget(
    ReadingPreferencesScope(
      preferences: preferences,
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _draft(int id) => find.byKey(ValueKey('draft-$id'));
Finder _action(int id, String label) =>
    find.descendant(of: _draft(id), matching: find.text(label));
Finder get _field => find.byKey(const ValueKey('import-text'));

class _BatchStore extends DocumentStore {
  List<String>? texts;
  int? owner;
  String? title;
  DocumentCategory? category;
  @override
  Future<List<DocumentCategory>> categories() async => [
    DocumentCategory.note,
    DocumentCategory.book,
  ];
  @override
  Future<int> savePages({
    required String title,
    required DocumentCategory category,
    required List<String> texts,
  }) async {
    this.title = title;
    this.category = category;
    this.texts = texts;
    return 1;
  }

  @override
  Future<void> appendPages({
    required int documentId,
    required List<String> texts,
  }) async {
    owner = documentId;
    this.texts = texts;
  }
}

class _SequencePicker extends FakeImagePickerService {
  final List<List<XFile>> selections = [];
  final List<int?> limits = [];
  final List<XFile?> cameras = [];
  final List<XFile?> replacements = [];
  final List<bool> recoveryTargets = [];
  Completer<List<XFile>>? selectionGate;
  Object? cameraError;

  @override
  Future<List<XFile>> pickMultipleFromGallery({
    required bool recoverToHome,
    int? limit,
  }) async {
    limits.add(limit);
    recoveryTargets.add(recoverToHome);
    if (selectionGate case final gate?) return gate.future;
    return selections.removeAt(0);
  }

  @override
  Future<XFile?> takePhoto({required bool recoverToHome}) async {
    recoveryTargets.add(recoverToHome);
    if (cameraError case final error?) throw error;
    return cameras.removeAt(0);
  }

  @override
  Future<XFile?> pickFromGallery({bool recoverToHome = true}) async {
    recoveryTargets.add(recoverToHome);
    return replacements.removeAt(0);
  }
}

Future<void> _open(WidgetTester tester, int id) async {
  await _tap(
    tester,
    find.descendant(of: _draft(id), matching: find.byType(InkWell)).first,
  );
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('batch drafts share the originating speech service', (
    tester,
  ) async {
    await _show(
      tester,
      ImageImportScreen(
        pickerService: FakeImagePickerService(
          onPickMultiple: () async => [XFile('a'), XFile('b')],
        ),
        textRecognitionService: FakeTextRecognitionService(
          (_) async => 'metin',
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
      ),
    );
    await _tap(tester, find.text('Galeriden görsel seç'));
    final service = tester
        .widget<MultiPageScreen>(find.byType(MultiPageScreen))
        .speechService;
    expect(service, isNotNull);
    await _open(tester, 0);
    final editor = tester.widget<ImageImportScreen>(
      find.byType(ImageImportScreen),
    );
    expect(editor.speechService, same(service));
  });

  for (final saveFirst in [false, true]) {
    testWidgets(
      'first ${saveFirst ? 'save' : 'page open'} reveals error after image layout',
      (tester) async {
        tester.view.physicalSize = const Size(320, 560);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final image = _DelayedImage();
        final decoded = await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(image.bytes);
          final frame = await codec.getNextFrame();
          codec.dispose();
          return frame.image;
        });
        addTearDown(decoded!.dispose);
        await _show(
          tester,
          ImageImportScreen(
            pickerService: FakeImagePickerService(
              onPickMultiple: () async => [XFile('a'), XFile('b')],
            ),
            textRecognitionService: FakeTextRecognitionService(
              (path) async => path,
            ),
            rotationService: FakeImageRotationService(),
            speechService: FakeSpeechService(),
            previewImageBuilder: (_) => image,
          ),
        );
        await _tap(tester, find.text('Galeriden görsel seç'));
        if (saveFirst) {
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('save-batch')),
            200,
          );
          await _tap(tester, find.byKey(const ValueKey('save-batch')));
        } else {
          await _open(tester, 0);
        }
        final error = find.text(
          'Bu sayfanın metni boş. Metni çıkarın veya yazın.',
        );
        expect(error, findsOneWidget);
        expect(tester.testTextInput.isVisible, isFalse);
        image.ready.complete(decoded);
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(ImagePreview)).height,
          greaterThan(500),
        );
        expect(error.hitTestable(), findsOneWidget);
        expect(tester.testTextInput.isVisible, isFalse);
      },
    );
  }

  testWidgets('manual scroll cancels pending validation scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final image = _DelayedImage();
    final decoded = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(image.bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    });
    addTearDown(decoded!.dispose);
    await _show(
      tester,
      MultiPageScreen(
        files: [XFile('a')],
        pickerService: FakeImagePickerService(),
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => image,
        speechService: FakeSpeechService(),
      ),
    );
    await _open(tester, 0);
    final scroll = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('content-scroll')),
        )
        .controller!;
    await tester.drag(
      find.byKey(const ValueKey('content-scroll')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    final offset = scroll.offset;
    image.ready.complete(decoded);
    await tester.pumpAndSettle();
    expect(scroll.offset, offset);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('preview failure still reveals validation error', (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final image = _DelayedImage();
    await _show(
      tester,
      MultiPageScreen(
        files: [XFile('a')],
        pickerService: FakeImagePickerService(),
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => image,
        speechService: FakeSpeechService(),
      ),
    );
    await _open(tester, 0);
    image.ready.completeError(StateError('image unavailable'));
    await tester.pumpAndSettle();
    expect(
      find
          .text('Bu sayfanın metni boş. Metni çıkarın veya yazın.')
          .hitTestable(),
      findsOneWidget,
    );
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty OCR notice follows the edited page text', (tester) async {
    final ocr = FakeTextRecognitionService((_) async => '');
    await _show(
      tester,
      MultiPageScreen(
        files: [XFile('a'), XFile('b')],
        pickerService: FakeImagePickerService(),
        textRecognitionService: ocr,
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
      ),
    );
    final firstNotice = find.descendant(
      of: _draft(0),
      matching: find.textContaining('Görselde metin bulunamadı'),
    );
    final secondNotice = find.descendant(
      of: _draft(1),
      matching: find.textContaining('Görselde metin bulunamadı'),
    );
    await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
    expect(firstNotice, findsOneWidget);
    expect(secondNotice, findsOneWidget);
    expect(find.text('Boş sayfalar: 1, 2. Metin ekleyin.'), findsOneWidget);
    expect(_action(0, 'Sayfa metni boş.'), findsOneWidget);
    expect(_action(1, 'Sayfa metni boş.'), findsOneWidget);

    await _open(tester, 0);
    final previewError = find.text(
      'Bu sayfanın metni boş. Metni çıkarın veya yazın.',
    );
    expect(previewError, findsOneWidget);
    await tester.enterText(_field, '   ');
    await tester.pumpAndSettle();
    expect(find.textContaining('Görselde metin bulunamadı'), findsOneWidget);
    expect(previewError, findsOneWidget);
    await tester.enterText(_field, 'Elle yazılan metin');
    await tester.pumpAndSettle();
    expect(find.textContaining('Görselde metin bulunamadı'), findsNothing);
    expect(previewError, findsNothing);
    await _back(tester);
    expect(firstNotice, findsNothing);
    expect(secondNotice, findsOneWidget);
    expect(find.text('Boş sayfalar: 2. Metin ekleyin.'), findsOneWidget);
    expect(_action(0, 'Sayfa metni boş.'), findsNothing);
    expect(_action(1, 'Sayfa metni boş.'), findsOneWidget);
    expect(_action(0, 'Yeniden dene'), findsNothing);

    await _open(tester, 0);
    await tester.enterText(_field, '   ');
    await tester.pumpAndSettle();
    expect(previewError, findsOneWidget);
    expect(find.textContaining('Görselde metin bulunamadı'), findsNothing);
    await _back(tester);
    expect(find.text('Boş sayfalar: 1, 2. Metin ekleyin.'), findsOneWidget);
    expect(_action(0, 'Sayfa metni boş.'), findsOneWidget);
    expect(firstNotice, findsNothing);
    expect(secondNotice, findsOneWidget);

    await _open(tester, 0);
    await _tap(tester, find.text('Metni çıkar'));
    await _tap(tester, find.text('Üzerine yaz'));
    expect(previewError, findsOneWidget);
    expect(find.textContaining('Görselde metin bulunamadı'), findsOneWidget);
    await _back(tester);
    expect(firstNotice, findsOneWidget);
    expect(secondNotice, findsOneWidget);
    expect(find.text('Boş sayfalar: 1, 2. Metin ekleyin.'), findsOneWidget);
    expect(ocr.paths, ['a', 'b', 'a']);
  });

  testWidgets('OCR activates batch validation and retains preview validation', (
    tester,
  ) async {
    final ocr = FakeTextRecognitionService((_) async => '');
    await _show(
      tester,
      MultiPageScreen(
        files: [XFile('a'), XFile('b')],
        pickerService: FakeImagePickerService(),
        textRecognitionService: ocr,
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
      ),
    );
    await _open(tester, 0);
    final previewError = find.text(
      'Bu sayfanın metni boş. Metni çıkarın veya yazın.',
    );
    expect(previewError, findsOneWidget);
    await _tap(tester, find.text('Metni çıkar'));
    expect(previewError, findsOneWidget);
    expect(find.textContaining('Görselde metin bulunamadı'), findsOneWidget);
    await tester.enterText(_field, 'Metin');
    await tester.pumpAndSettle();
    expect(previewError, findsNothing);
    await tester.enterText(_field, '');
    await tester.pumpAndSettle();
    expect(previewError, findsOneWidget);
    expect(find.textContaining('Görselde metin bulunamadı'), findsNothing);
    await _back(tester);
    expect(find.text('Boş sayfalar: 1, 2. Metin ekleyin.'), findsOneWidget);
    expect(_action(0, 'Sayfa metni boş.'), findsOneWidget);
    expect(_action(1, 'Sayfa metni boş.'), findsOneWidget);
  });

  testWidgets('empty retry validates retained text without discarding it', (
    tester,
  ) async {
    var calls = 0;
    await _show(
      tester,
      MultiPageScreen(
        files: [XFile('a'), XFile('b')],
        pickerService: FakeImagePickerService(),
        textRecognitionService: FakeTextRecognitionService(
          (_) async => calls++ == 0 ? 'Korunan metin' : '',
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
      ),
    );
    await _open(tester, 0);
    await _tap(tester, find.text('Metni çıkar'));
    await _back(tester);
    expect(find.textContaining('Boş sayfalar:'), findsNothing);
    await _open(tester, 0);
    await _tap(tester, find.text('Metni çıkar'));
    await _tap(tester, find.text('Üzerine yaz'));
    expect(tester.widget<TextField>(_field).controller!.text, 'Korunan metin');
    expect(find.textContaining('Görselde metin bulunamadı'), findsOneWidget);
    expect(
      find.text('Bu sayfanın metni boş. Metni çıkarın veya yazın.'),
      findsNothing,
    );
    await _back(tester);
    expect(find.text('Boş sayfalar: 2. Metin ekleyin.'), findsOneWidget);
    expect(_action(0, 'Sayfa metni boş.'), findsNothing);
    expect(_action(1, 'Sayfa metni boş.'), findsOneWidget);
  });

  testWidgets('closing during a gallery addition ignores the late result', (
    tester,
  ) async {
    final picker = _SequencePicker()..selectionGate = Completer<List<XFile>>();
    await _show(
      tester,
      MultiPageScreen(
        files: [XFile('a')],
        pickerService: picker,
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
    await tester.tap(find.text('Galeriden seç'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    picker.selectionGate!.complete([XFile('late')]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('home replacement uses a draft recovery target', (tester) async {
    final picker = _SequencePicker()
      ..selections.add([XFile('a')])
      ..replacements.add(XFile('b'));
    await _show(
      tester,
      ImageImportScreen(
        pickerService: picker,
        speechService: FakeSpeechService(),
        previewImageBuilder: (_) => _image,
      ),
    );
    await _tap(tester, find.text('Galeriden görsel seç'));
    await _tap(tester, find.text('Görseli değiştir'));
    expect(picker.recoveryTargets, [true, false]);
  });

  testWidgets('pending addition is locked and cancellation keeps drafts', (
    tester,
  ) async {
    final picker = _SequencePicker()..selectionGate = Completer<List<XFile>>();
    await _show(
      tester,
      MultiPageScreen(
        files: [XFile('a'), XFile('b')],
        pickerService: picker,
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
    await tester.tap(find.text('Galeriden seç'));
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('add-draft-pages')))
          .onPressed,
      isNull,
    );
    expect(picker.limits, [18]);
    picker.selectionGate!.complete([]);
    await tester.pumpAndSettle();
    expect(_draft(0), findsOneWidget);
    expect(_draft(1), findsOneWidget);
    expect(_draft(2), findsNothing);
    picker.cameraError = StateError('camera');
    await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
    await _tap(tester, find.text('Fotoğraf çek'));
    expect(
      find.text('Görseller eklenemedi. Tekrar deneyebilirsin.'),
      findsOneWidget,
    );
    expect(_draft(0), findsOneWidget);
    expect(_draft(1), findsOneWidget);
  });

  testWidgets('gallery and camera additions preserve order and save together', (
    tester,
  ) async {
    final picker = _SequencePicker()
      ..selections.addAll([
        [XFile('a')],
        [XFile('c'), XFile('d')],
      ])
      ..cameras.add(XFile('b'))
      ..replacements.add(XFile('replacement'));
    final store = _BatchStore();
    final ocr = FakeTextRecognitionService((path) async => path);
    await _show(
      tester,
      AddPageScreen(
        documentId: 7,
        documentTitle: 'Kitap',
        store: store,
        pickerService: picker,
        textRecognitionService: ocr,
        rotationService: FakeImageRotationService(),
        speechService: FakeSpeechService(),
        previewImageBuilder: (_) => _image,
      ),
    );
    await _tap(tester, find.text('Galeriden görsel seç'));
    expect(find.byType(MultiPageScreen), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
    await _tap(tester, find.text('Fotoğraf çek').last);
    await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
    await _tap(tester, find.text('Galeriden seç'));
    expect(picker.limits, [20, 18]);
    await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
    expect(ocr.paths, ['a', 'b', 'c', 'd']);
    await _open(tester, 1);
    await _tap(tester, find.text('Görseli değiştir'));
    await _tap(tester, find.text('Metni çıkar'));
    await _back(tester);
    await _tap(tester, _action(3, 'Yukarı'));
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    expect(store.owner, 7);
    expect(store.texts, ['a', 'replacement', 'd', 'c']);
    expect(picker.recoveryTargets, [false, false, false, false]);
  });

  testWidgets('empty batch accepts a new page after removal', (tester) async {
    final picker = _SequencePicker()..cameras.add(XFile('new'));
    await _show(
      tester,
      MultiPageScreen(
        files: [XFile('a')],
        pickerService: picker,
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
      ),
    );
    await _tap(tester, _action(0, 'Kaldır'));
    expect(find.text('Henüz sayfa yok. Sayfa ekleyebilirsin.'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
    await _tap(tester, find.text('Fotoğraf çek'));
    expect(_draft(1), findsOneWidget);
  });

  testWidgets('camera draft survives adding another camera page', (
    tester,
  ) async {
    final picker = _SequencePicker()..cameras.addAll([XFile('a'), XFile('b')]);
    final ocr = FakeTextRecognitionService(
      (path) async => '${path.startsWith('/tmp/') ? 'a' : path} bir\niki',
    );
    final rotation = FakeImageRotationService();
    final speech = FakeSpeechService();
    await _show(
      tester,
      ImageImportScreen(
        pickerService: picker,
        textRecognitionService: ocr,
        rotationService: rotation,
        speechService: speech,
        previewImageBuilder: (_) => _image,
      ),
    );
    await _tap(tester, find.text('Fotoğraf çek'));
    await _tap(tester, find.text('Sağa döndür'));
    await _tap(tester, find.text('Metni çıkar'));
    await _tap(tester, find.text('Satırları birleştir'));
    await tester.enterText(_field, 'Elle düzeltme');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    tester.widget<TextField>(_field).controller!.selection =
        const TextSelection(baseOffset: 2, extentOffset: 6);
    await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
    await _tap(tester, find.text('Fotoğraf çek').last);
    expect(_draft(0), findsOneWidget);
    expect(_draft(1), findsOneWidget);
    expect(picker.recoveryTargets, [true, false]);
    await _open(tester, 0);
    expect(tester.widget<TextField>(_field).controller!.text, 'Elle düzeltme');
    expect(
      tester.widget<TextField>(_field).controller!.selection,
      const TextSelection(baseOffset: 2, extentOffset: 6),
    );
    expect(find.textContaining('90° döndürüldü'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      false,
    );
    await _tap(tester, find.text('Satırları birleştir'));
    await _tap(tester, find.text('Metni sil ve uygula'));
    expect(tester.widget<TextField>(_field).controller!.text, 'a bir iki');
    await _back(tester);
    await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
    expect(ocr.paths, ['/tmp/rotated_1.jpg', 'b']);
    await _back(tester);
    expect(
      find.text(
        'Eklenen sayfa taslakları kaybolacak; ilk sayfanın taslağı korunacak.',
      ),
      findsOneWidget,
    );
    await _tap(tester, find.text('Kaydetmeden çık'));
    expect(find.byType(MultiPageScreen), findsNothing);
    expect(tester.widget<TextField>(_field).controller!.text, 'Elle düzeltme');
    expect(find.textContaining('90° döndürüldü'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      false,
    );
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pumpAndSettle();
    expect(speech.spoken, ['Elle düzeltme']);
    await tapReadingControl(tester, 'Durdur');
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Satırları birleştir'));
    await _tap(tester, find.text('Metni sil ve uygula'));
    expect(tester.widget<TextField>(_field).controller!.text, 'a bir iki');
    await _tap(tester, find.text('Temizle'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Temizle'));
    expect(tester.widget<TextField>(_field).controller!.text, isEmpty);
    expect(find.byTooltip('Sesli oku'), findsNothing);
    expect(speech.spoken, ['Elle düzeltme']);
  });

  for (final addingPage in [false, true]) {
    testWidgets(
      'discard restores an empty ${addingPage ? 'added page' : 'home draft'}',
      (tester) async {
        final picker = _SequencePicker()
          ..cameras.addAll([XFile('a'), XFile('b')]);
        final speech = FakeSpeechService();
        await _show(
          tester,
          ImageImportScreen(
            pickerService: picker,
            textRecognitionService: FakeTextRecognitionService((_) async => ''),
            rotationService: FakeImageRotationService(),
            speechService: speech,
            previewImageBuilder: (_) => _image,
            onSavePage: addingPage ? (_) async {} : null,
            onSavePages: addingPage ? (_) async {} : null,
          ),
        );
        await _tap(tester, find.text('Fotoğraf çek'));
        await _tap(tester, find.text('Metni çıkar'));
        expect(
          find.textContaining('Görselde metin bulunamadı'),
          findsOneWidget,
        );
        await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
        await _tap(tester, find.text('Fotoğraf çek').last);
        await _open(tester, 0);
        await tester.enterText(_field, 'Yalnızca taslak');
        await _back(tester);
        await _back(tester);
        await _tap(tester, find.text('Vazgeç'));
        expect(_draft(0), findsOneWidget);
        expect(_draft(1), findsOneWidget);
        await _open(tester, 0);
        expect(
          tester.widget<TextField>(_field).controller!.text,
          'Yalnızca taslak',
        );
        await _back(tester);
        await _back(tester);
        await _tap(tester, find.text('Kaydetmeden çık'));
        expect(find.byType(MultiPageScreen), findsNothing);
        expect(find.byType(ImagePreview), findsOneWidget);
        expect(
          find.textContaining('Görselde metin bulunamadı'),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey(addingPage ? 'new-page-text' : 'import-text')),
          findsNothing,
        );
        expect(find.byTooltip('Sesli oku'), findsNothing);
        if (addingPage) {
          expect(
            tester
                .widget<TextButton>(find.byKey(const ValueKey('save-page')))
                .onPressed,
            isNull,
          );
        } else {
          expect(
            tester
                .widget<IconButton>(
                  find
                      .ancestor(
                        of: find.byTooltip('Metni kaydet'),
                        matching: find.byType(IconButton),
                      )
                      .first,
                )
                .onPressed,
            isNull,
          );
        }
        expect(speech.spoken, isEmpty);
      },
    );
  }

  testWidgets('removing the first batch page leaves the single draft intact', (
    tester,
  ) async {
    final picker = _SequencePicker()..cameras.addAll([XFile('a'), XFile('b')]);
    final speech = FakeSpeechService();
    await _show(
      tester,
      ImageImportScreen(
        pickerService: picker,
        textRecognitionService: FakeTextRecognitionService((_) async => 'Önce'),
        rotationService: FakeImageRotationService(),
        speechService: speech,
        previewImageBuilder: (_) => _image,
      ),
    );
    await _tap(tester, find.text('Fotoğraf çek'));
    await _tap(tester, find.text('Metni çıkar'));
    await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
    await _tap(tester, find.text('Fotoğraf çek').last);
    await _open(tester, 0);
    await _tap(tester, find.text('Temizle'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Temizle'));
    expect(tester.widget<TextField>(_field).controller!.text, isEmpty);
    expect(find.byTooltip('Sesli oku'), findsNothing);
    await _back(tester);
    await _tap(tester, _action(0, 'Kaldır'));
    expect(_draft(0), findsNothing);
    await _back(tester);
    await _tap(tester, find.text('Kaydetmeden çık'));
    expect(find.byType(ImagePreview), findsOneWidget);
    expect(tester.widget<TextField>(_field).controller!.text, 'Önce');
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pumpAndSettle();
    expect(speech.spoken, ['Önce']);
  });

  testWidgets('single to batch save appends edited pages and returns', (
    tester,
  ) async {
    final picker = _SequencePicker()..cameras.addAll([XFile('a'), XFile('b')]);
    final store = _BatchStore();
    await _show(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<int>(
              context,
              MaterialPageRoute(
                builder: (_) => AddPageScreen(
                  documentId: 7,
                  documentTitle: 'Kitap',
                  store: store,
                  pickerService: picker,
                  textRecognitionService: FakeTextRecognitionService(
                    (path) async => path,
                  ),
                  rotationService: FakeImageRotationService(),
                  previewImageBuilder: (_) => _image,
                  speechService: FakeSpeechService(),
                ),
              ),
            ),
            child: const Text('Aç'),
          ),
        ),
      ),
    );
    await _tap(tester, find.text('Aç'));
    await _tap(tester, find.text('Fotoğraf çek'));
    await _tap(tester, find.text('Metni çıkar'));
    await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
    await _tap(tester, find.text('Fotoğraf çek').last);
    await _open(tester, 0);
    await tester.enterText(_field, 'Düzenlenen ilk sayfa');
    await _back(tester);
    await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    expect(store.owner, 7);
    expect(store.texts, ['Düzenlenen ilk sayfa', 'b']);
    expect(find.byType(AddPageScreen), findsNothing);
    expect(find.text('Aç'), findsOneWidget);
  });

  testWidgets('after discard the restored added page is spoken and saved', (
    tester,
  ) async {
    final picker = _SequencePicker()..cameras.addAll([XFile('a'), XFile('b')]);
    final speech = FakeSpeechService();
    String? saved;
    await _show(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<int>(
              context,
              MaterialPageRoute(
                builder: (_) => ImageImportScreen(
                  pickerService: picker,
                  textRecognitionService: FakeTextRecognitionService(
                    (path) async => path,
                  ),
                  rotationService: FakeImageRotationService(),
                  previewImageBuilder: (_) => _image,
                  speechService: speech,
                  pageDocumentTitle: 'Kitap',
                  onSavePage: (text) async => saved = text,
                  onSavePages: (_) async {},
                ),
              ),
            ),
            child: const Text('Aç'),
          ),
        ),
      ),
    );
    await _tap(tester, find.text('Aç'));
    await _tap(tester, find.text('Fotoğraf çek'));
    await _tap(tester, find.text('Metni çıkar'));
    await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
    await _tap(tester, find.text('Fotoğraf çek').last);
    await _open(tester, 0);
    await tester.enterText(_field, 'Terk edilen değişiklik');
    await _back(tester);
    await _back(tester);
    await _tap(tester, find.text('Kaydetmeden çık'));
    final text = tester
        .widget<TextField>(find.byKey(const ValueKey('new-page-text')))
        .controller!
        .text;
    expect(text, 'a');
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pumpAndSettle();
    expect(speech.spoken, [text]);
    await tapReadingControl(tester, 'Durdur');
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('save-page')));
    expect(saved, text);
    expect(find.text('Aç'), findsOneWidget);
  });

  testWidgets('single to batch save creates a document and returns home', (
    tester,
  ) async {
    final picker = _SequencePicker()..cameras.addAll([XFile('a'), XFile('b')]);
    final store = _BatchStore();
    await _show(
      tester,
      ImageImportScreen(
        pickerService: picker,
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
        store: store,
      ),
    );
    await _tap(tester, find.text('Fotoğraf çek'));
    await _tap(tester, find.text('Metni çıkar'));
    await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
    await _tap(tester, find.text('Fotoğraf çek').last);
    await _open(tester, 0);
    await tester.enterText(_field, 'Toplu düzenleme');
    await _back(tester);
    await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    await tester.enterText(find.byType(TextFormField).first, 'Belge');
    await _tap(tester, find.text('2 sayfayı ekle').last);
    expect(store.texts, ['Toplu düzenleme', 'b']);
    expect(find.byType(MultiPageScreen), findsNothing);
    expect(find.text('Sayfalar kaydedildi.'), findsOneWidget);
    expect(tester.widget<TextField>(_field).controller!.text, 'a');
  });

  testWidgets('late batch OCR does not change the discarded original', (
    tester,
  ) async {
    final picker = _SequencePicker()..cameras.addAll([XFile('a'), XFile('b')]);
    final pending = Completer<String>();
    await _show(
      tester,
      ImageImportScreen(
        pickerService: picker,
        textRecognitionService: FakeTextRecognitionService(
          (_) => pending.future,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
      ),
    );
    await _tap(tester, find.text('Fotoğraf çek'));
    await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
    await _tap(tester, find.text('Fotoğraf çek').last);
    await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
    await _back(tester);
    await _tap(tester, find.text('Kaydetmeden çık'));
    pending.complete('Geç gelen metin');
    await tester.pumpAndSettle();
    expect(find.byType(MultiPageScreen), findsNothing);
    expect(_field, findsNothing);
    expect(find.byTooltip('Sesli oku'), findsNothing);
    expect(find.byType(ImagePreview), findsOneWidget);
  });

  testWidgets(
    'gallery selections respect capacity and removal opens it again',
    (tester) async {
      final picker = _SequencePicker()
        ..selections.addAll([
          [for (var i = 0; i < 21; i++) XFile('$i')],
          [for (var i = 0; i < 20; i++) XFile('$i')],
          [XFile('extra'), XFile('overflow')],
          [XFile('extra')],
        ]);
      await _show(
        tester,
        ImageImportScreen(
          pickerService: picker,
          textRecognitionService: FakeTextRecognitionService(
            (path) async => path,
          ),
          rotationService: FakeImageRotationService(),
          speechService: FakeSpeechService(),
          previewImageBuilder: (_) => _image,
        ),
      );
      await _tap(tester, find.text('Galeriden görsel seç'));
      expect(
        find.text('Tek seferde en fazla 20 sayfa ekleyebilirsin.'),
        findsOneWidget,
      );
      expect(find.byType(MultiPageScreen), findsNothing);
      await _tap(tester, find.text('Galeriden görsel seç'));
      expect(find.text('20 sayfa sınırına ulaştın.'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('add-draft-pages')),
            )
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(_action(19, 'Kaldır'), 300);
      await _tap(tester, _action(19, 'Kaldır'));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('add-draft-pages')),
        -300,
      );
      await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
      await _tap(tester, find.text('Galeriden seç'));
      expect(
        find.text('Bu taslağa en fazla 1 sayfa daha ekleyebilirsin.'),
        findsOneWidget,
      );
      expect(_draft(20), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
      await _tap(tester, find.text('Galeriden seç'));
      expect(find.text('20 sayfa sınırına ulaştın.'), findsOneWidget);
      expect(picker.limits, [20, 20, 1, 1]);
    },
  );

  testWidgets('oversized recovered batch is rejected', (tester) async {
    await _show(
      tester,
      ImageImportScreen(
        pickerService: FakeImagePickerService(
          canRecoverLostImage: true,
          onRetrieveLost: () async => throw LostMultipleImagesException([
            for (var i = 0; i < 21; i++) XFile('$i'),
          ]),
        ),
        speechService: FakeSpeechService(),
        previewImageBuilder: (_) => _image,
      ),
    );
    expect(find.byType(MultiPageScreen), findsNothing);
    expect(
      find.text('Tek seferde en fazla 20 sayfa ekleyebilirsin.'),
      findsOneWidget,
    );
  });

  testWidgets('a recovered single gallery result opens the single editor', (
    tester,
  ) async {
    await _show(
      tester,
      ImageImportScreen(
        pickerService: FakeImagePickerService(
          canRecoverLostImage: true,
          onRetrieveLost: () async =>
              throw LostMultipleImagesException([XFile('a')]),
        ),
        speechService: FakeSpeechService(),
        previewImageBuilder: (_) => _image,
      ),
    );
    expect(find.byType(MultiPageScreen), findsNothing);
    expect(find.text('Görseli değiştir'), findsOneWidget);
  });

  testWidgets('lost multi-selection opens all recovered drafts', (
    tester,
  ) async {
    await _show(
      tester,
      ImageImportScreen(
        pickerService: FakeImagePickerService(
          canRecoverLostImage: true,
          onRetrieveLost: () async =>
              throw LostMultipleImagesException([XFile('a'), XFile('b')]),
        ),
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        speechService: FakeSpeechService(),
        previewImageBuilder: (_) => _image,
      ),
    );
    expect(_draft(0), findsOneWidget);
    expect(_draft(1), findsOneWidget);
  });

  testWidgets(
    'batch controls remain reachable at large text on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _show(
        tester,
        MultiPageScreen(
          files: [XFile('a'), XFile('b')],
          pickerService: FakeImagePickerService(),
          textRecognitionService: FakeTextRecognitionService(
            (path) async => path,
          ),
          rotationService: FakeImageRotationService(),
          previewImageBuilder: (_) => _image,
          speechService: FakeSpeechService(),
        ),
      );
      await _tap(tester, find.byKey(const ValueKey('add-draft-pages')));
      expect(find.text('Galeriden seç').hitTestable(), findsOneWidget);
      expect(find.text('Fotoğraf çek').hitTestable(), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(_action(1, 'Yukarı'), 200);
      await tester.pumpAndSettle();
      expect(_action(1, 'Yukarı').hitTestable(), findsOneWidget);
      await _tap(tester, _action(1, 'Yukarı'));
      await tester.ensureVisible(find.byKey(const ValueKey('save-batch')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('save-batch')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty page explanation is visible at large system text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final image = _DelayedImage();
    final decoded = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(image.bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    });
    addTearDown(decoded!.dispose);
    await _show(
      tester,
      MultiPageScreen(
        files: [XFile('a')],
        pickerService: FakeImagePickerService(),
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => image,
        speechService: FakeSpeechService(),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('save-batch')),
      200,
    );
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    final error = find.text('Bu sayfanın metni boş. Metni çıkarın veya yazın.');
    image.ready.complete(decoded);
    await tester.pumpAndSettle();
    expect(error.hitTestable(), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'multi selection cancellation preserves existing text and selection',
    (tester) async {
      final picker = FakeImagePickerService(onPickMultiple: () async => []);
      await _show(
        tester,
        ImageImportScreen(
          pickerService: picker,
          speechService: FakeSpeechService(),
          previewImageBuilder: (_) => _image,
        ),
      );
      await _tap(tester, find.text('Metin yaz veya yapıştır'));
      await tester.enterText(_field, 'Korunan taslak');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('pick-multiple')));
      expect(
        tester.widget<TextField>(_field).controller!.text,
        'Korunan taslak',
      );
      expect(find.byType(MultiPageScreen), findsNothing);
    },
  );

  testWidgets('new document asks for title and category once', (tester) async {
    final store = _BatchStore();
    await _show(
      tester,
      ImageImportScreen(
        pickerService: FakeImagePickerService(
          onPickMultiple: () async => [XFile('a'), XFile('b')],
        ),
        textRecognitionService: FakeTextRecognitionService(
          (path) async => 'Bir',
        ),
        rotationService: FakeImageRotationService(),
        speechService: FakeSpeechService(),
        previewImageBuilder: (_) => _image,
        store: store,
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('pick-multiple')));
    await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    await tester.enterText(find.byType(TextFormField).first, 'Belge');
    await _tap(tester, find.text('2 sayfayı ekle').last);
    expect(store.title, 'Belge');
    expect(store.category, DocumentCategory.note);
    expect(store.texts, ['Bir', 'Bir']);
    expect(find.byType(MultiPageScreen), findsNothing);
  });

  testWidgets('existing document appends chosen pages to its owner', (
    tester,
  ) async {
    final store = _BatchStore();
    await _show(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<int>(
              context,
              MaterialPageRoute(
                builder: (_) => AddPageScreen(
                  documentId: 7,
                  documentTitle: 'Kitap',
                  store: store,
                  pickerService: FakeImagePickerService(
                    onPickMultiple: () async => [XFile('a'), XFile('b')],
                  ),
                  textRecognitionService: FakeTextRecognitionService(
                    (path) async => path,
                  ),
                  rotationService: FakeImageRotationService(),
                  previewImageBuilder: (_) => _image,
                  speechService: FakeSpeechService(),
                ),
              ),
            ),
            child: const Text('Aç'),
          ),
        ),
      ),
    );
    await _tap(tester, find.text('Aç'));
    await _tap(tester, find.byKey(const ValueKey('pick-multiple')));
    await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    expect(store.owner, 7);
    expect(store.texts, ['a', 'b']);
    expect(find.byType(AddPageScreen), findsNothing);
  });

  testWidgets(
    'batch pages keep independent join settings through OCR and navigation',
    (tester) async {
      final ocr = FakeTextRecognitionService((path) async => '$path bir\niki');
      await _show(
        tester,
        MultiPageScreen(
          files: [XFile('a'), XFile('b')],
          pickerService: FakeImagePickerService(),
          textRecognitionService: ocr,
          rotationService: FakeImageRotationService(),
          previewImageBuilder: (_) => _image,
          speechService: FakeSpeechService(),
        ),
      );
      await _open(tester, 0);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await _tap(tester, find.text('Satırları birleştir'));
      await _back(tester);
      await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
      await _open(tester, 0);
      expect(tester.widget<TextField>(_field).controller!.text, 'a bir\niki');
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await _tap(tester, find.text('Metni çıkar'));
      await _tap(tester, find.text('Üzerine yaz'));
      expect(tester.widget<TextField>(_field).controller!.text, 'a bir\niki');
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await _back(tester);
      await _open(tester, 1);
      expect(tester.widget<TextField>(_field).controller!.text, 'b bir iki');
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    },
  );

  testWidgets('adding a single page uses joined OCR by default', (
    tester,
  ) async {
    await _show(
      tester,
      AddPageScreen(
        documentId: 7,
        documentTitle: 'Kitap',
        store: _BatchStore(),
        pickerService: FakeImagePickerService(onPick: () async => XFile('a')),
        textRecognitionService: FakeTextRecognitionService(
          (_) async => 'bir\niki',
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
      ),
    );
    await _tap(tester, find.text('Galeriden görsel seç'));
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    await _tap(tester, find.text('Metni çıkar'));
    final field = find.byKey(const ValueKey('new-page-text'));
    expect(tester.widget<TextField>(field).controller!.text, 'bir iki');
  });

  testWidgets('existing page draft is not discarded without confirmation', (
    tester,
  ) async {
    final store = _BatchStore();
    await _show(
      tester,
      AddPageScreen(
        documentId: 7,
        documentTitle: 'Kitap',
        store: store,
        pickerService: FakeImagePickerService(
          onPickMultiple: () async => [XFile('a')],
        ),
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
      ),
    );
    await _tap(tester, find.text('Metin yaz veya yapıştır'));
    final field = find.byKey(const ValueKey('new-page-text'));
    await tester.enterText(field, 'Taslağım');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('pick-multiple')));
    expect(find.text('Düzenlediğin metin silinsin mi?'), findsOneWidget);
    await _tap(tester, find.text('Vazgeç'));
    expect(tester.widget<TextField>(field).controller!.text, 'Taslağım');
    expect(find.byType(MultiPageScreen), findsNothing);
  });

  testWidgets('leaving during OCR drops late results and stops processing', (
    tester,
  ) async {
    final gate = Completer<String>();
    final ocr = FakeTextRecognitionService((path) => gate.future);
    await _show(
      tester,
      ImageImportScreen(
        pickerService: FakeImagePickerService(
          onPickMultiple: () async => [XFile('a'), XFile('b')],
        ),
        textRecognitionService: ocr,
        rotationService: FakeImageRotationService(),
        speechService: FakeSpeechService(),
        previewImageBuilder: (_) => _image,
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('pick-multiple')));
    await tester.tap(find.text('Tüm sayfalardan metin çıkar'));
    await tester.pump();
    expect(find.text('1 / 2 işleniyor'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-batch')))
          .onPressed,
      isNull,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Kaydetmeden çık'));
    gate.complete('geç sonuç');
    await tester.pumpAndSettle();
    expect(ocr.paths, ['a']);
    expect(find.byType(MultiPageScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'drafts stay with images through OCR, reorder, removal and retry',
    (tester) async {
      var failures = 0;
      final ocr = FakeTextRecognitionService((path) async {
        if (path == 'b' && failures++ == 0) throw StateError('OCR');
        return '$path ilk\nsatır';
      });
      final picker = FakeImagePickerService(
        onPickMultiple: () async => [XFile('a'), XFile('b'), XFile('c')],
      );
      await _show(
        tester,
        ImageImportScreen(
          pickerService: picker,
          textRecognitionService: ocr,
          rotationService: FakeImageRotationService(),
          speechService: FakeSpeechService(),
          previewImageBuilder: (_) => _image,
        ),
      );
      await _tap(tester, find.byKey(const ValueKey('pick-multiple')));
      await _open(tester, 0);
      await tester.enterText(_field, 'Elle yazılan');
      await _back(tester);
      await _tap(tester, find.text('Tüm sayfalardan metin çıkar'));
      expect(ocr.paths, ['b', 'c']);
      expect(_action(1, 'Yeniden dene'), findsOneWidget);
      await _tap(tester, _action(1, 'Yeniden dene'));
      expect(ocr.paths, ['b', 'c', 'b']);
      await _open(tester, 1);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      await _tap(tester, find.text('Metni çıkar'));
      expect(find.text('Metnin üzerine yazılsın mı?'), findsOneWidget);
      await _tap(tester, find.text('Vazgeç'));
      expect(ocr.paths, ['b', 'c', 'b']);
      expect(tester.widget<TextField>(_field).controller!.text, 'b ilk satır');
      await _tap(tester, find.text('Satırları birleştir'));
      expect(tester.widget<TextField>(_field).controller!.text, 'b ilk\nsatır');
      await tester.enterText(_field, 'b düzeltme');
      await _tap(tester, find.text('Satırları birleştir'));
      expect(find.text('Düzenlediğin metin silinsin mi?'), findsOneWidget);
      await _tap(tester, find.text('Vazgeç'));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      expect(tester.widget<TextField>(_field).controller!.text, 'b düzeltme');
      await _tap(tester, find.text('Sağa döndür'));
      await _back(tester);
      await _tap(tester, _action(1, 'Yukarı'));
      await _open(tester, 2);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      await _back(tester);
      await _tap(tester, _action(2, 'Kaldır'));
      await _tap(tester, find.text('Sayfayı kaldır'));
      await _open(tester, 1);
      expect(tester.widget<TextField>(_field).controller!.text, 'b düzeltme');
      expect(find.textContaining('90° döndürüldü'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      await _back(tester);
      await _open(tester, 0);
      expect(tester.widget<TextField>(_field).controller!.text, 'Elle yazılan');
      await _tap(tester, find.text('Temizle'));
      await _tap(tester, find.text('Vazgeç'));
      expect(tester.widget<TextField>(_field).controller!.text, 'Elle yazılan');
      await _tap(tester, find.text('Temizle'));
      await _tap(tester, find.text('Temizle').last);
      expect(tester.widget<TextField>(_field).controller!.text, isEmpty);
      expect(find.text('Metni çıkar'), findsOneWidget);
      await _back(tester);
      await _open(tester, 1);
      expect(tester.widget<TextField>(_field).controller!.text, 'b düzeltme');
      await _back(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Vazgeç'));
      expect(find.byType(MultiPageScreen), findsOneWidget);
      expect(_draft(0), findsOneWidget);
    },
  );

  testWidgets('blank validation and failed save keep drafts; save is guarded', (
    tester,
  ) async {
    final completer = Completer<void>();
    var calls = 0;
    List<String>? saved;
    await _show(
      tester,
      MultiPageScreen(
        files: [XFile('a'), XFile('b')],
        pickerService: FakeImagePickerService(),
        textRecognitionService: FakeTextRecognitionService(
          (path) async => path,
        ),
        rotationService: FakeImageRotationService(),
        previewImageBuilder: (_) => _image,
        speechService: FakeSpeechService(),
        onSavePages: (texts) async {
          calls++;
          saved = texts;
          if (calls == 1) throw StateError('save');
          await completer.future;
        },
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    expect(find.text('1. sayfa'), findsOneWidget);
    final error = find.text('Bu sayfanın metni boş. Metni çıkarın veya yazın.');
    expect(error, findsOneWidget);
    expect(error.hitTestable(), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.enterText(_field, '   ');
    await tester.pumpAndSettle();
    expect(error, findsOneWidget);
    await tester.enterText(_field, 'Bir');
    await tester.pumpAndSettle();
    expect(error, findsNothing);
    await _back(tester);
    expect(find.textContaining('Boş sayfalar: 2'), findsOneWidget);
    expect(_action(0, 'Sayfa metni boş.'), findsNothing);
    expect(_action(1, 'Sayfa metni boş.'), findsOneWidget);
    await _open(tester, 1);
    expect(error, findsOneWidget);
    await tester.enterText(_field, 'İki');
    await tester.pumpAndSettle();
    expect(error, findsNothing);
    await _back(tester);
    expect(find.text('Sayfa metni boş.'), findsNothing);
    await _tap(tester, _action(1, 'Yukarı'));
    await _tap(tester, find.byKey(const ValueKey('save-batch')));
    expect(calls, 1);
    expect(saved, ['İki', 'Bir']);
    expect(find.textContaining('Taslaklar korundu'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-batch')));
    await tester.pump();
    expect(calls, 2);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-batch')))
          .onPressed,
      isNull,
    );
    completer.complete();
    await tester.pumpAndSettle();
  });
}

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_controller.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';

import '../listening/fake_preferences_store.dart';
import '../listening/fake_speech_service.dart';
import 'test_doubles.dart';

void main() {
  testWidgets('unchanged crop and cancelled confirmation preserve text', (
    tester,
  ) async {
    final image = MemoryImage(img.encodePng(img.Image(width: 80, height: 40)));
    final picker = FakeImagePickerService();
    final ocr = FakeTextRecognitionService((_) async => 'OCR');
    final rotation = FakeImageRotationService();
    final controller = ImageImportController(
      pickerService: picker,
      textRecognitionService: ocr,
      rotationService: rotation,
      previewImageBuilder: (_) => image,
      initialFile: XFile('source.png'),
    );
    controller.textController.text = 'Korunan metin';
    final preferences = ReadingPreferences(store: FakePreferencesStore());
    await preferences.load();
    addTearDown(controller.dispose);
    addTearDown(preferences.dispose);
    await tester.pumpWidget(
      ReadingPreferencesScope(
        preferences: preferences,
        child: MaterialApp(
          home: ImageImportScreen(
            pickerService: picker,
            textRecognitionService: ocr,
            rotationService: rotation,
            previewImageBuilder: (_) => image,
            speechService: FakeSpeechService(),
            batchController: controller,
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    Future<void> openCrop() async {
      await tester.ensureVisible(find.text('Kırp'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kırp'));
      await tester.pump();
      await tester.runAsync(
        () => precacheImage(
          ResizeImage(
            image,
            width: 1200,
            height: 1200,
            policy: ResizeImagePolicy.fit,
          ),
          tester.element(find.byType(MaterialApp)),
        ),
      );
      await tester.pumpAndSettle();
    }

    await openCrop();
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();
    expect(find.text('Mevcut metin temizlensin mi?'), findsNothing);
    expect(controller.textController.text, 'Korunan metin');
    expect(controller.selection!.file.path, 'source.png');

    await openCrop();
    final handle = find.byKey(const ValueKey('crop-handle--1-0'));
    final drag = await tester.startGesture(tester.getCenter(handle));
    await drag.moveBy(const Offset(20, 0));
    await drag.moveBy(const Offset(30, 0));
    await drag.moveBy(const Offset(30, 0));
    await drag.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Kırpma uygulanınca mevcut metin temizlenecek. Görselden yeniden metin çıkarabilirsin.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(controller.textController.text, 'Korunan metin');
    expect(controller.selection!.file.path, 'source.png');
  });
}

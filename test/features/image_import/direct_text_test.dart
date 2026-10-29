import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
import 'package:reading_assistant/features/image_import/services/image_picker_service.dart';
import 'package:reading_assistant/features/library/presentation/save_document_dialog.dart';

import '../listening/fake_speech_service.dart';

class _Picker extends ImagePickerService {
  XFile? result;
  @override
  bool get canRecoverLostImage => false;
  @override
  Future<XFile?> pickFromGallery() async => result;
}

final _field = find.byKey(const ValueKey('import-text'));

Future<void> _show(
  WidgetTester tester,
  _Picker picker,
  FakeSpeechService speech, {
  bool returnText = false,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: ImageImportScreen(
        pickerService: picker,
        speechService: speech,
        returnText: returnText,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _create(WidgetTester tester, String text) async {
  await tester.tap(find.text('Metin yaz veya yapıştır'));
  await tester.pumpAndSettle();
  await tester.enterText(_field, text);
  FocusManager.instance.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens empty editor without OCR options', (tester) async {
    await _show(tester, _Picker(), FakeSpeechService());
    await _create(tester, '');
    expect(_field, findsOneWidget);
    expect(find.text('Satırları birleştir'), findsNothing);
    expect(find.text('Metni çıkar'), findsNothing);
    expect(find.byKey(const ValueKey('listening-panel')), findsNothing);
  });

  testWidgets('typed text can be spoken and opens existing save dialog', (
    tester,
  ) async {
    final speech = FakeSpeechService();
    await _show(tester, _Picker(), speech);
    await _create(tester, 'Yazılan metin.');
    await tester.tap(find.byTooltip('Metni kaydet'));
    await tester.pumpAndSettle();
    expect(find.byType(SaveDocumentDialog), findsOneWidget);
    // Close the dialog without persisting to the native database.
    final dialogContext = tester.element(find.byType(SaveDocumentDialog));
    Navigator.of(dialogContext).pop(false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sesli oku'));
    await tester.pump();
    await tester.pump();
    expect(speech.spoken.join(), contains('Yazılan metin.'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('blank text disables save and hides playback', (tester) async {
    await _show(tester, _Picker(), FakeSpeechService());
    await _create(tester, '   ');
    final save = find.byWidgetPredicate(
      (w) => w is IconButton && w.tooltip == 'Metni kaydet',
    );
    expect(tester.widget<IconButton>(save).onPressed, isNull);
    expect(find.byKey(const ValueKey('listening-panel')), findsNothing);
  });

  testWidgets('cancelled picker preserves manual draft', (tester) async {
    await _show(tester, _Picker(), FakeSpeechService());
    await _create(tester, 'Korunan taslak.');
    await tester.ensureVisible(find.text('Galeriden görsel seç'));
    await tester.tap(find.text('Galeriden görsel seç'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_field).controller!.text,
      'Korunan taslak.',
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('declining image replacement preserves manual draft', (
    tester,
  ) async {
    final picker = _Picker()..result = XFile('unused-image.jpg');
    await _show(tester, picker, FakeSpeechService());
    await _create(tester, 'Korunan taslak.');
    await tester.ensureVisible(find.text('Galeriden görsel seç'));
    await tester.tap(find.text('Galeriden görsel seç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Düzenlediğin metin silinsin mi?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_field).controller!.text,
      'Korunan taslak.',
    );
  });

  testWidgets('page OCR import remains an OCR-only flow', (tester) async {
    await _show(tester, _Picker(), FakeSpeechService(), returnText: true);
    expect(find.text('Metin yaz veya yapıştır'), findsNothing);
    expect(find.text('Metni kullan'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/app.dart';
import 'package:reading_assistant/features/image_import/services/ocr_result.dart';

import 'test_doubles.dart';

const _extractLabel = 'Metni çıkar';
const _selectLabel = 'Galeriden görsel seç';
const _changeLabel = 'Görseli değiştir';
const _removeLabel = 'Görseli kaldır';
const _joinLabel = 'Satırları birleştir';
const _fieldLabel = 'Çıkarılan metin';
const _raw = 'kitap-\nlık burada\nikinci satır\r\n\r\nYeni paragraf\nson';
const _joined = 'kitaplık burada ikinci satır\n\nYeni paragraf son';

final _textField = find.widgetWithText(TextField, _fieldLabel);
final _switch = find.byType(SwitchListTile);

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(_textField).controller!.text;

bool _isOn(WidgetTester tester) => tester.widget<SwitchListTile>(_switch).value;

Future<void> _start(WidgetTester tester, {String raw = _raw}) async {
  await tester.pumpWidget(
    ReadingAssistantApp(
      pickerService: FakeImagePickerService(
        onPick: () async => XFile('/tmp/a.jpg'),
      ),
      textRecognitionService: FakeTextRecognitionService((_) async => raw),
      previewImageBuilder: (file) => ControlledImageProvider(),
    ),
  );
  await tester.pump();
  await tester.tap(find.text(_selectLabel));
  await tester.pump();
}

Future<void> _extract(WidgetTester tester) async {
  await tester.ensureVisible(find.text(_extractLabel));
  await tester.tap(find.text(_extractLabel));
  await tester.pump();
  await tester.pump();
}

Future<void> _toggle(WidgetTester tester) async {
  await tester.ensureVisible(_switch);
  await tester.tap(find.text(_joinLabel));
  await tester.pump();
}

// The progress indicator behind the dialog never settles.
Future<void> _showDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('offers the option only after OCR, off by default', (
    tester,
  ) async {
    await _start(tester);
    expect(_switch, findsNothing);

    await _extract(tester);

    expect(_switch, findsOneWidget);
    expect(_isOn(tester), isFalse);
    expect(_fieldText(tester), _raw);
    expect(
      find.text(
        'Satırları birleştirir; paragraf ve başlık ayrımlarını tahmin eder.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('joins lines from the raw result and restores it when off', (
    tester,
  ) async {
    await _start(tester);
    await _extract(tester);

    await _toggle(tester);
    expect(_isOn(tester), isTrue);
    expect(_fieldText(tester), _joined);
    expect(find.byType(AlertDialog), findsNothing);

    await _toggle(tester);
    expect(_isOn(tester), isFalse);
    expect(_fieldText(tester), _raw);

    await _toggle(tester);
    expect(_fieldText(tester), _joined);
  });

  group('edited text', () {
    testWidgets('asks first; declining keeps the text and the option', (
      tester,
    ) async {
      await _start(tester);
      await _extract(tester);
      await tester.enterText(_textField, 'Benim düzeltmem');
      await tester.pump();

      await tester.ensureVisible(_switch);
      await tester.tap(find.text(_joinLabel));
      await _showDialog(tester);
      expect(find.text('Düzenlediğin metin silinsin mi?'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await _showDialog(tester);

      expect(_fieldText(tester), 'Benim düzeltmem');
      expect(_isOn(tester), isFalse);
    });

    testWidgets('confirming rebuilds the text from the raw result', (
      tester,
    ) async {
      await _start(tester);
      await _extract(tester);
      await tester.enterText(_textField, 'Benim düzeltmem');
      await tester.pump();

      await tester.ensureVisible(_switch);
      await tester.tap(find.text(_joinLabel));
      await _showDialog(tester);
      await tester.tap(find.text('Metni sil ve uygula'));
      await _showDialog(tester);

      expect(_fieldText(tester), _joined);
      expect(_isOn(tester), isTrue);
    });

    testWidgets('editing after joining is detected and protected', (
      tester,
    ) async {
      await _start(tester);
      await _extract(tester);
      await _toggle(tester);
      await tester.enterText(_textField, '$_joined düzeltme');
      await tester.pump();

      // Switching back asks, because the joined text was edited.
      await tester.tap(find.text(_joinLabel));
      await _showDialog(tester);
      expect(find.text('Düzenlediğin metin silinsin mi?'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await _showDialog(tester);
      expect(_fieldText(tester), '$_joined düzeltme');
      expect(_isOn(tester), isTrue);

      // Removing the image asks too.
      await tester.tap(find.text(_removeLabel));
      await _showDialog(tester);
      expect(find.text('Düzenlediğin metin silinsin mi?'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await _showDialog(tester);
      expect(_fieldText(tester), '$_joined düzeltme');
    });
  });

  testWidgets('joined but unedited text is not treated as edited', (
    tester,
  ) async {
    await _start(tester);
    await _extract(tester);
    await _toggle(tester);

    await tester.tap(find.text(_removeLabel));
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(_textField, findsNothing);
    expect(_switch, findsNothing);
  });

  testWidgets('a new image or a new OCR result resets the option', (
    tester,
  ) async {
    await _start(tester);
    await _extract(tester);
    await _toggle(tester);

    // Re-running OCR on unedited text needs no confirmation.
    await _extract(tester);
    expect(_isOn(tester), isFalse);
    expect(_fieldText(tester), _raw);

    await _toggle(tester);
    await tester.ensureVisible(find.text(_changeLabel));
    await tester.tap(find.text(_changeLabel));
    await tester.pump();
    await tester.pump();
    expect(_switch, findsNothing);

    await _extract(tester);
    expect(_isOn(tester), isFalse);
    expect(_fieldText(tester), _raw);
  });

  testWidgets('no option when OCR finds only whitespace', (tester) async {
    await _start(tester, raw: '  \n ');
    await _extract(tester);
    expect(_switch, findsNothing);
  });

  group('with line layout', () {
    // Synthetic text; coordinates describe a 40..860 px column.
    OcrLine line(String text, {int block = 0, double left = 40}) => OcrLine(
      text: text,
      blockIndex: block,
      left: left,
      top: 0,
      right: 860,
      bottom: 40,
    );

    late OcrResult layout;
    late String laidOutRaw;

    setUp(() {
      layout = OcrResult(
        'birinci paragraf sürer ve biter.\nikinci satır sürer.\n'
        'ikinci paragraf girintili başlar\nüçüncü satır sürer\n'
        'dördüncü satır sürer\nbeşinci satır sürer',
        lines: [
          line('birinci paragraf sürer ve biter.'),
          line('ikinci satır sürer.'),
          line('ikinci paragraf girintili başlar', left: 75),
          line('üçüncü satır sürer'),
          line('dördüncü satır sürer'),
          line('beşinci satır sürer'),
        ],
      );
      laidOutRaw = layout.text;
    });

    Future<void> startWithLayout(WidgetTester tester) async {
      await tester.pumpWidget(
        ReadingAssistantApp(
          pickerService: FakeImagePickerService(
            onPick: () async => XFile('/tmp/a.jpg'),
          ),
          textRecognitionService: FakeTextRecognitionService.withLayout(
            (_) async => layout,
          ),
          previewImageBuilder: (file) => ControlledImageProvider(),
        ),
      );
      await tester.pump();
      await tester.tap(find.text(_selectLabel));
      await tester.pump();
    }

    testWidgets('shows the raw text first; joining uses the layout and '
        'toggling back restores the raw text', (tester) async {
      await startWithLayout(tester);
      await _extract(tester);
      expect(_isOn(tester), isFalse);
      expect(_fieldText(tester), laidOutRaw);

      await _toggle(tester);
      expect(
        _fieldText(tester),
        startsWith('birinci paragraf sürer ve biter. '),
      );
      expect(_fieldText(tester), contains('\n\nikinci paragraf'));

      await _toggle(tester);
      expect(_fieldText(tester), laidOutRaw);
    });

    testWidgets('edited layout-joined text is still protected', (tester) async {
      await startWithLayout(tester);
      await _extract(tester);
      await _toggle(tester);
      expect(_fieldText(tester), isNot(laidOutRaw));

      // Only the automatic formatting does not count as an edit.
      await tester.tap(find.text(_removeLabel));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(_textField, findsNothing);
    });

    testWidgets('user edits are kept when the switch change is declined', (
      tester,
    ) async {
      await startWithLayout(tester);
      await _extract(tester);
      await _toggle(tester);
      await tester.enterText(_textField, 'Benim düzeltmem');
      await tester.pump();

      await tester.tap(find.text(_joinLabel));
      await _showDialog(tester);
      await tester.tap(find.text('Vazgeç'));
      await _showDialog(tester);
      expect(_fieldText(tester), 'Benim düzeltmem');
      expect(_isOn(tester), isTrue);

      await tester.tap(find.text(_joinLabel));
      await _showDialog(tester);
      await tester.tap(find.text('Metni sil ve uygula'));
      await _showDialog(tester);
      expect(_fieldText(tester), laidOutRaw);
      expect(_isOn(tester), isFalse);
    });

    testWidgets('a new OCR run resets the option and the layout', (
      tester,
    ) async {
      await startWithLayout(tester);
      await _extract(tester);
      await _toggle(tester);
      expect(_fieldText(tester), isNot(laidOutRaw));

      await _extract(tester);
      expect(_isOn(tester), isFalse);
      expect(_fieldText(tester), laidOutRaw);
      await _toggle(tester);
      expect(_fieldText(tester), contains('\n\nikinci paragraf'));
    });
  });
}

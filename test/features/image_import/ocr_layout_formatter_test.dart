import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/image_import/services/ocr_result.dart';
import 'package:reading_assistant/features/image_import/services/ocr_text_formatter.dart';

// All texts below are synthetic. Coordinates are either hand-made (a 820 px
// wide column, 40..860) or taken from a real device log (see the last group).
// Passing these tests says nothing about real OCR accuracy.

OcrLine _line(
  String text, {
  int block = 0,
  double left = 40,
  double right = 860,
  double top = 0,
  double scale = 1,
}) => OcrLine(
  text: text,
  blockIndex: block,
  left: left * scale,
  top: top * scale,
  right: right * scale,
  bottom: (top + 40) * scale,
);

OcrResult _result(List<OcrLine> lines, {String? text}) =>
    OcrResult(text ?? lines.map((l) => l.text).join('\n'), lines: lines);

// A page whose normal lines span 40..860; helpers add indents (left 75).
List<OcrLine> _filler(int count, {int block = 9, double scale = 1}) => [
  for (var i = 0; i < count; i++)
    _line('dolgu$i metni sürer', block: block, scale: scale),
];

void main() {
  group('joinOcrResult', () {
    test('joins lines across block boundaries inside one paragraph', () {
      final result = _result([
        _line('bir cümle başlar ve', block: 0),
        _line('sonraki blokta sürer ve', block: 1),
        _line('üçüncü blokta da sürer', block: 2),
        _line('dördüncü blokta devam eder', block: 3),
        _line('beşinci blokta devam eder', block: 4),
        _line('altıncı blokta biter.', block: 5, right: 500),
      ]);
      expect(
        joinOcrResult(result),
        'bir cümle başlar ve sonraki blokta sürer ve üçüncü blokta da sürer '
        'dördüncü blokta devam eder beşinci blokta devam eder '
        'altıncı blokta biter.',
      );
    });

    test('splits two paragraphs inside one block on indent after a '
        'sentence end', () {
      final result = _result([
        _line('birinci paragraf tam satır sürer'),
        _line('ve cümleyi burada bitirir.'),
        _line('ikinci paragraf girintiyle başlar', left: 75),
        _line('ve aynı sütunda sürer'),
        _line('üçüncü satır da sürer'),
        _line('dördüncü satır da sürer'),
        _line('son satır biter.', right: 500),
      ]);
      expect(
        joinOcrResult(result),
        'birinci paragraf tam satır sürer ve cümleyi burada bitirir.\n\n'
        'ikinci paragraf girintiyle başlar ve aynı sütunda sürer üçüncü '
        'satır da sürer dördüncü satır da sürer son satır biter.',
      );
    });

    test('a clearly short previous line supports an indent without a '
        'period', () {
      final result = _result([
        _line('birinci paragraf tam satır sürer'),
        _line('kısa son satır', right: 400),
        _line('ikinci paragraf girintiyle başlar', left: 75),
        ..._filler(4),
      ]);
      expect(joinOcrResult(result), contains('kısa son satır\n\nikinci'));
    });

    test('an indent alone does not split (full-width previous line, no '
        'sentence end)', () {
      final result = _result([
        _line('birinci satır tam genişlikte ve'),
        _line('ikinci satır da tam genişlikte ve'),
        _line('girintili satır sahte olabilir', left: 75),
        ..._filler(4),
      ]);
      expect(joinOcrResult(result), isNot(contains('\n\n')));
    });

    test('a hyphenated continuation line is not split by a false indent', () {
      final result = _result([
        _line('birinci paragraf tam satır ve söz-'),
        _line('cük girintili görünür ve sürer.', left: 75),
        ..._filler(5),
      ]);
      final output = joinOcrResult(result);
      expect(output, startsWith('birinci paragraf tam satır ve sözcük '));
      expect(output, isNot(contains('\n\n')));
    });

    test('sentence end plus capital letter alone does not split', () {
      final result = _result([
        _line('Birinci cümle burada biter. Sonra'),
        _line('Başka bir cümle başlar. Üçüncü'),
        _line('Cümle de sürer. Dördüncü cümle'),
        _line('Burada devam eder. Beşinci'),
        _line('Cümle de böyle. Altıncı cümle'),
        _line('Son satır. Bitti.'),
      ]);
      expect(joinOcrResult(result), isNot(contains('\n\n')));
    });

    test('a centered single-line block is a heading: split before and '
        'after', () {
      final result = _result([
        _line('birinci paragraf tam satır sürer'),
        _line('ikinci satır da sürer'),
        _line('cümleyi burada bitirir.', right: 500),
        _line('Başlık', block: 1, left: 400, right: 500),
        _line('sonraki metin tam satır sürer', block: 2),
        _line('ikinci satır da sürer', block: 2),
        _line('üçüncü satır da sürer', block: 2),
      ]);
      expect(
        joinOcrResult(result),
        'birinci paragraf tam satır sürer ikinci satır da sürer cümleyi '
        'burada bitirir.\n\nBaşlık\n\nsonraki metin tam satır sürer ikinci '
        'satır da sürer üçüncü satır da sürer',
      );
    });

    test('no hyphen joining across a heading boundary', () {
      final result = _result([
        _line('birinci paragraf tam satır ve kelime-'),
        _line('Başlık', block: 1, left: 400, right: 500),
        _line('sonraki', block: 2),
        ..._filler(4),
      ]);
      expect(joinOcrResult(result), contains('kelime-\n\nBaşlık\n\nsonraki'));
    });

    test('a short left-aligned single-line block is not a heading', () {
      final result = _result([
        _line('birinci paragraf tam satır sürer'),
        _line('ikinci satır da sürer'),
        _line('kısa son satır', block: 1, right: 300),
        _line('sonraki satır', block: 2),
        ..._filler(3),
      ]);
      expect(joinOcrResult(result), isNot(contains('\n\n')));
    });

    test('list markers still stay on their own line', () {
      final result = _result([
        _line('Liste:'),
        _line('- elma'),
        _line('- armut'),
        ..._filler(4),
      ]);
      expect(joinOcrResult(result), startsWith('Liste:\n- elma\n- armut '));
    });

    group('falls back to the text-based formatter', () {
      const raw = 'bir\nsatır\n\nyeni paragraf\nburada';

      test('without layout or with too few lines', () {
        expect(joinOcrResult(const OcrResult(raw)), joinOcrLines(raw));
        final few = _result([_line('a'), _line('b'), _line('c')]);
        expect(joinOcrResult(few), joinOcrLines(few.text));
      });

      test('when the layout does not match the text', () {
        final lines = [for (var i = 0; i < 8; i++) _line('satır$i')];
        final result = _result(lines, text: 'başka bir metin\nburada');
        expect(joinOcrResult(result), joinOcrLines(result.text));
      });

      test('when the raw text already has blank lines', () {
        final lines = [for (var i = 0; i < 8; i++) _line('satır$i')];
        final result = _result(
          lines,
          text:
              '${lines.take(4).map((l) => l.text).join('\n')}\n\n'
              '${lines.skip(4).map((l) => l.text).join('\n')}',
        );
        expect(joinOcrResult(result), joinOcrLines(result.text));
      });

      test('when a box is invalid', () {
        final lines = [
          for (var i = 0; i < 8; i++) _line('satır$i'),
          _line('bozuk', right: 10),
        ];
        final result = _result(lines);
        expect(joinOcrResult(result), joinOcrLines(result.text));
      });

      test('when lines do not form a column (no guesses)', () {
        final lines = [
          for (var i = 0; i < 8; i++)
            _line(
              'şiir satırı $i',
              left: 40 + (i % 3) * 200,
              right: 200 + (i % 3) * 200,
            ),
        ];
        final output = joinOcrResult(_result(lines));
        expect(output, isNot(contains('\n\n')));
      });

      test('empty text', () {
        expect(joinOcrResult(const OcrResult('')), '');
      });
    });

    test('keeps every character and the reading order', () {
      final result = _result([
        _line('Birinci cümle burada biter.'),
        _line('İkinci paragraf başlar ve', left: 75),
        _line('Başlık', block: 1, left: 400, right: 500),
        _line('ğüşiöç sürer ve devam eder', block: 2),
        ..._filler(4),
      ]);
      String strip(String s) => s.replaceAll(RegExp(r'\s+'), '');
      expect(strip(joinOcrResult(result)), strip(result.text));
    });

    test('does not depend on the pixel scale', () {
      List<OcrLine> build(double scale) => [
        _line('birinci paragraf tam satır sürer', scale: scale),
        _line('cümleyi burada bitirir.', scale: scale, right: 500),
        _line('ikinci paragraf girintili', scale: scale, left: 75),
        _line('Başlık', block: 1, scale: scale, left: 400, right: 500),
        _line('sonraki', block: 2, scale: scale),
        ..._filler(4, scale: scale),
      ];
      final expected = joinOcrResult(_result(build(1)));
      expect(expected, contains('\n\n'));
      for (final scale in [0.37, 2.0, 3.5]) {
        expect(joinOcrResult(_result(build(scale))), expected);
      }
    });
  });

  group('log-shaped page (real coordinates, synthetic text)', () {
    // Left/right pixels and block of the 31 lines from a real device run.
    const geometry = <(int, double, double)>[
      (0, 50, 856),
      (0, 47, 852),
      (0, 40, 859),
      (0, 42, 862),
      (0, 74, 862),
      (1, 40, 863),
      (1, 40, 866),
      (1, 42, 866),
      (1, 40, 871),
      (1, 43, 872),
      (1, 52, 662),
      (2, 77, 874),
      (2, 44, 876),
      (2, 44, 717),
      (3, 77, 880),
      (3, 44, 880),
      (3, 44, 259),
      (4, 79, 888),
      (4, 45, 891),
      (4, 46, 894),
      (4, 46, 894),
      (4, 47, 619),
      (5, 424, 510),
      (6, 84, 863),
      (6, 84, 905),
      (6, 50, 912),
      (6, 50, 915),
      (6, 51, 516),
      (7, 86, 918),
      (7, 51, 920),
      (7, 53, 923),
    ];
    const sentenceEnds = {3, 10, 13, 16, 21, 23, 27};

    test('splits at indents and the heading, not at block boundaries', () {
      final lines = [
        for (var i = 0; i < geometry.length; i++)
          OcrLine(
            text: 'satir$i${sentenceEnds.contains(i) ? '.' : ''}',
            blockIndex: geometry[i].$1,
            left: geometry[i].$2,
            top: i * 43.0,
            right: geometry[i].$3,
            bottom: i * 43.0 + 55,
          ),
      ];
      const groups = [
        [0, 1, 2, 3],
        [4, 5, 6, 7, 8, 9, 10],
        [11, 12, 13],
        [14, 15, 16],
        [17, 18, 19, 20, 21],
        [22],
        [23],
        [24, 25, 26, 27],
        [28, 29, 30],
      ];
      final expected = groups
          .map((g) => g.map((i) => lines[i].text).join(' '))
          .join('\n\n');
      expect(joinOcrResult(_result(lines)), expected);
    });
  });
}

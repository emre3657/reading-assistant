import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/image_import/services/ocr_text_formatter.dart';

void main() {
  group('joinOcrLines', () {
    test('turns single line breaks into spaces', () {
      expect(
        joinOcrLines('Bir satır\niki satır\nüç satır'),
        'Bir satır iki satır üç satır',
      );
    });

    test('keeps paragraphs separated by blank lines', () {
      expect(joinOcrLines('A\nb\n\nC\nd\n\n\n\nE'), 'A b\n\nC d\n\nE');
      expect(joinOcrLines('A\n  \t\nB'), 'A\n\nB');
    });

    test('handles CRLF, CR and LF the same way', () {
      const expected = 'A b\n\nC d';
      expect(joinOcrLines('A\r\nb\r\n\r\nC\r\nd'), expected);
      expect(joinOcrLines('A\nb\n\nC\nd'), expected);
      expect(joinOcrLines('A\rb\r\rC\rd'), expected);
      expect(joinOcrLines('A\r\nb\n\r\nC\nd'), expected);
    });

    test('joins a hyphenated split before a lowercase letter', () {
      expect(joinOcrLines('kitap-\nlık burada'), 'kitaplık burada');
      expect(joinOcrLines('çalış-\nışmak'), 'çalışışmak');
      expect(joinOcrLines('göz-\nığrı'), 'gözığrı');
      expect(joinOcrLines('okul-\nİstanbul'), 'okul- İstanbul');
      expect(joinOcrLines('ağaç-\nönce'), 'ağaçönce');
    });

    test('keeps the hyphen when the next line is not lowercase', () {
      expect(joinOcrLines('Kuzey-\nDoğu'), 'Kuzey- Doğu');
      expect(joinOcrLines('sayfa-\n12'), 'sayfa- 12');
      expect(joinOcrLines('a -\nb'), 'a - b');
    });

    test('does not split across paragraphs', () {
      expect(joinOcrLines('kitap-\n\nlık'), 'kitap-\n\nlık');
    });

    test('leaves inner hyphens, list markers and punctuation alone', () {
      expect(
        joinOcrLines('sosyo-ekonomik, "iyi" (evet)!\nsonra: 3-4 gün'),
        'sosyo-ekonomik, "iyi" (evet)! sonra: 3-4 gün',
      );
      expect(
        joinOcrLines('Liste:\n- elma\n- armut\n1. bir\n2) iki'),
        'Liste:\n- elma\n- armut\n1. bir\n2) iki',
      );
    });

    test('does not change Turkish characters', () {
      const text = 'ÇĞİÖŞÜ çğıöşü\nİŞ ığüşö';
      expect(joinOcrLines(text), 'ÇĞİÖŞÜ çğıöşü İŞ ığüşö');
    });

    test('trims lines and handles empty text', () {
      expect(joinOcrLines(''), '');
      expect(joinOcrLines('  \n\n \n'), '');
      expect(joinOcrLines('\n\n  A  \n  b  \n\n'), 'A b');
    });

    test('is applied to the raw text, not repeated over its own output', () {
      const raw = 'a\nb\n\nc-\nd';
      expect(joinOcrLines(joinOcrLines(raw)), joinOcrLines(raw));
    });
  });
}

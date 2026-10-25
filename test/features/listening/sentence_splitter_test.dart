import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/listening/services/sentence_splitter.dart';

// Heuristic rules: these cases document the intended behaviour, they do not
// prove correct sentence detection for arbitrary Turkish text.
List<String> _split(String text) => [
  for (final s in splitSentences(text)) text.substring(s.start, s.end),
];

void main() {
  test('splits on . ! ? and the ellipsis character', () {
    expect(_split('Geldim. Gördüm! Yendim? Belki… Evet.'), [
      'Geldim. ',
      'Gördüm! ',
      'Yendim? ',
      'Belki… ',
      'Evet.',
    ]);
  });

  test('ranges are consecutive and cover the text exactly', () {
    const text = '  Merhaba dünya.\n\nİkinci paragraf. "Tamam!" dedi.  \n';
    final spans = splitSentences(text);
    expect(spans.first.start, 0);
    expect(spans.last.end, text.length);
    for (var i = 1; i < spans.length; i++) {
      expect(spans[i].start, spans[i - 1].end);
    }
    expect(_split(text).join(), text);
  });

  test('closing quotes stay with their sentence', () {
    expect(_split('"Gel buraya!" Sonra gitti. «Neden?» Bilmem.'), [
      '"Gel buraya!" ',
      'Sonra gitti. ',
      '«Neden?» ',
      'Bilmem.',
    ]);
  });

  test('a lowercase continuation does not split', () {
    expect(_split('"Gel!" dedi annem. Sonra gitti.'), [
      '"Gel!" dedi annem. ',
      'Sonra gitti.',
    ]);
    expect(_split('Bekle... sonra geldi. Bitti.'), [
      'Bekle... sonra geldi. ',
      'Bitti.',
    ]);
  });

  test('keeps decimals, numbers and ordinals together', () {
    expect(_split('Fiyat 3.5 lira, oran 1,25 idi. Sonra 5. sınıfa geçti.'), [
      'Fiyat 3.5 lira, oran 1,25 idi. ',
      'Sonra 5. sınıfa geçti.',
    ]);
    expect(_split('Madde 3. Yeni kural geldi.'), [
      'Madde 3. Yeni kural geldi.',
    ]);
  });

  test('common abbreviations and initials do not split', () {
    expect(_split('Dr. Ayşe geldi. Prof. Dr. Ali de geldi.'), [
      'Dr. Ayşe geldi. ',
      'Prof. Dr. Ali de geldi.',
    ]);
    expect(_split('M. Kemal Atatürk geldi. Bitti.'), [
      'M. Kemal Atatürk geldi. ',
      'Bitti.',
    ]);
    expect(_split('Şirket a.ş. olarak kuruldu. Sonra büyüdü.'), [
      'Şirket a.ş. olarak kuruldu. ',
      'Sonra büyüdü.',
    ]);
  });

  test('sentence-final abbreviations split only before a capital letter', () {
    expect(_split('Elma, armut vb. çok sattı. Bitti.'), [
      'Elma, armut vb. çok sattı. ',
      'Bitti.',
    ]);
    expect(_split('Elma, armut vb. Sonra gitti.'), [
      'Elma, armut vb. ',
      'Sonra gitti.',
    ]);
  });

  test('a blank line ends a sentence; a single line break does not', () {
    expect(_split('Başlık\n\nBirinci satır\nikinci satır. Üçüncü.'), [
      'Başlık\n\n',
      'Birinci satır\nikinci satır. ',
      'Üçüncü.',
    ]);
    expect(_split('Satır bir\nSatır iki'), ['Satır bir\nSatır iki']);
  });

  test('text without punctuation stays one sentence', () {
    final text = 'kelime ' * 500;
    expect(_split(text), [text]);
  });

  test('empty and whitespace-only text', () {
    expect(splitSentences(''), isEmpty);
    expect(_split('  \n\n '), ['  \n\n ']);
  });

  test('Turkish capital letters count as sentence starts', () {
    expect(_split('Bitti. İstanbul güzel. Ömer geldi.'), [
      'Bitti. ',
      'İstanbul güzel. ',
      'Ömer geldi.',
    ]);
  });

  test('never loses characters, including emoji', () {
    const text = 'Güzel 😀 gün. Çok iyi!!! Evet?! Tamam… ok. \u00A0Son.';
    expect(_split(text).join(), text);
  });
}

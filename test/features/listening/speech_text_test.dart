import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/listening/services/speech_service.dart';
import 'package:reading_assistant/features/listening/services/speech_text_splitter.dart';

Map<String, String> _voice(
  String name, {
  String locale = 'tr-TR',
  String network = '0',
  String features = 'embeddedTts',
  String quality = 'normal',
}) => {
  'name': name,
  'locale': locale,
  'network_required': network,
  'features': features,
  'quality': quality,
};

void main() {
  group('splitSpeechText', () {
    test('keeps short text in one piece', () {
      expect(splitSpeechText('Kısa metin.', maxLength: 100), ['Kısa metin.']);
      expect(splitSpeechText('', maxLength: 100), isEmpty);
    });

    test('joining the pieces gives back the exact text', () {
      final text =
          'Birinci cümle. İkinci cümle!\n\nÜçüncü, dördüncü; beşinci '
          '${'x' * 300} sonuncu  cümle ?  Son.';
      for (final max in [2, 3, 10, 37, 100, 1000]) {
        final chunks = splitSpeechText(text, maxLength: max);
        expect(chunks.join(), text, reason: 'maxLength $max');
        expect(chunks.every((c) => c.isNotEmpty && c.length <= max), isTrue);
      }
    });

    test('prefers line breaks, then sentence ends, then spaces', () {
      expect(splitSpeechText('aaaa bbbb.\ncccc dddd eeee', maxLength: 14), [
        'aaaa bbbb.\n',
        'cccc dddd eeee',
      ]);
      expect(splitSpeechText('aaaa bbbb. cccc dddd eeee', maxLength: 16), [
        'aaaa bbbb.',
        ' cccc dddd eeee',
      ]);
      expect(splitSpeechText('aaaa bbbb cccc dddd', maxLength: 12), [
        'aaaa bbbb ',
        'cccc dddd',
      ]);
    });

    test('hard cut of a long word never splits a surrogate pair', () {
      final text = '😀' * 21;
      for (final max in [3, 5, 7]) {
        final chunks = splitSpeechText(text, maxLength: max);
        expect(chunks.join(), text);
        for (final chunk in chunks) {
          expect(chunk.runes.every((r) => r == 0x1F600), isTrue);
        }
      }
    });

    test('keeps Turkish letters and combining marks in the text', () {
      const text = 'ığüşöçİĞÜŞÖÇ ı̇ i̇ şehir ağaç ÖĞRETMEN ';
      final chunks = splitSpeechText(text * 20, maxLength: 17);
      expect(chunks.join(), text * 20);
    });

    test('rejects a too small limit', () {
      expect(() => splitSpeechText('abc', maxLength: 1), throwsArgumentError);
    });
  });

  group('selectOfflineTurkishVoice', () {
    test('returns null for missing or odd data', () {
      expect(selectOfflineTurkishVoice(null), isNull);
      expect(selectOfflineTurkishVoice('x'), isNull);
      expect(selectOfflineTurkishVoice(<Object>[]), isNull);
      expect(selectOfflineTurkishVoice(<Object>[1, 'a', {}]), isNull);
    });

    test('ignores other languages, network and not-installed voices', () {
      final voices = [
        _voice('en', locale: 'en-US'),
        _voice('tr-net', network: '1'),
        _voice('tr-missing', features: 'embeddedTts\tnotInstalled'),
        {'name': 'tr-unknown', 'locale': 'tr-TR'},
      ];
      expect(selectOfflineTurkishVoice(voices), isNull);
    });

    test('picks an installed offline Turkish voice', () {
      final voices = [
        _voice('en', locale: 'en-US'),
        _voice('tr-net', network: '1', quality: 'very high'),
        _voice('tr-local'),
      ];
      expect(selectOfflineTurkishVoice(voices), {
        'name': 'tr-local',
        'locale': 'tr-TR',
      });
    });

    test('prefers higher quality, then embedded voices', () {
      expect(
        selectOfflineTurkishVoice([
          _voice('normal'),
          _voice('high', quality: 'high'),
        ])!['name'],
        'high',
      );
      expect(
        selectOfflineTurkishVoice([
          _voice('plain', features: ''),
          _voice('embedded'),
        ])!['name'],
        'embedded',
      );
    });

    test('accepts the underscore locale spelling', () {
      expect(
        selectOfflineTurkishVoice([_voice('x', locale: 'tr_TR')]),
        isNotNull,
      );
    });
  });
}

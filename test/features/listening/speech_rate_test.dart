import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/listening/presentation/listening_controller.dart';
import 'package:reading_assistant/features/listening/services/speech_service.dart';

// Only the arithmetic of our own mapping is checked. How fast a real engine
// then speaks is not covered and needs listening on a device.
void main() {
  test('1× maps to the base rate that matches the old default', () {
    expect(baseSpeechRate, 0.5);
    expect(speechRateFor(1), baseSpeechRate);
  });

  test('speed choices scale the base rate, not the multiplier itself', () {
    expect(speechRateFor(0.75), closeTo(0.375, 1e-9));
    expect(speechRateFor(1.25), closeTo(0.625, 1e-9));
    expect(speechRateFor(1.5), closeTo(0.75, 1e-9));
    // Passing 1.5 straight to flutter_tts would be a different (fast) value.
    expect(speechRateFor(1.5), isNot(1.5));
  });

  test('every choice stays inside the 0..1 range and increases', () {
    final rates = [
      for (final speed in ReadingSpeed.values) speechRateFor(speed.multiplier),
    ];
    expect(rates.every((r) => r > 0 && r <= 1), isTrue);
    for (var i = 1; i < rates.length; i++) {
      expect(rates[i], greaterThan(rates[i - 1]));
    }
  });

  test('the result is clamped for out-of-range input', () {
    expect(speechRateFor(10), 1.0);
    expect(speechRateFor(-1), 0.0);
  });

  test('speed labels are the four documented choices; 1× is the default', () {
    expect(ReadingSpeed.values.map((s) => s.label), [
      '0.75×',
      '1×',
      '1.25×',
      '1.5×',
    ]);
    expect(
      ListeningController(speechService: _Unused()).speed,
      ReadingSpeed.normal,
    );
  });
}

class _Unused implements SpeechService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

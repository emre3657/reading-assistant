import 'dart:async';

import 'package:reading_assistant/features/listening/services/speech_service.dart';

/// Fake speech engine. Every [speak] stays pending until the test calls
/// [finishCurrent] / [failCurrent], or [stop] is called. This checks our own
/// sequencing only, not the behaviour of a real engine.
class FakeSpeechService implements SpeechService {
  FakeSpeechService({
    this.setup = const SpeechSetup(SpeechAvailability.ready),
    this.prepareError,
    this.stopError,
  });

  SpeechSetup setup;
  Object? prepareError;
  Object? stopError;
  Completer<void>? prepareGate;

  final List<String> spoken = [];
  int prepareCalls = 0;
  int stopCalls = 0;
  bool disposed = false;
  Completer<SpeechOutcome>? _current;

  bool get isSpeaking => _current != null;

  @override
  Future<SpeechSetup> prepare() async {
    prepareCalls++;
    await prepareGate?.future;
    if (prepareError != null) throw prepareError!;
    return setup;
  }

  /// Every multiplier passed to [setSpeechRate], in order.
  final List<double> rates = [];

  /// The multiplier in effect when each text of [spoken] was spoken.
  final List<double?> spokenRates = [];
  Object? rateError;
  double? _rate;

  @override
  Future<void> setSpeechRate(double multiplier) async {
    if (rateError != null) throw rateError!;
    rates.add(multiplier);
    _rate = multiplier;
  }

  @override
  Future<SpeechOutcome> speak(String text) {
    spoken.add(text);
    spokenRates.add(_rate);
    final completer = Completer<SpeechOutcome>();
    _current = completer;
    return completer.future;
  }

  void finishCurrent() => _complete(SpeechOutcome.completed);

  void failCurrent() => _complete(SpeechOutcome.failed);

  /// Simulates the platform ending the utterance on its own, as stopped.
  void interruptCurrent() => _complete(SpeechOutcome.stopped);

  void _complete(SpeechOutcome outcome) {
    final current = _current;
    _current = null;
    current?.complete(outcome);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _complete(SpeechOutcome.stopped);
    if (stopError != null) throw stopError!;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

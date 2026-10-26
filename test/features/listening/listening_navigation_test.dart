import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/listening/presentation/listening_controller.dart';
import 'package:reading_assistant/features/listening/services/speech_service.dart';

import 'fake_speech_service.dart';

// A fake engine: these tests check our sequencing and position handling, not
// how a real device engine behaves.
const _text = 'Bir. İki. Üç. Dört.';
const _s = ['Bir. ', 'İki. ', 'Üç. ', 'Dört.'];

void main() {
  late FakeSpeechService speech;
  late ListeningController controller;

  setUp(() {
    speech = FakeSpeechService();
    controller = ListeningController(speechService: speech);
  });

  tearDown(() => controller.dispose());

  late Future<void> lastRun;

  /// Starts reading and returns once the first speak is pending; the reading
  /// itself is available as [lastRun].
  Future<void> startReading([String text = _text]) async {
    lastRun = controller.start(text);
    await pumpEventQueue();
  }

  test('reads sentence by sentence and shows the position', () async {
    await startReading();
    final run = lastRun;
    expect(speech.spoken, [_s[0]]);
    expect(controller.currentSentence, 1);
    expect(controller.sentenceCount, 4);

    speech.finishCurrent();
    await pumpEventQueue();
    expect(speech.spoken, [_s[0], _s[1]]);
    expect(controller.currentSentence, 2);

    for (var i = 0; i < 3; i++) {
      speech.finishCurrent();
      await pumpEventQueue();
    }
    await run;
    expect(speech.spoken, _s);
    expect(controller.status, ListeningStatus.completed);
    expect(controller.isActive, isFalse);
    expect(controller.sentenceCount, 0);
  });

  test('pause stops the engine and keeps the sentence', () async {
    await startReading();
    final run = lastRun;
    speech.finishCurrent();
    await pumpEventQueue();

    await controller.pause();
    await run;
    expect(controller.status, ListeningStatus.paused);
    expect(controller.isActive, isTrue);
    expect(controller.currentSentence, 2);
    expect(speech.stopCalls, 1);
    expect(speech.spoken, [_s[0], _s[1]], reason: 'no new piece after pause');
  });

  test('resume reads the paused sentence again from its beginning', () async {
    await startReading();
    speech.finishCurrent();
    await pumpEventQueue();
    await controller.pause();

    await controller.resume();
    await pumpEventQueue();
    expect(controller.status, ListeningStatus.speaking);
    expect(speech.spoken, [_s[0], _s[1], _s[1]]);
    expect(controller.currentSentence, 2);
  });

  test('resume after the last sentence completes', () async {
    await startReading('Bir. İki.');
    speech.finishCurrent();
    await pumpEventQueue();
    await controller.pause();
    await controller.resume();
    await pumpEventQueue();
    speech.finishCurrent();
    await pumpEventQueue();
    expect(controller.status, ListeningStatus.completed);
  });

  test('next while reading cuts speech and reads the target', () async {
    await startReading();
    await controller.nextSentence();
    await pumpEventQueue();
    expect(speech.stopCalls, 1);
    expect(speech.spoken, [_s[0], _s[1]]);
    expect(controller.currentSentence, 2);
    expect(controller.status, ListeningStatus.speaking);
  });

  test('previous while reading reads the earlier sentence', () async {
    await startReading();
    speech.finishCurrent();
    await pumpEventQueue();
    speech.finishCurrent();
    await pumpEventQueue();
    expect(controller.currentSentence, 3);

    await controller.previousSentence();
    await pumpEventQueue();
    expect(speech.spoken.last, _s[1]);
    expect(controller.currentSentence, 2);
  });

  test('navigation while paused only moves the position', () async {
    await startReading();
    await controller.pause();
    final spokenBefore = speech.spoken.length;
    final stopsBefore = speech.stopCalls;

    await controller.nextSentence();
    await controller.nextSentence();
    expect(controller.currentSentence, 3);
    await controller.previousSentence();
    expect(controller.currentSentence, 2);
    expect(controller.status, ListeningStatus.paused);
    expect(speech.spoken.length, spokenBefore);
    expect(speech.stopCalls, stopsBefore);

    await controller.resume();
    await pumpEventQueue();
    expect(speech.spoken.last, _s[1]);
  });

  test('first and last sentence disable the matching navigation', () async {
    await startReading('Bir. İki.');
    expect(controller.canGoPrevious, isFalse);
    expect(controller.canRestart, isTrue);
    expect(controller.canGoNext, isTrue);

    await controller.nextSentence();
    await pumpEventQueue();
    expect(controller.canGoNext, isFalse);
    expect(controller.canGoPrevious, isTrue);
    expect(controller.canRestart, isTrue);

    final spoken = speech.spoken.length;
    await controller.nextSentence();
    expect(controller.currentSentence, 2);
    expect(speech.spoken.length, spoken);
  });

  test('restart moves to the first sentence and keeps playing', () async {
    await startReading();
    speech.finishCurrent();
    await pumpEventQueue();
    speech.finishCurrent();
    await pumpEventQueue();

    await controller.restartFromBeginning();
    await pumpEventQueue();
    expect(controller.currentSentence, 1);
    expect(controller.status, ListeningStatus.speaking);
    expect(speech.spoken.last, _s[0]);
  });

  test('restart on the first sentence while reading restarts it', () async {
    await startReading();
    expect(controller.canRestart, isTrue);
    await controller.restartFromBeginning();
    await pumpEventQueue();
    expect(speech.stopCalls, 1);
    expect(speech.spoken, [_s[0], _s[0]]);
    expect(controller.currentSentence, 1);
    expect(controller.status, ListeningStatus.speaking);
  });

  test('restart on the first sentence while paused stays silent', () async {
    await startReading();
    await controller.pause();
    final spoken = speech.spoken.length;
    final stops = speech.stopCalls;

    expect(controller.canRestart, isTrue);
    await controller.restartFromBeginning();
    expect(controller.currentSentence, 1);
    expect(controller.status, ListeningStatus.paused);
    expect(speech.spoken.length, spoken);
    expect(speech.stopCalls, stops);
  });

  test(
    'restart is unavailable outside a session and during a switch',
    () async {
      expect(controller.canRestart, isFalse);

      final slow = _SlowStopSpeech();
      final slowController = ListeningController(speechService: slow);
      addTearDown(slowController.dispose);
      unawaited(slowController.start(_text));
      await pumpEventQueue();
      expect(slowController.canRestart, isTrue);

      final jump = slowController.restartFromBeginning();
      expect(slowController.canRestart, isFalse);
      slow.stopGate.complete();
      await jump;
      await pumpEventQueue();
      expect(slowController.canRestart, isTrue);
    },
  );

  test('restart while paused stays paused', () async {
    await startReading();
    speech.finishCurrent();
    await pumpEventQueue();
    await controller.pause();
    final spoken = speech.spoken.length;

    await controller.restartFromBeginning();
    expect(controller.currentSentence, 1);
    expect(controller.status, ListeningStatus.paused);
    expect(speech.spoken.length, spoken);
  });

  test('stop while paused resets the position and unlocks', () async {
    await startReading();
    speech.finishCurrent();
    await pumpEventQueue();
    await controller.pause();

    await controller.stop();
    expect(controller.status, ListeningStatus.idle);
    expect(controller.isActive, isFalse);
    expect(controller.sentenceCount, 0);

    final run = controller.start(_text);
    await pumpEventQueue();
    expect(speech.spoken.last, _s[0]);
    await controller.stop();
    await run;
  });

  test('controls are ignored in the wrong state', () async {
    await controller.pause();
    await controller.resume();
    await controller.nextSentence();
    await controller.previousSentence();
    await controller.restartFromBeginning();
    expect(controller.status, ListeningStatus.idle);
    expect(speech.stopCalls, 0);

    await startReading();
    await controller.resume();
    expect(speech.spoken, [_s[0]]);
  });

  test(
    'a long sentence is read in pieces; navigation counts sentences',
    () async {
      speech.setup = const SpeechSetup(
        SpeechAvailability.ready,
        maxInputLength: 20,
      );
      final long = 'kelime ' * 12;
      final text = '${long.trim()}. Kısa.';
      await startReading(text);
      final run = lastRun;

      var pieces = 0;
      while (controller.currentSentence == 1 && speech.isSpeaking) {
        pieces++;
        expect(controller.currentSentence, 1);
        speech.finishCurrent();
        await pumpEventQueue();
      }
      expect(pieces, greaterThan(1));
      expect(controller.currentSentence, 2);
      expect(controller.sentenceCount, 2);
      expect(speech.spoken.every((c) => c.length <= 20), isTrue);

      speech.finishCurrent();
      await run;
      expect(speech.spoken.join(), text);
    },
  );

  test('pause during a long sentence does not start its next piece', () async {
    speech.setup = const SpeechSetup(
      SpeechAvailability.ready,
      maxInputLength: 20,
    );
    await startReading('${'kelime ' * 12}bitti.');
    final run = lastRun;
    final spoken = speech.spoken.length;
    await controller.pause();
    await run;
    await pumpEventQueue();
    expect(speech.spoken.length, spoken);
    expect(controller.status, ListeningStatus.paused);
  });

  test('rapid next commands end on the last target only', () async {
    await startReading();
    final a = controller.nextSentence();
    final b = controller.nextSentence();
    final c = controller.nextSentence();
    await Future.wait([a, b, c]);
    await pumpEventQueue();

    expect(controller.currentSentence, 4);
    expect(speech.spoken.last, _s[3]);
    expect(
      speech.spoken.where((s) => s == _s[3]).length,
      1,
      reason: 'only the latest run speaks',
    );
    expect(speech.spoken, [_s[0], _s[3]]);
    expect(speech.stopCalls, 3);
  });

  test('a speak never starts before the pending stop has finished', () async {
    final slow = _SlowStopSpeech();
    final slowController = ListeningController(speechService: slow);
    addTearDown(slowController.dispose);
    unawaited(slowController.start(_text));
    await pumpEventQueue();

    final jump = slowController.nextSentence();
    await pumpEventQueue();
    expect(slow.spoken, [_s[0]], reason: 'stop is still pending');

    slow.stopGate.complete();
    await jump;
    await pumpEventQueue();
    expect(slow.spoken, [_s[0], _s[1]]);
  });

  test('stop during a pending jump wins', () async {
    final slow = _SlowStopSpeech();
    final slowController = ListeningController(speechService: slow);
    addTearDown(slowController.dispose);
    unawaited(slowController.start(_text));
    await pumpEventQueue();

    final jump = slowController.nextSentence();
    final stop = slowController.stop();
    slow.stopGate.complete();
    await Future.wait([jump, stop]);
    await pumpEventQueue();

    expect(slow.spoken, [_s[0]]);
    expect(slowController.status, ListeningStatus.idle);
  });

  test('pause then quick resume: the old stop finishes first', () async {
    final slow = _SlowStopSpeech();
    final slowController = ListeningController(speechService: slow);
    addTearDown(slowController.dispose);
    unawaited(slowController.start(_text));
    await pumpEventQueue();

    final pause = slowController.pause();
    await slowController.resume();
    await pumpEventQueue();
    expect(slow.spoken, [_s[0]], reason: 'waits for the pending stop');

    slow.stopGate.complete();
    await pause;
    await pumpEventQueue();
    expect(slow.spoken, [_s[0], _s[0]]);
    expect(slowController.status, ListeningStatus.speaking);
  });

  test('the default speed 1× is applied before the first speech', () async {
    await startReading();
    expect(speech.rates, [1.0]);
    expect(speech.spokenRates, [1.0]);
    expect(controller.speed, ReadingSpeed.normal);
  });

  test('idle: the chosen speed is used by the next reading', () async {
    await controller.setSpeed(ReadingSpeed.faster);
    expect(controller.speed, ReadingSpeed.faster);
    expect(speech.rates, isEmpty, reason: 'nothing to apply while idle');
    expect(speech.stopCalls, 0);

    await startReading();
    expect(speech.spokenRates, [1.5]);
  });

  test(
    'speaking: a new speed cuts the speech and rereads the sentence',
    () async {
      await startReading();
      speech.finishCurrent();
      await pumpEventQueue();
      expect(controller.currentSentence, 2);

      await controller.setSpeed(ReadingSpeed.fast);
      await pumpEventQueue();
      expect(speech.stopCalls, 1);
      expect(speech.spoken, [_s[0], _s[1], _s[1]]);
      expect(speech.spokenRates, [1.0, 1.0, 1.25]);
      expect(controller.currentSentence, 2);
      expect(controller.status, ListeningStatus.speaking);
    },
  );

  test('paused: only the speed changes; resume uses it', () async {
    await startReading();
    await controller.pause();
    final spoken = speech.spoken.length;
    final stops = speech.stopCalls;

    await controller.setSpeed(ReadingSpeed.slow);
    expect(controller.speed, ReadingSpeed.slow);
    expect(controller.status, ListeningStatus.paused);
    expect(speech.spoken.length, spoken);
    expect(speech.stopCalls, stops);

    await controller.resume();
    await pumpEventQueue();
    expect(speech.spoken.last, _s[0]);
    expect(speech.spokenRates.last, 0.75);
  });

  test('the speed survives stop, completion and a new text', () async {
    await controller.setSpeed(ReadingSpeed.fast);
    await startReading('Bir.');
    speech.finishCurrent();
    await lastRun;
    expect(controller.status, ListeningStatus.completed);
    expect(controller.speed, ReadingSpeed.fast);

    await startReading('Yeni metin.');
    await controller.stop();
    expect(controller.speed, ReadingSpeed.fast);
    await startReading('Başka.');
    expect(speech.spokenRates.last, 1.25);
  });

  test('choosing the current speed again does nothing', () async {
    await startReading();
    await controller.setSpeed(ReadingSpeed.normal);
    expect(speech.stopCalls, 0);
    expect(speech.spoken, [_s[0]]);
  });

  test('rapid speed changes end on the last speed, read once', () async {
    await startReading();
    final a = controller.setSpeed(ReadingSpeed.slow);
    final b = controller.setSpeed(ReadingSpeed.fast);
    final c = controller.setSpeed(ReadingSpeed.faster);
    await Future.wait([a, b, c]);
    await pumpEventQueue();

    expect(controller.speed, ReadingSpeed.faster);
    expect(speech.spoken, [_s[0], _s[0]]);
    expect(speech.spokenRates, [1.0, 1.5]);
    expect(speech.stopCalls, 1, reason: 'one cut for the whole burst');
  });

  test(
    'a speed chosen while the stop is pending is used by the read',
    () async {
      final slow = _SlowStopSpeech();
      final slowController = ListeningController(speechService: slow);
      addTearDown(slowController.dispose);
      unawaited(slowController.start(_text));
      await pumpEventQueue();

      final first = slowController.setSpeed(ReadingSpeed.fast);
      await pumpEventQueue();
      expect(slowController.canRestart, isFalse, reason: 'switching');
      final second = slowController.setSpeed(ReadingSpeed.slow);
      expect(slow.spoken, [_s[0]], reason: 'stop is still pending');

      slow.stopGate.complete();
      await Future.wait([first, second]);
      await pumpEventQueue();
      expect(slow.spoken, [_s[0], _s[0]]);
      expect(slow.spokenRates, [1.0, 0.75]);
    },
  );

  test('stop right after a speed change wins', () async {
    final slow = _SlowStopSpeech();
    final slowController = ListeningController(speechService: slow);
    addTearDown(slowController.dispose);
    unawaited(slowController.start(_text));
    await pumpEventQueue();

    final change = slowController.setSpeed(ReadingSpeed.fast);
    final stop = slowController.stop();
    slow.stopGate.complete();
    await Future.wait([change, stop]);
    await pumpEventQueue();

    expect(slow.spoken, [_s[0]]);
    expect(slowController.status, ListeningStatus.idle);
    expect(slowController.speed, ReadingSpeed.fast);
  });

  test('a failing rate setting is reported in Turkish', () async {
    speech.rateError = Exception('rate');
    await startReading();
    await lastRun;
    expect(controller.status, ListeningStatus.failed);
    expect(controller.message, contains('Okuma hızı ayarlanamadı'));
    expect(speech.spoken, isEmpty);
  });

  test('dispose during a speed change touches nothing afterwards', () async {
    final slow = _SlowStopSpeech();
    final slowController = ListeningController(speechService: slow);
    unawaited(slowController.start(_text));
    await pumpEventQueue();
    var notified = 0;
    slowController.addListener(() => notified++);

    final change = slowController.setSpeed(ReadingSpeed.fast);
    final before = notified;
    slowController.dispose();
    slow.stopGate.complete();
    await change;
    await pumpEventQueue();

    expect(notified, before);
    expect(slow.spoken, [_s[0]]);
  });

  test('an engine error ends the session and clears the position', () async {
    await startReading();
    final run = lastRun;
    speech.failCurrent();
    await run;
    expect(controller.status, ListeningStatus.failed);
    expect(controller.sentenceCount, 0);
  });

  test('a failing stop during pause is reported', () async {
    await startReading();
    speech.stopError = Exception('boom');
    await controller.pause();
    expect(controller.status, ListeningStatus.failed);
    expect(controller.message, contains('durdurulamadı'));
    expect(controller.isActive, isFalse);
  });

  test('dispose while paused or jumping touches nothing afterwards', () async {
    final slow = _SlowStopSpeech();
    final slowController = ListeningController(speechService: slow);
    unawaited(slowController.start(_text));
    await pumpEventQueue();
    var notified = 0;
    slowController.addListener(() => notified++);

    final jump = slowController.nextSentence();
    final before = notified;
    slowController.dispose();
    slow.stopGate.complete();
    await jump;
    await pumpEventQueue();

    expect(notified, before);
    expect(slow.spoken, [_s[0]]);
  });
}

/// Fake whose stop completes only when the test releases [stopGate].
class _SlowStopSpeech extends FakeSpeechService {
  final Completer<void> stopGate = Completer<void>();

  @override
  Future<void> stop() async {
    await super.stop();
    await stopGate.future;
  }
}

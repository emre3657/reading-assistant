import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/listening/presentation/listening_controller.dart';
import 'package:reading_assistant/features/listening/services/speech_service.dart';

import 'fake_speech_service.dart';

// These tests use a fake engine: they check our sequencing and state
// handling, not how a real device engine behaves.
void main() {
  late FakeSpeechService speech;
  late ListeningController controller;

  setUp(() {
    speech = FakeSpeechService();
    controller = ListeningController(speechService: speech);
  });

  tearDown(() => controller.dispose());

  test('reads the given text and completes', () async {
    final run = controller.start('Merhaba dünya.');
    await pumpEventQueue();
    expect(controller.status, ListeningStatus.speaking);
    expect(speech.spoken, ['Merhaba dünya.']);

    speech.finishCurrent();
    await run;
    expect(controller.status, ListeningStatus.completed);
    expect(controller.isActive, isFalse);
    expect(controller.message, 'Okuma tamamlandı.');
  });

  test('does not read empty or whitespace-only text', () async {
    await controller.start('');
    await controller.start(' \n\t ');
    expect(speech.prepareCalls, 0);
    expect(speech.spoken, isEmpty);
    expect(controller.status, ListeningStatus.idle);
    expect(controller.message, 'Okunacak metin yok.');
  });

  test('shows how to install a voice when no offline Turkish voice', () async {
    speech.setup = const SpeechSetup(SpeechAvailability.noOfflineTurkishVoice);
    await controller.start('Merhaba');
    expect(controller.status, ListeningStatus.failed);
    expect(controller.message, contains('internet gerektirmeyen Türkçe ses'));
    expect(controller.message, contains('Türkçe sesi yükleyin'));
    expect(speech.spoken, isEmpty);
  });

  test('a failing preparation shows a Turkish error', () async {
    speech.prepareError = Exception('no engine');
    await controller.start('Merhaba');
    expect(controller.status, ListeningStatus.failed);
    expect(controller.message, contains('Sesli okuma başlatılamadı'));
  });

  test('ignores a second start while active', () async {
    final first = controller.start('Bir');
    await pumpEventQueue();
    await controller.start('İki');
    expect(speech.prepareCalls, 1);
    expect(speech.spoken, ['Bir']);

    speech.finishCurrent();
    await first;
  });

  test('starts are ignored during the starting phase too', () async {
    speech.prepareGate = Completer<void>();
    final first = controller.start('Bir');
    expect(controller.status, ListeningStatus.starting);
    await controller.start('İki');
    expect(speech.prepareCalls, 1);

    speech.prepareGate!.complete();
    await pumpEventQueue();
    speech.finishCurrent();
    await first;
    expect(speech.spoken, ['Bir']);
  });

  test('an engine error ends in failed and stops the engine', () async {
    final run = controller.start('Merhaba');
    await pumpEventQueue();
    speech.failCurrent();
    await run;
    expect(controller.status, ListeningStatus.failed);
    expect(controller.message, contains('hata oluştu'));
    expect(speech.stopCalls, 1);
  });

  test(
    'a platform interruption we did not ask for is shown as failed',
    () async {
      final run = controller.start('Merhaba');
      await pumpEventQueue();
      speech.interruptCurrent();
      await run;
      expect(controller.status, ListeningStatus.failed);
      expect(controller.message, 'Sesli okuma kesildi.');
    },
  );

  test('long text is read in order, piece by piece', () async {
    final text = List.generate(
      400,
      (i) => 'Cümle numarası $i burada.',
    ).join(' ');
    final run = controller.start(text);
    await pumpEventQueue();

    var pieces = 0;
    while (speech.isSpeaking) {
      pieces++;
      speech.finishCurrent();
      await pumpEventQueue();
    }
    await run;
    expect(pieces, greaterThan(1));
    expect(speech.spoken.join(), text);
    expect(
      speech.spoken.every(
        (c) => c.length <= ListeningController.preferredChunkLength,
      ),
      isTrue,
    );
    expect(controller.status, ListeningStatus.completed);
  });

  test('the platform input limit lowers the piece size', () async {
    speech.setup = const SpeechSetup(
      SpeechAvailability.ready,
      maxInputLength: 50,
    );
    final text = 'Kısa cümle bir. ' * 10;
    final run = controller.start(text);
    await pumpEventQueue();
    while (speech.isSpeaking) {
      speech.finishCurrent();
      await pumpEventQueue();
    }
    await run;
    expect(speech.spoken.every((c) => c.length <= 50), isTrue);
    expect(speech.spoken.join(), text);
  });

  test('stop ends the session and the next piece never starts', () async {
    final text = '${'a' * 900} ${'b' * 900}';
    final run = controller.start(text);
    await pumpEventQueue();
    expect(speech.spoken, hasLength(1));

    await controller.stop();
    await run;
    await pumpEventQueue();
    expect(speech.spoken, hasLength(1));
    expect(speech.stopCalls, 1);
    expect(controller.status, ListeningStatus.idle);
    expect(controller.isActive, isFalse);
  });

  test('stop during preparation prevents speaking', () async {
    speech.prepareGate = Completer<void>();
    final run = controller.start('Merhaba');
    expect(controller.canStop, isTrue);
    final stopping = controller.stop();
    expect(controller.status, ListeningStatus.stopping);
    speech.prepareGate!.complete();
    await stopping;
    await run;
    expect(speech.spoken, isEmpty);
    expect(controller.status, ListeningStatus.idle);
  });

  test('a second stop while stopping is ignored', () async {
    final run = controller.start('Merhaba');
    await pumpEventQueue();
    final first = controller.stop();
    await controller.stop();
    await first;
    await run;
    expect(speech.stopCalls, 1);
  });

  test('restart after stop reads from the beginning', () async {
    var run = controller.start('Birinci cümle. İkinci cümle.');
    await pumpEventQueue();
    await controller.stop();
    await run;

    run = controller.start('Birinci cümle. İkinci cümle.');
    await pumpEventQueue();
    expect(speech.spoken, [
      'Birinci cümle. İkinci cümle.',
      'Birinci cümle. İkinci cümle.',
    ]);
    speech.finishCurrent();
    await run;
  });

  test('a late result of a stopped session does not touch a new one', () async {
    final first = controller.start('Eski');
    await pumpEventQueue();
    await controller.stop();

    final second = controller.start('Yeni');
    await pumpEventQueue();
    await first;
    expect(controller.status, ListeningStatus.speaking);
    expect(speech.spoken, ['Eski', 'Yeni']);

    speech.finishCurrent();
    await second;
    expect(controller.status, ListeningStatus.completed);
  });

  test('a failing stop is reported', () async {
    speech.stopError = Exception('stop failed');
    final run = controller.start('Merhaba');
    await pumpEventQueue();
    await controller.stop();
    await run;
    expect(controller.status, ListeningStatus.failed);
    expect(controller.message, contains('durdurulamadı'));
    expect(controller.isActive, isFalse);
  });

  test('dispose stops the engine and later results change nothing', () async {
    final run = controller.start('Merhaba');
    await pumpEventQueue();
    var notified = 0;
    controller.addListener(() => notified++);

    controller.dispose();
    speech.finishCurrent();
    await run;
    await pumpEventQueue();

    expect(notified, 0);
    expect(speech.stopCalls, 1);
    expect(controller.status, ListeningStatus.speaking);
  });

  test('dispose during preparation never speaks', () async {
    speech.prepareGate = Completer<void>();
    final run = controller.start('Merhaba');
    controller.dispose();
    speech.prepareGate!.complete();
    await run;
    expect(speech.spoken, isEmpty);
  });

  test('a failing stop during dispose is swallowed', () async {
    speech.stopError = Exception('stop failed');
    final run = controller.start('Merhaba');
    await pumpEventQueue();
    controller.dispose();
    await pumpEventQueue();
    await run;
  });
}

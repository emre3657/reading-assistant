import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum SpeechAvailability {
  ready,

  /// No installed Turkish voice that works without a network connection could
  /// be confirmed.
  noOfflineTurkishVoice,
}

class SpeechSetup {
  const SpeechSetup(this.availability, {this.maxInputLength});

  final SpeechAvailability availability;

  /// Longest text the platform accepts in one call, when it reports one.
  final int? maxInputLength;
}

enum SpeechOutcome {
  completed,

  /// The platform stopped or refused the utterance.
  stopped,
  failed,
}

/// `flutter_tts` rate value that stands for the app's base speed (1×).
///
/// In `flutter_tts 4.2.5` the Dart value is not the engine value: Android
/// multiplies it by 2 (so 0.5 becomes the engine's normal rate 1.0) and iOS
/// passes it as `AVSpeechUtterance.rate`, whose default is 0.5. The app never
/// set a rate before, so 0.5 matches the previous default on both platforms.
const baseSpeechRate = 0.5;

/// Maps a speed multiplier (0.75, 1, 1.25, 1.5 …) to a `flutter_tts` rate by
/// scaling the base value, never by passing the multiplier itself.
///
/// The result is only a relative setting: engines and voices (and iOS's
/// non-linear rate scale) do not guarantee an exact duration ratio.
double speechRateFor(double multiplier) =>
    (baseSpeechRate * multiplier).clamp(0.0, 1.0);

/// Thin wrapper over `flutter_tts` (the device speech engine). Tests replace
/// it with a fake that `implements` this class.
///
/// `flutter_tts` callbacks carry no utterance id, and its `speak` future only
/// completes on success or on stop (never on engine errors). So each [speak]
/// races the awaited platform result, the error callback and [stop], and
/// ignores the start/complete/cancel callbacks. A late error callback of an
/// earlier utterance can still fail the next one; this cannot be ruled out.
class SpeechService {
  SpeechService({FlutterTts? tts}) : _tts = tts ?? FlutterTts() {
    _tts.setErrorHandler(_onError);
  }

  static const turkishLocale = 'tr-TR';

  final FlutterTts _tts;
  Completer<SpeechOutcome>? _pending;

  /// Selects a Turkish voice and checks what the platform can tell about its
  /// offline availability. Throws when the platform call itself fails.
  Future<SpeechSetup> prepare() async {
    await _tts.awaitSpeakCompletion(true);
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final voice = selectOfflineTurkishVoice(await _tts.getVoices);
        if (voice == null) {
          return const SpeechSetup(SpeechAvailability.noOfflineTurkishVoice);
        }
        final selected = await _tts.setVoice(voice);
        if (selected != 1) {
          return const SpeechSetup(SpeechAvailability.noOfflineTurkishVoice);
        }
        return SpeechSetup(
          SpeechAvailability.ready,
          maxInputLength: await _tts.getMaxSpeechInputLength,
        );
      case TargetPlatform.iOS:
        // iOS reports no per-voice network flag; only the language is checked.
        final available = await _tts.isLanguageAvailable(turkishLocale);
        if (available != true || await _tts.setLanguage(turkishLocale) != 1) {
          return const SpeechSetup(SpeechAvailability.noOfflineTurkishVoice);
        }
        return const SpeechSetup(SpeechAvailability.ready);
      default:
        return const SpeechSetup(SpeechAvailability.noOfflineTurkishVoice);
    }
  }

  /// Sets the speech rate for the following [speak] calls. [multiplier] is
  /// relative to the app's base rate (1 = base); see [speechRateFor].
  Future<void> setSpeechRate(double multiplier) async {
    await _tts.setSpeechRate(speechRateFor(multiplier));
  }

  /// Speaks one piece of text. The returned future completes when the
  /// platform reports the end, an error, or [stop] is called.
  Future<SpeechOutcome> speak(String text) {
    final signal = Completer<SpeechOutcome>();
    _pending = signal;
    _tts
        .speak(text)
        .then(
          (result) => _complete(
            signal,
            result == 1 ? SpeechOutcome.completed : SpeechOutcome.stopped,
          ),
          onError: (Object _) => _complete(signal, SpeechOutcome.failed),
        );
    return signal.future.whenComplete(() {
      if (identical(_pending, signal)) _pending = null;
    });
  }

  /// Stops speaking and completes a waiting [speak] as stopped.
  Future<void> stop() async {
    final pending = _pending;
    if (pending != null) _complete(pending, SpeechOutcome.stopped);
    await _tts.stop();
  }

  /// Releases the callbacks. Never throws; errors of the final stop are
  /// dropped because nothing is left to report them to.
  Future<void> dispose() async {
    final pending = _pending;
    if (pending != null) _complete(pending, SpeechOutcome.stopped);
    _tts.setErrorHandler((_) {});
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void _onError(dynamic message) {
    final pending = _pending;
    if (pending == null) return;
    _complete(pending, SpeechOutcome.failed);
    // Lets the platform release the pending `speak` call of the failed run.
    _tts.stop().then((_) {}, onError: (Object _) {});
  }

  void _complete(Completer<SpeechOutcome> signal, SpeechOutcome outcome) {
    if (!signal.isCompleted) signal.complete(outcome);
  }
}

/// Picks an installed Turkish voice that does not need a network connection
/// from the `getVoices` result of `flutter_tts` on Android. Returns the map
/// to pass to `setVoice`, or null when none qualifies.
///
/// A voice qualifies when its locale is Turkish, `network_required` is "0" and
/// its features do not contain `notInstalled`. These flags are what the
/// engine reports; Android gives no stronger proof that synthesis will work
/// offline. Voices with `embeddedTts` and higher quality are preferred.
Map<String, String>? selectOfflineTurkishVoice(Object? voices) {
  if (voices is! List) return null;
  Map<String, String>? best;
  var bestScore = -1;
  for (final entry in voices) {
    if (entry is! Map) continue;
    final name = entry['name']?.toString();
    final locale = entry['locale']?.toString();
    if (name == null || locale == null) continue;
    if (locale.replaceAll('_', '-').toLowerCase() !=
        SpeechService.turkishLocale.toLowerCase()) {
      continue;
    }
    if (entry['network_required']?.toString() != '0') continue;
    final features = (entry['features']?.toString() ?? '').split('\t');
    if (features.contains('notInstalled')) continue;

    final score =
        _qualityScore(entry['quality']?.toString()) * 2 +
        (features.contains('embeddedTts') ? 1 : 0);
    if (score > bestScore) {
      bestScore = score;
      best = {'name': name, 'locale': locale};
    }
  }
  return best;
}

int _qualityScore(String? quality) => switch (quality) {
  'very high' => 4,
  'high' => 3,
  'normal' => 2,
  'low' => 1,
  _ => 0,
};

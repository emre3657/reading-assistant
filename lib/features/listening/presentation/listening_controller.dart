import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/sentence_splitter.dart';
import '../services/speech_service.dart';
import '../services/speech_text_splitter.dart';

/// Reading speed choices, relative to the app's base speed (1×). The values
/// are mapped to the engine by [speechRateFor]; they are not exact duration
/// ratios.
enum ReadingSpeed {
  slow(0.75, '0.75×'),
  normal(1, '1×'),
  fast(1.25, '1.25×'),
  faster(1.5, '1.5×');

  const ReadingSpeed(this.multiplier, this.label);

  final double multiplier;
  final String label;
}

enum ListeningStatus {
  idle,
  starting,
  speaking,
  paused,
  stopping,
  completed,
  failed,
}

/// State of reading a text aloud with the device speech engine, sentence by
/// sentence.
///
/// Independent of the image import flow: the screen passes the text in.
///
/// Position: the controller tracks the current sentence itself. Pause stops
/// the engine; resume reads the paused sentence again from its beginning (no
/// word-level resume, no native pause). Previous/next/restart move the
/// position; while reading they cut the current speech and read the target.
///
/// Safety: every change of playback (start, pause, resume, jump, stop,
/// dispose) opens a new run number, so an older reading loop never starts
/// another piece or changes state. Engine stops are queued one after another
/// and a new speak waits for them. `flutter_tts` callbacks carry no utterance
/// id, so this Dart-side counter cannot prove that a late native callback
/// belongs to the old utterance; see [SpeechService].
///
/// The service is owned by whoever created it; this controller only uses it.
class ListeningController extends ChangeNotifier {
  ListeningController({required this.speechService});

  /// Largest piece handed to the engine in one call. A sentence longer than
  /// this (or the platform limit) is read in several pieces.
  static const preferredChunkLength = 1000;

  static const _stopErrorMessage =
      'Okuma durdurulamadı. Cihazın konuşma motoru yanıt vermiyor.';

  final SpeechService speechService;

  ListeningStatus _status = ListeningStatus.idle;
  String? _message;
  int _run = 0;

  // Run whose engine stop is still pending in a jump; any newer run clears it.
  int _switchingRun = -1;
  bool _disposed = false;
  Future<void> _stopTail = Future.value();

  String _text = '';
  List<SentenceSpan> _sentences = const [];
  int _chunkLength = preferredChunkLength;
  int _index = 0;

  ReadingSpeed _speed = ReadingSpeed.normal;

  ListeningStatus get status => _status;

  /// Chosen speed. It belongs to the controller, not to a session, so it
  /// survives stop, completion and new texts (not the app restart).
  ReadingSpeed get speed => _speed;

  /// Turkish message for the user: an error, a hint or a short result.
  String? get message => _message;

  /// True from the start request until the session has ended. A paused
  /// session is active, so the screen stays locked until Stop.
  bool get isActive =>
      _status == ListeningStatus.starting ||
      _status == ListeningStatus.speaking ||
      _status == ListeningStatus.paused ||
      _status == ListeningStatus.stopping;

  bool get canStop =>
      _status == ListeningStatus.starting ||
      _status == ListeningStatus.speaking ||
      _status == ListeningStatus.paused;

  bool get canPause => _status == ListeningStatus.speaking;
  bool get canResume => _status == ListeningStatus.paused;

  bool get _canNavigate =>
      _status == ListeningStatus.speaking || _status == ListeningStatus.paused;

  bool get canGoPrevious => _canNavigate && _index > 0;
  bool get canGoNext => _canNavigate && _index < _sentences.length - 1;

  /// Works on any sentence (also the first) in a live session, except while
  /// a jump is cutting the current speech.
  bool get canRestart => _canNavigate && _switchingRun != _run;

  /// 1-based number of the current sentence; 0 when there is no session.
  int get currentSentence => _canNavigate ? _index + 1 : 0;
  int get sentenceCount => _canNavigate ? _sentences.length : 0;

  void _setState(ListeningStatus status, [String? message]) {
    _status = status;
    _message = message;
    if (!_disposed) notifyListeners();
  }

  void _clearDocument() {
    _text = '';
    _sentences = const [];
    _index = 0;
  }

  /// Reads [text] from its first sentence. A copy is taken now, later changes
  /// of the source do not affect the running session. Ignored while active.
  /// Completes when this reading ends (completed, stopped, paused or failed).
  Future<void> start(String text) async {
    if (_disposed || isActive) return;
    if (text.trim().isEmpty) {
      _setState(ListeningStatus.idle, 'Okunacak metin yok.');
      return;
    }

    final run = ++_run;
    _setState(ListeningStatus.starting);

    final SpeechSetup setup;
    try {
      setup = await speechService.prepare();
    } catch (_) {
      if (run != _run) return;
      _setState(
        ListeningStatus.failed,
        'Sesli okuma başlatılamadı. Cihazın konuşma motoru kullanılamıyor '
        'olabilir.',
      );
      return;
    }
    if (run != _run) return;
    if (setup.availability != SpeechAvailability.ready) {
      _setState(
        ListeningStatus.failed,
        'Cihazda internet gerektirmeyen Türkçe ses bulunamadı. Cihazın '
        'ayarlarından Metin okuma (TTS) bölümünü açıp Türkçe sesi yükleyin.',
      );
      return;
    }

    final maxInput = setup.maxInputLength;
    _chunkLength = maxInput != null && maxInput >= 2
        ? (maxInput < preferredChunkLength ? maxInput : preferredChunkLength)
        : preferredChunkLength;
    _text = text;
    _sentences = splitSentences(text);
    _index = 0;

    _setState(ListeningStatus.speaking);
    await _play(run);
  }

  /// Pauses by stopping the engine. The position stays on the current
  /// sentence.
  Future<void> pause() async {
    if (_disposed || !canPause) return;
    final run = ++_run;
    _setState(ListeningStatus.paused);
    try {
      await _engineStop();
    } catch (_) {
      if (!_disposed && run == _run) _failAfterStopError();
    }
  }

  /// Reads the paused sentence again from its beginning.
  Future<void> resume() async {
    if (_disposed || !canResume) return;
    final run = ++_run;
    _setState(ListeningStatus.speaking);
    unawaited(_play(run));
  }

  /// Chooses the reading speed.
  /// - Speaking: cuts the speech and reads the same sentence again from its
  ///   beginning at the new speed.
  /// - Paused or idle (or starting/stopping): only remembers the speed; the
  ///   next reading or resume uses it.
  /// - While a jump is already cutting the speech: only remembers the speed,
  ///   because that jump has not applied the rate yet and will pick it up.
  Future<void> setSpeed(ReadingSpeed speed) async {
    if (_disposed || speed == _speed) return;
    _speed = speed;
    if (_status == ListeningStatus.speaking && _switchingRun != _run) {
      await _jump(_index);
      return;
    }
    notifyListeners();
  }

  Future<void> previousSentence() => _jump(_index - 1);

  Future<void> nextSentence() => _jump(_index + 1);

  Future<void> restartFromBeginning() => _jump(0);

  /// While reading: cuts the current speech and reads the target sentence.
  /// While paused: only moves the position.
  Future<void> _jump(int target) async {
    if (_disposed || !_canNavigate) return;
    if (target < 0 || target >= _sentences.length) return;
    final wasPaused = _status == ListeningStatus.paused;
    _index = target;
    if (wasPaused) {
      notifyListeners();
      return;
    }
    final run = ++_run;
    _switchingRun = run;
    notifyListeners();
    try {
      await _engineStop();
    } catch (_) {
      if (!_disposed && run == _run) _failAfterStopError();
      return;
    }
    if (_disposed || run != _run) return;
    _switchingRun = -1;
    notifyListeners();
    unawaited(_play(run));
  }

  /// Stops reading and ends the session. The position is reset, so reading
  /// again starts from the beginning. The state returns to idle when the
  /// engine has been told to stop.
  Future<void> stop() async {
    if (_disposed || !canStop) return;
    final run = ++_run;
    _setState(ListeningStatus.stopping);
    String? error;
    try {
      await _engineStop();
    } catch (_) {
      error = _stopErrorMessage;
    }
    if (_disposed || run != _run) return;
    _clearDocument();
    _setState(
      error == null ? ListeningStatus.idle : ListeningStatus.failed,
      error,
    );
  }

  void _failAfterStopError() {
    _clearDocument();
    _setState(ListeningStatus.failed, _stopErrorMessage);
  }

  /// Engine stops run one after another; a failure goes to the caller only.
  Future<void> _engineStop() {
    final next = _stopTail.then((_) => speechService.stop());
    _stopTail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _play(int run) async {
    // A speak never starts while an earlier stop is still running.
    await _stopTail;
    if (_disposed || run != _run) return;
    // The speed is read here, after the stop, so a speed chosen while a jump
    // was waiting for its stop is used. Every speed change opens a new run,
    // so the rate stays the same for the whole run.
    try {
      await speechService.setSpeechRate(_speed.multiplier);
    } catch (_) {
      if (_disposed || run != _run) return;
      _clearDocument();
      _setState(
        ListeningStatus.failed,
        'Okuma hızı ayarlanamadı. Tekrar deneyebilirsin.',
      );
      return;
    }
    while (!_disposed && run == _run && _index < _sentences.length) {
      final span = _sentences[_index];
      final sentence = _text.substring(span.start, span.end);
      for (final chunk in splitSpeechText(sentence, maxLength: _chunkLength)) {
        if (chunk.trim().isEmpty) continue;
        // Checked right before each piece, so a stop, pause or jump never
        // lets the next piece of the old run begin.
        if (_disposed || run != _run) return;
        var outcome = SpeechOutcome.failed;
        try {
          outcome = await speechService.speak(chunk);
        } catch (_) {
          outcome = SpeechOutcome.failed;
        }
        if (_disposed || run != _run) return;
        if (outcome == SpeechOutcome.failed) {
          // Clean up the engine first, so that a quick restart is not cut off
          // by this late stop.
          await _stopQuietly();
          if (_disposed || run != _run) return;
          _clearDocument();
          _setState(
            ListeningStatus.failed,
            'Sesli okuma sırasında bir hata oluştu. Tekrar deneyebilirsin.',
          );
          return;
        }
        if (outcome == SpeechOutcome.stopped) {
          // Not requested by us (a stop, pause or jump opens a new run).
          _clearDocument();
          _setState(ListeningStatus.failed, 'Sesli okuma kesildi.');
          return;
        }
      }
      if (_index >= _sentences.length - 1) break;
      _index++;
      notifyListeners();
    }
    if (_disposed || run != _run) return;
    _clearDocument();
    _setState(ListeningStatus.completed, 'Okuma tamamlandı.');
  }

  Future<void> _stopQuietly() async {
    try {
      await _engineStop();
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_disposed) return;
    final wasActive = isActive;
    _disposed = true;
    _run++;
    if (wasActive) unawaited(_stopQuietly());
    super.dispose();
  }
}

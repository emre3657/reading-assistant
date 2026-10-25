import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/speech_service.dart';
import '../services/speech_text_splitter.dart';

enum ListeningStatus { idle, starting, speaking, stopping, completed, failed }

/// State of reading a text aloud with the device speech engine.
///
/// Independent of the image import flow: the screen passes the text in. Each
/// [start] opens a session; [stop] and [dispose] close it at once, so results
/// of an older session (a late chunk result, a late stop) never change the
/// state of a newer one or touch the controller after dispose.
///
/// The service is owned by whoever created it; this controller only uses it.
class ListeningController extends ChangeNotifier {
  ListeningController({required this.speechService});

  /// Largest piece handed to the engine in one call. Smaller than the Android
  /// limit so that a stop takes effect between pieces without a long wait.
  static const preferredChunkLength = 1000;

  final SpeechService speechService;

  ListeningStatus _status = ListeningStatus.idle;
  String? _message;
  int _session = 0;
  bool _disposed = false;

  ListeningStatus get status => _status;

  /// Turkish message for the user: an error, a hint or a short result.
  String? get message => _message;

  /// True from the start request until the stop has finished.
  bool get isActive =>
      _status == ListeningStatus.starting ||
      _status == ListeningStatus.speaking ||
      _status == ListeningStatus.stopping;

  bool get canStop =>
      _status == ListeningStatus.starting ||
      _status == ListeningStatus.speaking;

  void _setState(ListeningStatus status, [String? message]) {
    _status = status;
    _message = message;
    if (!_disposed) notifyListeners();
  }

  /// Reads [text] from its beginning. A copy is taken now, later changes of
  /// the source do not affect the running session. Ignored while active.
  Future<void> start(String text) async {
    if (_disposed || isActive) return;
    final snapshot = text;
    if (snapshot.trim().isEmpty) {
      _setState(ListeningStatus.idle, 'Okunacak metin yok.');
      return;
    }

    final session = ++_session;
    _setState(ListeningStatus.starting);

    final SpeechSetup setup;
    try {
      setup = await speechService.prepare();
    } catch (_) {
      if (session != _session) return;
      _setState(
        ListeningStatus.failed,
        'Sesli okuma başlatılamadı. Cihazın konuşma motoru kullanılamıyor '
        'olabilir.',
      );
      return;
    }
    if (session != _session) return;
    if (setup.availability != SpeechAvailability.ready) {
      _setState(
        ListeningStatus.failed,
        'Cihazda internet gerektirmeyen Türkçe ses bulunamadı. Cihazın '
        'ayarlarından Metin okuma (TTS) bölümünü açıp Türkçe sesi yükleyin.',
      );
      return;
    }

    final maxInput = setup.maxInputLength;
    final chunkLength = maxInput != null && maxInput >= 2
        ? (maxInput < preferredChunkLength ? maxInput : preferredChunkLength)
        : preferredChunkLength;
    final chunks = splitSpeechText(snapshot, maxLength: chunkLength);

    _setState(ListeningStatus.speaking);
    for (final chunk in chunks) {
      if (chunk.trim().isEmpty) continue;
      // The session is checked right before each piece, so a stop never
      // lets the next piece begin.
      if (session != _session) return;
      var outcome = SpeechOutcome.failed;
      try {
        outcome = await speechService.speak(chunk);
      } catch (_) {
        outcome = SpeechOutcome.failed;
      }
      if (session != _session) return;
      if (outcome == SpeechOutcome.failed) {
        // Clean up the engine first, so that a quick restart is not cut off by
        // this late stop.
        await _stopQuietly();
        if (session != _session) return;
        _setState(
          ListeningStatus.failed,
          'Sesli okuma sırasında bir hata oluştu. Tekrar deneyebilirsin.',
        );
        return;
      }
      if (outcome == SpeechOutcome.stopped) {
        // Not requested by us (a stop would have ended the session).
        _setState(ListeningStatus.failed, 'Sesli okuma kesildi.');
        return;
      }
    }
    _setState(ListeningStatus.completed, 'Okuma tamamlandı.');
  }

  /// Stops reading. The session ends immediately; the state returns to idle
  /// when the engine has been told to stop.
  Future<void> stop() async {
    if (_disposed || !canStop) return;
    final session = ++_session;
    _setState(ListeningStatus.stopping);
    String? error;
    try {
      await speechService.stop();
    } catch (_) {
      error = 'Okuma durdurulamadı. Cihazın konuşma motoru yanıt vermiyor.';
    }
    if (_disposed || session != _session) return;
    _setState(
      error == null ? ListeningStatus.idle : ListeningStatus.failed,
      error,
    );
  }

  Future<void> _stopQuietly() async {
    try {
      await speechService.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_disposed) return;
    final wasActive = isActive;
    _disposed = true;
    _session++;
    if (wasActive) unawaited(_stopQuietly());
    super.dispose();
  }
}

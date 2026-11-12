import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/data/document_store.dart';
import 'listening_controller.dart';

enum ReadingTextSize {
  normal('Normal', 1),
  large('Büyük', 1.25),
  extraLarge('Çok büyük', 1.5);

  const ReadingTextSize(this.label, this.multiplier);
  final String label;
  final double multiplier;
}

enum ReadingTextAlignment {
  start('Sola', TextAlign.start),
  center('Ortaya', TextAlign.center),
  right('Sağa', TextAlign.right),
  justify('İki yana', TextAlign.justify);

  const ReadingTextAlignment(this.label, this.textAlign);
  final String label;
  final TextAlign textAlign;
}

TextStyle? readingInputTextStyle(BuildContext context, ReadingTextSize size) {
  if (size == ReadingTextSize.normal) return null;
  final theme = Theme.of(context);
  final defaultStyle = theme.useMaterial3
      ? theme.textTheme.bodyLarge
      : theme.textTheme.titleMedium;
  return TextStyle(fontSize: (defaultStyle?.fontSize ?? 16) * size.multiplier);
}

class ReadingPreferences extends ChangeNotifier {
  ReadingPreferences({DocumentStore? store})
    : _store = store ?? DocumentStore.instance;

  static final instance = ReadingPreferences();
  final DocumentStore _store;
  Future<void>? _loading;
  Future<void> _writeTail = Future.value();
  bool _ready = false;
  ReadingSpeed _speed = ReadingSpeed.normal;
  bool _autoNextPage = false;
  bool _followSentence = false;
  ReadingTextSize _textSize = ReadingTextSize.normal;
  ReadingTextAlignment _textAlignment = ReadingTextAlignment.start;
  bool _saveFailureReported = false;
  int _errorRevision = 0;
  int _claimedErrorRevision = 0;
  String? _errorMessage;

  bool get ready => _ready;
  ReadingSpeed get speed => _speed;
  bool get autoNextPage => _autoNextPage;
  bool get followSentence => _followSentence;
  ReadingTextSize get textSize => _textSize;
  ReadingTextAlignment get textAlignment => _textAlignment;
  Future<void> get pendingWrites => _writeTail;
  int get errorRevision => _errorRevision;
  String? get errorMessage => _errorMessage;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final row = await _store.loadReadingPreferences();
      final savedSpeed = row?['speed'];
      _speed =
          ReadingSpeed.values
              .where((speed) => speed.name == savedSpeed)
              .firstOrNull ??
          ReadingSpeed.normal;
      _autoNextPage = row?['auto_next_page'] == 1;
      _followSentence = row?['follow_sentence'] == 1;
      _textSize =
          ReadingTextSize.values
              .where((size) => size.name == row?['text_size'])
              .firstOrNull ??
          ReadingTextSize.normal;
      _textAlignment =
          ReadingTextAlignment.values
              .where((alignment) => alignment.name == row?['text_alignment'])
              .firstOrNull ??
          ReadingTextAlignment.start;
    } catch (_) {
      _errorMessage =
          'Okuma tercihleri yüklenemedi. Varsayılanlar kullanılıyor.';
      _errorRevision++;
    } finally {
      _ready = true;
      notifyListeners();
    }
  }

  void setSpeed(ReadingSpeed speed) {
    if (!_ready || _speed == speed) return;
    _speed = speed;
    notifyListeners();
    _save();
  }

  void setAutoNextPage(bool value) {
    if (!_ready || _autoNextPage == value) return;
    _autoNextPage = value;
    notifyListeners();
    _save();
  }

  void setFollowSentence(bool value) {
    if (!_ready || _followSentence == value) return;
    _followSentence = value;
    notifyListeners();
    _save();
  }

  void setTextSize(ReadingTextSize value) {
    if (!_ready || _textSize == value) return;
    _textSize = value;
    notifyListeners();
    _save();
  }

  void setTextAlignment(ReadingTextAlignment value) {
    if (!_ready || _textAlignment == value) return;
    _textAlignment = value;
    notifyListeners();
    _save();
  }

  void _save() {
    final speed = _speed.name;
    final auto = _autoNextPage;
    final follow = _followSentence;
    final textSize = _textSize.name;
    final textAlignment = _textAlignment.name;
    _writeTail = _writeTail.then((_) async {
      try {
        await _store.saveReadingPreferences(
          speed: speed,
          autoNextPage: auto,
          followSentence: follow,
          textSize: textSize,
          textAlignment: textAlignment,
        );
        _saveFailureReported = false;
      } catch (_) {
        if (!_saveFailureReported) {
          _saveFailureReported = true;
          _errorMessage = 'Okuma tercihleri kalıcı kaydedilemedi.';
          _errorRevision++;
          notifyListeners();
        }
      }
    });
  }

  bool claimError(int revision) {
    if (revision <= _claimedErrorRevision) return false;
    _claimedErrorRevision = revision;
    return true;
  }
}

class ReadingPreferencesScope extends InheritedWidget {
  const ReadingPreferencesScope({
    super.key,
    required this.preferences,
    required super.child,
  });

  final ReadingPreferences preferences;

  static ReadingPreferences of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ReadingPreferencesScope>()
          ?.preferences ??
      ReadingPreferences.instance;

  @override
  bool updateShouldNotify(ReadingPreferencesScope oldWidget) =>
      preferences != oldWidget.preferences;
}

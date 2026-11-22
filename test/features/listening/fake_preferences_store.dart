import 'dart:async';

import 'package:reading_assistant/features/library/data/document_store.dart';

class FakePreferencesStore extends DocumentStore {
  bool introCompleted = true;
  Object? introReadError;
  Object? introWriteError;
  Completer<void>? introReadGate;
  Completer<void>? introWriteGate;
  int introWriteCalls = 0;
  Map<String, Object?>? values;
  Object? loadError;
  Object? saveError;
  Completer<void>? loadGate;
  Completer<void>? saveGate;
  int saveCalls = 0;

  @override
  Future<bool> hasCompletedIntro() async {
    await introReadGate?.future;
    if (introReadError != null) throw introReadError!;
    return introCompleted;
  }

  @override
  Future<void> completeIntro() async {
    introWriteCalls++;
    await introWriteGate?.future;
    if (introWriteError != null) throw introWriteError!;
    introCompleted = true;
  }

  @override
  Future<Map<String, Object?>?> loadReadingPreferences() async {
    await loadGate?.future;
    if (loadError != null) throw loadError!;
    return values == null ? null : Map.of(values!);
  }

  @override
  Future<void> saveReadingPreferences({
    required String speed,
    required bool autoNextPage,
    required bool followSentence,
    required String textSize,
    required String textAlignment,
    required String lineSpacing,
    String pageView = 'plain',
    bool pageAnimationEnabled = false,
    String pageAnimationEffect = 'fade',
    String bookmarkShape = 'ribbon',
    String bookmarkColor = 'red',
    String themeMode = 'system',
    String themePalette = 'turquoise',
  }) async {
    saveCalls++;
    await saveGate?.future;
    if (saveError != null) throw saveError!;
    values = {
      'speed': speed,
      'auto_next_page': autoNextPage ? 1 : 0,
      'follow_sentence': followSentence ? 1 : 0,
      'text_size': textSize,
      'text_alignment': textAlignment,
      'line_spacing': lineSpacing,
      'page_view': pageView,
      'page_animation_enabled': pageAnimationEnabled ? 1 : 0,
      'page_animation_effect': pageAnimationEffect,
      'bookmark_shape': bookmarkShape,
      'bookmark_color': bookmarkColor,
      'theme_mode': themeMode,
      'theme_palette': themePalette,
    };
  }
}

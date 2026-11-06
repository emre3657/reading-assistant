import 'dart:async';

import 'package:reading_assistant/features/library/data/document_store.dart';

class FakePreferencesStore extends DocumentStore {
  Map<String, Object?>? values;
  Object? loadError;
  Object? saveError;
  Completer<void>? loadGate;
  Completer<void>? saveGate;
  int saveCalls = 0;

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
  }) async {
    saveCalls++;
    await saveGate?.future;
    if (saveError != null) throw saveError!;
    values = {'speed': speed, 'auto_next_page': autoNextPage ? 1 : 0};
  }
}

import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/reading_position.dart';

mixin FakeReadingPositions on DocumentStore {
  final Map<int, ReadingPosition> positions = {};
  Object? positionSaveError;
  Object? positionLoadError;
  int positionWrites = 0;

  @override
  Future<ReadingPosition?> readingPosition(int documentId) async {
    if (positionLoadError != null) throw positionLoadError!;
    return positions[documentId];
  }

  @override
  Future<void> saveReadingPosition({
    required int documentId,
    required int pageId,
    required int sentenceIndex,
    required String pageText,
  }) async {
    positionWrites++;
    if (positionSaveError != null) throw positionSaveError!;
    positions[documentId] = ReadingPosition(
      pageId: pageId,
      sentenceIndex: sentenceIndex,
      pageText: pageText,
    );
  }

  @override
  Future<void> completeReadingPage({
    required int documentId,
    required int pageId,
  }) async {}
}

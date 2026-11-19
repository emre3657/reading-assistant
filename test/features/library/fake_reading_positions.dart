import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/reading_position.dart';

mixin FakeReadingPositions on DocumentStore {
  final Map<int, ReadingPosition> positions = {};
  Object? positionSaveError;
  Object? positionLoadError;
  int positionWrites = 0;
  final Map<int, ReadingPosition> bookmarks = {};
  Object? bookmarkSaveError;
  Object? bookmarkLoadError;

  @override
  Future<ReadingPosition?> bookmark(int documentId) async {
    if (bookmarkLoadError != null) throw bookmarkLoadError!;
    return bookmarks[documentId];
  }

  @override
  Future<void> saveBookmark({
    required int documentId,
    required int pageId,
    required int sentenceIndex,
    required String pageText,
  }) async {
    if (bookmarkSaveError != null) throw bookmarkSaveError!;
    bookmarks[documentId] = ReadingPosition(
      pageId: pageId,
      sentenceIndex: sentenceIndex,
      pageText: pageText,
    );
  }

  @override
  Future<void> removeBookmark(int documentId) async {
    if (bookmarkSaveError != null) throw bookmarkSaveError!;
    bookmarks.remove(documentId);
  }

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

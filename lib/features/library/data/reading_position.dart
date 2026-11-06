class ReadingPosition {
  const ReadingPosition({
    required this.pageId,
    required this.sentenceIndex,
    required this.pageText,
  });

  final int pageId;
  final int sentenceIndex;
  final String pageText;
}

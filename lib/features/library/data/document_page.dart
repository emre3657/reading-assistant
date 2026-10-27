/// One ordered page. Positions are zero-based in storage.
class DocumentPage {
  const DocumentPage({
    required this.id,
    required this.documentId,
    required this.position,
    required this.text,
  });

  final int id;
  final int documentId;
  final int position;
  final String text;

  factory DocumentPage.fromMap(Map<String, Object?> map) {
    return DocumentPage(
      id: map['id'] as int,
      documentId: map['document_id'] as int,
      position: map['position'] as int,
      text: map['text'] as String,
    );
  }
}

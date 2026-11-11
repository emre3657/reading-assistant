class DocumentCategory {
  const DocumentCategory(this.name, this.label);

  static const book = DocumentCategory('book', 'Kitap');
  static const note = DocumentCategory('note', 'Not');
  static const recipe = DocumentCategory('recipe', 'Yemek tarifi');
  static const lesson = DocumentCategory('lesson', 'Ders notu');
  static const lyrics = DocumentCategory('lyrics', 'Şarkı sözü');
  static const values = [book, note, recipe, lesson, lyrics];

  final String name;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is DocumentCategory && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

class SavedDocument {
  const SavedDocument({
    required this.id,
    required this.title,
    required this.category,
    required this.text,
    required this.createdAt,
  });

  final int id;
  final String title;
  final DocumentCategory category;
  final String text;
  final DateTime createdAt;

  factory SavedDocument.fromMap(Map<String, Object?> map) {
    return SavedDocument(
      id: map['id'] as int,
      title: map['title'] as String,
      category: DocumentCategory(
        map['category'] as String,
        map['category_label'] as String,
      ),
      text: map['text'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int,
        isUtc: true,
      ).toLocal(),
    );
  }
}

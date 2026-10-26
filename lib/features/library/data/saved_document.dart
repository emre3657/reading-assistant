enum DocumentCategory {
  book('Kitap'),
  note('Not'),
  recipe('Yemek tarifi'),
  lesson('Ders notu'),
  lyrics('Şarkı sözü');

  const DocumentCategory(this.label);

  final String label;

  static DocumentCategory fromName(String name) {
    return values.firstWhere(
      (category) => category.name == name,
      orElse: () => DocumentCategory.note,
    );
  }
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
      category: DocumentCategory.fromName(map['category'] as String),
      text: map['text'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int,
        isUtc: true,
      ).toLocal(),
    );
  }
}

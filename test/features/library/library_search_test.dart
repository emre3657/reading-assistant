import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/library_screen.dart';

class _Store extends DocumentStore {
  _Store(this.documents);

  List<SavedDocument> documents;
  int listCalls = 0;
  List<DocumentCategory> availableCategories = [...DocumentCategory.values];
  bool failCategories = false;

  @override
  Future<List<SavedDocument>> list() async {
    listCalls++;
    return List.of(documents);
  }

  @override
  Future<List<DocumentCategory>> categories() async {
    if (failCategories) throw StateError('category load failed');
    return List.of(availableCategories);
  }

  @override
  Future<DocumentCategory> renameCategory(
    DocumentCategory category,
    String name,
  ) async {
    final renamed = DocumentCategory(category.name, name.trim());
    availableCategories[availableCategories.indexOf(category)] = renamed;
    documents = documents
        .map(
          (d) => d.category == category
              ? SavedDocument(
                  id: d.id,
                  title: d.title,
                  category: renamed,
                  text: d.text,
                  createdAt: d.createdAt,
                )
              : d,
        )
        .toList();
    return renamed;
  }

  @override
  Future<int> categoryDocumentCount(DocumentCategory category) async =>
      documents.where((d) => d.category == category).length;

  @override
  Future<void> deleteCategory(
    DocumentCategory category, {
    DocumentCategory? target,
  }) async {
    availableCategories.remove(category);
    documents = documents
        .map(
          (d) => d.category == category
              ? SavedDocument(
                  id: d.id,
                  title: d.title,
                  category: target!,
                  text: d.text,
                  createdAt: d.createdAt,
                )
              : d,
        )
        .toList();
  }
}

SavedDocument _document(
  int id,
  String title, {
  DocumentCategory category = DocumentCategory.note,
  DateTime? date,
}) => SavedDocument(
  id: id,
  title: title,
  category: category,
  text: 'Başlık dışında aranmaması gereken metin.',
  createdAt: date ?? DateTime(2024).subtract(Duration(days: id)),
);

final _search = find.byKey(const ValueKey('title-search'));

Future<void> _show(WidgetTester tester, _Store store) async {
  await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
  await tester.pumpAndSettle();
}

Future<void> _searchFor(WidgetTester tester, String query) async {
  await tester.enterText(_search, query);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openFilter(WidgetTester tester) =>
    _tap(tester, find.byKey(const ValueKey('category-filter-button')));

Future<void> _select(WidgetTester tester, String id) =>
    _tap(tester, find.byKey(ValueKey('category-filter-$id')));

Future<void> _sort(WidgetTester tester, String label) async {
  await _tap(tester, find.byKey(const ValueKey('date-order')));
  await _tap(tester, find.text(label).last);
}

void main() {
  testWidgets('multiple categories combine with search, order and clearing', (
    tester,
  ) async {
    final date = DateTime(2025);
    final store = _Store([
      _document(2, 'İstanbul not', category: DocumentCategory.note, date: date),
      _document(
        3,
        'İstanbul kitap',
        category: DocumentCategory.book,
        date: date,
      ),
      _document(
        1,
        'İstanbul tarif',
        category: DocumentCategory.recipe,
        date: date.subtract(const Duration(days: 1)),
      ),
      _document(
        4,
        'Başka kitap',
        category: DocumentCategory.book,
        date: date.add(const Duration(days: 1)),
      ),
    ]);
    await _show(tester, store);
    final badgeFinder = find.descendant(
      of: find.byKey(const ValueKey('category-filter-button')),
      matching: find.byType(Badge),
    );
    expect(tester.widget<Badge>(badgeFinder).isLabelVisible, isFalse);
    await _searchFor(tester, 'istanbul');
    await _openFilter(tester);
    expect(find.text('Tüm kategoriler'), findsOneWidget);
    await _select(tester, 'book');
    await _select(tester, 'note');
    await _tap(tester, find.text('Kapat'));
    expect(tester.widget<Badge>(badgeFinder).isLabelVisible, isTrue);
    expect(
      find.descendant(of: badgeFinder, matching: find.text('2')),
      findsOneWidget,
    );
    expect(find.text('Kategori'), findsOneWidget);
    expect(find.text('İstanbul tarif'), findsNothing);
    expect(find.text('Başka kitap'), findsNothing);
    expect(
      tester.getTopLeft(find.text('İstanbul kitap')).dy,
      lessThan(tester.getTopLeft(find.text('İstanbul not')).dy),
    );
    await _sort(tester, 'En eski');
    expect(
      tester.getTopLeft(find.text('İstanbul not')).dy,
      lessThan(tester.getTopLeft(find.text('İstanbul kitap')).dy),
    );
    await _openFilter(tester);
    await _select(tester, 'book');
    await _select(tester, 'note');
    expect(find.text('Tüm kategoriler'), findsOneWidget);
    await _tap(tester, find.text('Kapat'));
    expect(tester.widget<Badge>(badgeFinder).isLabelVisible, isFalse);
    expect(find.text('İstanbul tarif'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('İstanbul tarif')).dy,
      lessThan(tester.getTopLeft(find.text('İstanbul not')).dy),
    );
    await _openFilter(tester);
    await _select(tester, 'book');
    await _select(tester, 'note');
    await _tap(tester, find.text('Temizle'));
    expect(find.text('Tüm kategoriler'), findsOneWidget);
    await _tap(tester, find.text('Kapat'));
    expect(tester.widget<TextField>(_search).controller!.text, 'istanbul');
    expect(find.text('En eski'), findsOneWidget);
    expect(find.text('İstanbul tarif'), findsOneWidget);
    expect(store.listCalls, 1);
    await _sort(tester, 'En yeni');
    expect(
      tester.getTopLeft(find.text('İstanbul kitap')).dy,
      lessThan(tester.getTopLeft(find.text('İstanbul tarif')).dy),
    );
  });

  testWidgets('category rename and deletion reconcile identity on return', (
    tester,
  ) async {
    final store = _Store([
      _document(1, 'Kitap kaydı', category: DocumentCategory.book),
      _document(2, 'Not kaydı'),
    ]);
    await _show(tester, store);
    await _openFilter(tester);
    await _select(tester, 'book');
    await _tap(tester, find.text('Kapat'));
    await _tap(tester, find.byTooltip('Kayıtlarım menüsü'));
    await _tap(tester, find.text('Kategorileri yönet'));
    await _tap(tester, find.byTooltip('Kitap kategori seçenekleri'));
    await _tap(tester, find.text('Yeniden adlandır'));
    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      'Okuduklarım',
    );
    await _tap(tester, find.widgetWithText(FilledButton, 'Kaydet'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Kitap kaydı'), findsOneWidget);
    expect(find.text('Not kaydı'), findsNothing);
    expect(find.text('Okuduklarım'), findsOneWidget);
    await _openFilter(tester);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('category-filter-book')),
          )
          .value,
      isTrue,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('category-filter-book')),
        matching: find.text('Okuduklarım'),
      ),
      findsOneWidget,
    );
    await _tap(tester, find.text('Kapat'));
    await _tap(tester, find.byTooltip('Kayıtlarım menüsü'));
    await _tap(tester, find.text('Kategorileri yönet'));
    await _tap(tester, find.byTooltip('Okuduklarım kategori seçenekleri'));
    await _tap(tester, find.text('Sil'));
    await _tap(
      tester,
      find.byKey(const ValueKey('category-delete-target-null')),
    );
    await _tap(tester, find.text('Not').last);
    await _tap(tester, find.byKey(const ValueKey('confirm-category-delete')));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Kitap kaydı'), findsOneWidget);
    expect(find.text('Not kaydı'), findsOneWidget);
    final badge = tester.widget<Badge>(
      find.descendant(
        of: find.byKey(const ValueKey('category-filter-button')),
        matching: find.byType(Badge),
      ),
    );
    expect(badge.isLabelVisible, isFalse);
  });

  testWidgets(
    'filter empty state and failed category refresh preserve choices',
    (tester) async {
      final store = _Store([_document(1, 'Başlık')]);
      await _show(tester, store);
      await _openFilter(tester);
      await _select(tester, 'book');
      await _tap(tester, find.text('Kapat'));
      expect(
        find.text('Aramana veya filtrelerine uygun kayıt bulunamadı.'),
        findsOneWidget,
      );
      store.failCategories = true;
      await _tap(tester, find.byTooltip('Yenile'));
      expect(
        find.text('Kategoriler yenilenemedi. Tekrar deneyebilirsin.'),
        findsOneWidget,
      );
      expect(
        find.text('Aramana veya filtrelerine uygun kayıt bulunamadı.'),
        findsOneWidget,
      );
      store.failCategories = false;
      await _openFilter(tester);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('category-filter-book')),
            )
            .value,
        isTrue,
      );
      await _tap(tester, find.text('Kapat'));
      store.documents = [];
      await _tap(tester, find.byTooltip('Yenile'));
      expect(
        find.text(
          'Henüz kayıt yok. Çıkardığın metni kaydederek başlayabilirsin.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Aramana veya filtrelerine uygun kayıt bulunamadı.'),
        findsNothing,
      );
    },
  );

  testWidgets('partial search preserves order and clearing shows all', (
    tester,
  ) async {
    final store = _Store([
      _document(1, 'Gezi notları'),
      _document(2, 'Tarifler'),
      _document(3, 'Ders notları'),
    ]);
    await _show(tester, store);
    await _searchFor(tester, '  NOT  ');
    expect(find.text('Gezi notları'), findsOneWidget);
    expect(find.text('Ders notları'), findsOneWidget);
    expect(find.text('Tarifler'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Gezi notları')).dy,
      lessThan(tester.getTopLeft(find.text('Ders notları')).dy),
    );
    expect(store.listCalls, 1);
    await tester.tap(find.byTooltip('Aramayı temizle'));
    await tester.pumpAndSettle();
    expect(find.text('Tarifler'), findsOneWidget);
    expect(find.byTooltip('Aramayı temizle'), findsNothing);
    await _searchFor(tester, '   ');
    expect(find.text('Gezi notları'), findsOneWidget);
    expect(find.text('Tarifler'), findsOneWidget);
    expect(find.text('Ders notları'), findsOneWidget);
  });

  testWidgets('uses Turkish case pairs without folding different letters', (
    tester,
  ) async {
    await _show(
      tester,
      _Store([
        _document(1, 'İstanbul Gezi Notları'),
        _document(2, 'IŞIK'),
        _document(3, 'Isik'),
        _document(4, 'Şeker'),
        _document(5, 'Seker'),
      ]),
    );
    await _searchFor(tester, 'istanbul');
    expect(find.text('İstanbul Gezi Notları'), findsOneWidget);
    expect(find.text('IŞIK'), findsNothing);
    await _searchFor(tester, 'ışık');
    expect(find.text('IŞIK'), findsOneWidget);
    expect(find.text('Isik'), findsNothing);
    await _searchFor(tester, 'IŞIK');
    expect(find.byKey(const ValueKey('document-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('document-3')), findsNothing);
    await _searchFor(tester, 'ŞEKER');
    expect(find.text('Şeker'), findsOneWidget);
    expect(find.text('Seker'), findsNothing);
    await _searchFor(tester, 'seker');
    expect(find.text('Seker'), findsOneWidget);
    expect(find.text('Şeker'), findsNothing);
    await _searchFor(tester, 'dışında');
    expect(
      find.text('Aramana veya filtrelerine uygun kayıt bulunamadı.'),
      findsOneWidget,
    );
  });

  testWidgets('distinguishes no matches from an empty library', (tester) async {
    final store = _Store([_document(1, 'Başlık')]);
    await _show(tester, store);
    await _searchFor(tester, 'yok');
    expect(
      find.text('Aramana veya filtrelerine uygun kayıt bulunamadı.'),
      findsOneWidget,
    );
    store.documents = [];
    await tester.tap(find.byTooltip('Yenile'));
    await tester.pumpAndSettle();
    expect(
      find.text('Aramana veya filtrelerine uygun kayıt bulunamadı.'),
      findsNothing,
    );
    expect(
      find.text(
        'Henüz kayıt yok. Çıkardığın metni kaydederek başlayabilirsin.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(_search).controller!.text, 'yok');
  });

  testWidgets('refresh reapplies the existing query to updated titles', (
    tester,
  ) async {
    final store = _Store([
      _document(1, 'Eski başlık'),
      _document(2, 'Aranan not'),
    ]);
    await _show(tester, store);
    await _searchFor(tester, 'aranan');
    store.documents = [
      _document(1, 'Aranan yeni başlık'),
      _document(2, 'Değişmiş başlık'),
    ];
    await tester.tap(find.byTooltip('Yenile'));
    await tester.pumpAndSettle();
    expect(find.text('Aranan yeni başlık'), findsOneWidget);
    expect(find.text('Değişmiş başlık'), findsNothing);
    expect(tester.widget<TextField>(_search).controller!.text, 'aranan');
    expect(store.listCalls, 2);
  });

  testWidgets('search remains accessible with large text on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _show(tester, _Store([_document(1, 'İstanbul')]));
    await _searchFor(tester, 'istanbul');
    expect(find.text('İstanbul'), findsOneWidget);
    expect(find.byTooltip('Aramayı temizle').hitTestable(), findsOneWidget);
    await _openFilter(tester);
    await _select(tester, 'note');
    await _tap(tester, find.text('Temizle'));
    await _tap(tester, find.text('Kapat'));
    expect(find.text('İstanbul'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/document_store.dart';
import 'package:reading_assistant/features/library/data/saved_document.dart';
import 'package:reading_assistant/features/library/presentation/library_screen.dart';

class _Store extends DocumentStore {
  _Store(this.documents);

  List<SavedDocument> documents;
  int listCalls = 0;

  @override
  Future<List<SavedDocument>> list() async {
    listCalls++;
    return List.of(documents);
  }
}

SavedDocument _document(int id, String title) => SavedDocument(
  id: id,
  title: title,
  category: DocumentCategory.note,
  text: 'Başlık dışında aranmaması gereken metin.',
  createdAt: DateTime(2024),
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

void main() {
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
    expect(find.text('Aramana uygun kayıt bulunamadı.'), findsOneWidget);
  });

  testWidgets('distinguishes no matches from an empty library', (tester) async {
    final store = _Store([_document(1, 'Başlık')]);
    await _show(tester, store);
    await _searchFor(tester, 'yok');
    expect(find.text('Aramana uygun kayıt bulunamadı.'), findsOneWidget);
    store.documents = [];
    await tester.tap(find.byTooltip('Yenile'));
    await tester.pumpAndSettle();
    expect(find.text('Aramana uygun kayıt bulunamadı.'), findsNothing);
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
    expect(tester.takeException(), isNull);
  });
}

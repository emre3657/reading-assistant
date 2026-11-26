import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openHomeReadingSettings(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppBar),
      matching: find.byTooltip('Diğer seçenekler'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Görünüm ve sesli okuma'));
  await tester.pumpAndSettle();
}

Finder get playbackMenu => find.descendant(
  of: find.byKey(const ValueKey('listening-panel')),
  matching: find.byTooltip('Diğer seçenekler'),
);

Finder readingControl(String label) =>
    {
      'Sesli oku',
      'Duraklat',
      'Devam et',
      'Önceki cümle',
      'Sonraki cümle',
    }.contains(label)
    ? find.byTooltip(label)
    : find.text(label);

Future<void> tapReadingControl(WidgetTester tester, String label) async {
  if (label == 'Durdur' || label == 'Başa dön') {
    await tester.tap(playbackMenu);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text(label));
  } else {
    await tester.tap(readingControl(label));
  }
}

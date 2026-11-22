import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reading_assistant/features/image_import/presentation/crop_screen.dart';

void main() {
  Future<void> loadImage(WidgetTester tester, ImageProvider image) async {
    await tester.pump();
    await tester.runAsync(
      () => precacheImage(
        ResizeImage(
          image,
          width: 1200,
          height: 1200,
          policy: ResizeImagePolicy.fit,
        ),
        tester.element(find.byType(MaterialApp)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('handles edit the selection and cancel and back discard it', (
    tester,
  ) async {
    final image = MemoryImage(img.encodePng(img.Image(width: 80, height: 40)));
    Rect? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<Rect>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CropScreen(image: image, quarterTurns: 0),
                  ),
                );
              },
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Aç'));
    await loadImage(tester, image);
    expect(find.text('Uygula'), findsOneWidget);
    final handle = find.byKey(const ValueKey('crop-handle--1-0'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.left, greaterThan(0));
    expect(result!.right, 1);

    await tester.tap(find.text('Aç'));
    await loadImage(tester, image);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.tap(find.text('Aç'));
    await loadImage(tester, image);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('crop actions remain available with large text in landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final image = MemoryImage(img.encodePng(img.Image(width: 80, height: 40)));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: CropScreen(image: image, quarterTurns: 1),
        ),
      ),
    );
    await loadImage(tester, image);
    await tester.ensureVisible(find.text('Uygula'));
    expect(tester.takeException(), isNull);
    expect(find.text('Vazgeç'), findsOneWidget);
    expect(find.text('Uygula'), findsOneWidget);
  });

  testWidgets('pinch zoom keeps crop handles usable', (tester) async {
    final image = MemoryImage(img.encodePng(img.Image(width: 80, height: 40)));
    Rect? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<Rect>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CropScreen(image: image, quarterTurns: 0),
                  ),
                );
              },
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Aç'));
    await loadImage(tester, image);
    final center = tester.getCenter(find.byKey(const ValueKey('crop-zoom')));
    final first = await tester.startGesture(
      center + const Offset(-60, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(60, 0),
      pointer: 2,
    );
    await first.moveBy(const Offset(-80, 0));
    await second.moveBy(const Offset(80, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    final handle = find.byKey(const ValueKey('crop-handle-1-0'));
    final zoom = tester.getRect(handle).width / 48;
    expect(zoom, greaterThan(1.2));
    // Panning first brings the right handle back inside the viewport.
    final pan = await tester.startGesture(center);
    await pan.moveBy(const Offset(-40, 0));
    await pan.moveBy(const Offset(-200, 0));
    await pan.moveBy(const Offset(-200, 0));
    await pan.moveBy(const Offset(-200, 0));
    await pan.up();
    await tester.pumpAndSettle();
    final pos = tester.getCenter(handle);
    expect(pos.dx, inInclusiveRange(0, 800));
    final drag = await tester.startGesture(pos);
    await drag.moveBy(const Offset(-30, 0));
    await drag.moveBy(const Offset(-30, 0));
    await drag.moveBy(const Offset(-150, 0));
    await drag.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();
    expect(result!.right, closeTo(1 - 150 / (752 * zoom), .02));
  });
}

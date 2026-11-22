import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/listening/presentation/page_transition.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';

void main() {
  for (final forward in [true, false]) {
    testWidgets('slide moves pages in opposite directions, forward=$forward', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 200,
            height: 200,
            child: ReadingPageTransition(
              animation: const AlwaysStoppedAnimation(0.25),
              effect: PageAnimationEffect.slide,
              forward: forward,
              previous: const Text('Eski'),
              child: const Text('Yeni'),
            ),
          ),
        ),
      );
      final translations = tester
          .widgetList<FractionalTranslation>(
            find.descendant(
              of: find.byType(ReadingPageTransition),
              matching: find.byType(FractionalTranslation),
            ),
          )
          .toList();
      expect(translations, hasLength(2));
      expect(translations[0].translation.dy.sign, forward ? -1 : 1);
      expect(translations[1].translation.dy.sign, forward ? 1 : -1);
    });

    testWidgets(
      'curl reveals the correct side without mirroring, forward=$forward',
      (tester) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 100, 100),
          Paint()..color = Colors.blue,
        );
        canvas.drawRect(
          const Rect.fromLTWH(100, 0, 100, 100),
          Paint()..color = Colors.green,
        );
        final picture = recorder.endRecording();
        final image = picture.toImageSync(200, 100);
        addTearDown(() {
          image.dispose();
          picture.dispose();
        });
        final key = GlobalKey();
        Future<List<Color>> frame(double progress) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: 200,
                    height: 100,
                    child: ReadingPageTransition(
                      animation: AlwaysStoppedAnimation(progress),
                      effect: PageAnimationEffect.turn,
                      forward: forward,
                      previous: const SizedBox(),
                      snapshot: image,
                      paperColor: Colors.white,
                      child: const ColoredBox(color: Colors.red),
                    ),
                  ),
                ),
              ),
            ),
          );
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final captured = boundary.toImageSync();
          final data = await tester.runAsync(
            () => captured.toByteData(format: ui.ImageByteFormat.rawRgba),
          );
          captured.dispose();
          Color pixel(int x) {
            final offset = (50 * 200 + x) * 4;
            return Color.fromARGB(
              data!.getUint8(offset + 3),
              data.getUint8(offset),
              data.getUint8(offset + 1),
              data.getUint8(offset + 2),
            );
          }

          return [pixel(20), pixel(180), pixel(95), pixel(105)];
        }

        const blue = Color(0xff2196f3);
        const green = Color(0xff4caf50);
        const red = Color(0xfff44336);
        expect((await frame(0)).take(2), [blue, green]);
        final middle = await frame(0.5);
        expect(middle.take(2), forward ? [blue, red] : [red, green]);
        final curl = middle[forward ? 3 : 2];
        expect(curl, isNot(red));
        expect(curl, isNot(forward ? green : blue));
        expect((await frame(1)).take(2), [red, red]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

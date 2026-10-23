import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/main.dart';

const _selectLabel = 'Galeriden görsel seç';
const _changeLabel = 'Görseli değiştir';
const _removeLabel = 'Görseli kaldır';

Future<XFile?> _noLostImage() async => null;

Widget _app(PickImage pickImage) {
  return ReadingAssistantApp(
    pickImage: pickImage,
    retrieveLostImage: _noLostImage,
  );
}

void main() {
  testWidgets('shows empty state with select button', (tester) async {
    await tester.pumpWidget(_app(() async => null));
    await tester.pump();

    expect(find.text(_selectLabel), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.text(_removeLabel), findsNothing);
  });

  testWidgets('shows preview and change/remove buttons after picking', (
    tester,
  ) async {
    await tester.pumpWidget(_app(() async => XFile('/tmp/a.png')));
    await tester.pump();

    await tester.tap(find.text(_selectLabel));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text(_changeLabel), findsOneWidget);
    expect(find.text(_removeLabel), findsOneWidget);
    expect(find.text(_selectLabel), findsNothing);
  });

  testWidgets('keeps current image when picking is cancelled', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(() async => calls++ == 0 ? XFile('/tmp/a.png') : null),
    );
    await tester.pump();

    await tester.tap(find.text(_selectLabel));
    await tester.pump();
    await tester.tap(find.text(_changeLabel));
    await tester.pump();

    expect(calls, 2);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text(_removeLabel), findsOneWidget);
  });

  testWidgets('removes the image', (tester) async {
    await tester.pumpWidget(_app(() async => XFile('/tmp/a.png')));
    await tester.pump();

    await tester.tap(find.text(_selectLabel));
    await tester.pump();
    await tester.tap(find.text(_removeLabel));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.text(_selectLabel), findsOneWidget);
  });

  testWidgets('shows Turkish error when picking fails', (tester) async {
    await tester.pumpWidget(_app(() async => throw Exception('boom')));
    await tester.pump();

    await tester.tap(find.text(_selectLabel));
    await tester.pump();

    expect(
      find.text('Görsel seçilemedi. Lütfen tekrar deneyin.'),
      findsOneWidget,
    );
    expect(find.text(_selectLabel), findsOneWidget);
  });

  testWidgets('blocks a second pick while one is in progress', (tester) async {
    final completer = Completer<XFile?>();
    var calls = 0;
    await tester.pumpWidget(
      _app(() {
        calls++;
        return completer.future;
      }),
    );
    await tester.pump();

    await tester.tap(find.text(_selectLabel));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(_selectLabel), findsNothing);
    expect(calls, 1);

    completer.complete(null);
    await tester.pump();

    expect(find.text(_selectLabel), findsOneWidget);
  });

  testWidgets('recovers a lost image on Android startup', (tester) async {
    await tester.pumpWidget(
      ReadingAssistantApp(
        pickImage: () async => null,
        retrieveLostImage: () async => XFile('/tmp/lost.png'),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text(_removeLabel), findsOneWidget);
  });

  testWidgets('stays scrollable with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 3.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(_app(() async => XFile('/tmp/a.png')));
    await tester.pump();
    await tester.tap(find.text(_selectLabel));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}

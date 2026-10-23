import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/app.dart';
import 'package:reading_assistant/features/image_import/presentation/widgets/image_preview.dart';

import 'test_doubles.dart';

const _selectLabel = 'Galeriden görsel seç';
const _changeLabel = 'Görseli değiştir';
const _removeLabel = 'Görseli kaldır';
const _previewError = 'Görsel görüntülenemedi. Lütfen başka bir görsel seçin.';

Future<void> _pumpApp(
  WidgetTester tester,
  FakeImagePickerService picker, {
  List<ControlledImageProvider>? providers,
}) async {
  await tester.pumpWidget(
    ReadingAssistantApp(
      pickerService: picker,
      previewImageBuilder: (file) {
        final provider = ControlledImageProvider();
        providers?.add(provider);
        return provider;
      },
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows empty state with select button', (tester) async {
    await _pumpApp(tester, FakeImagePickerService());

    expect(find.text(_selectLabel), findsOneWidget);
    expect(find.byType(ImagePreview), findsNothing);
    expect(find.text(_removeLabel), findsNothing);
  });

  testWidgets('shows preview and change/remove buttons after picking', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      FakeImagePickerService(onPick: () async => XFile('/tmp/a.png')),
    );

    await tester.tap(find.text(_selectLabel));
    await tester.pump();

    expect(find.byType(ImagePreview), findsOneWidget);
    expect(find.text(_changeLabel), findsOneWidget);
    expect(find.text(_removeLabel), findsOneWidget);
    expect(find.text(_selectLabel), findsNothing);
  });

  testWidgets('keeps current image when picking is cancelled', (tester) async {
    var calls = 0;
    await _pumpApp(
      tester,
      FakeImagePickerService(
        onPick: () async => calls++ == 0 ? XFile('/tmp/a.png') : null,
      ),
    );

    await tester.tap(find.text(_selectLabel));
    await tester.pump();
    await tester.tap(find.text(_changeLabel));
    await tester.pump();

    expect(calls, 2);
    expect(find.byType(ImagePreview), findsOneWidget);
    expect(find.text(_removeLabel), findsOneWidget);
  });

  testWidgets('removes the image', (tester) async {
    await _pumpApp(
      tester,
      FakeImagePickerService(onPick: () async => XFile('/tmp/a.png')),
    );

    await tester.tap(find.text(_selectLabel));
    await tester.pump();
    await tester.tap(find.text(_removeLabel));
    await tester.pump();

    expect(find.byType(ImagePreview), findsNothing);
    expect(find.text(_selectLabel), findsOneWidget);
  });

  testWidgets('shows Turkish error when picking fails', (tester) async {
    await _pumpApp(
      tester,
      FakeImagePickerService(onPick: () async => throw Exception('boom')),
    );

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
    await _pumpApp(
      tester,
      FakeImagePickerService(
        onPick: () {
          calls++;
          return completer.future;
        },
      ),
    );

    await tester.tap(find.text(_selectLabel));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(_selectLabel), findsNothing);
    expect(calls, 1);

    completer.complete(null);
    await tester.pump();

    expect(find.text(_selectLabel), findsOneWidget);
  });

  testWidgets('recovers a lost image on startup', (tester) async {
    await _pumpApp(
      tester,
      FakeImagePickerService(
        canRecoverLostImage: true,
        onRetrieveLost: () async => XFile('/tmp/lost.png'),
      ),
    );

    expect(find.byType(ImagePreview), findsOneWidget);
    expect(find.text(_removeLabel), findsOneWidget);
  });

  testWidgets('stays scrollable with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 3.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpApp(
      tester,
      FakeImagePickerService(onPick: () async => XFile('/tmp/a.png')),
    );
    await tester.tap(find.text(_selectLabel));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('late error of a replaced preview does not affect the new one', (
    tester,
  ) async {
    final providers = <ControlledImageProvider>[];
    var calls = 0;
    await _pumpApp(
      tester,
      FakeImagePickerService(
        onPick: () async => XFile('/tmp/${calls++ == 0 ? 'a' : 'b'}.png'),
      ),
      providers: providers,
    );

    await tester.tap(find.text(_selectLabel));
    await tester.pump();
    await tester.tap(find.text(_changeLabel));
    await tester.pump();
    expect(providers, hasLength(2));

    providers.first.fail();
    await tester.pump();
    await tester.pump();

    expect(find.byType(ImagePreview), findsOneWidget);
    expect(find.text(_previewError), findsNothing);
  });

  testWidgets('late error of the same file picked earlier does not affect '
      'the new selection', (tester) async {
    final providers = <ControlledImageProvider>[];
    await _pumpApp(
      tester,
      FakeImagePickerService(onPick: () async => XFile('/tmp/same.png')),
      providers: providers,
    );

    await tester.tap(find.text(_selectLabel));
    await tester.pump();
    await tester.tap(find.text(_changeLabel));
    await tester.pump();
    expect(providers, hasLength(2));

    providers.first.fail();
    await tester.pump();
    await tester.pump();

    expect(find.byType(ImagePreview), findsOneWidget);
    expect(find.text(_previewError), findsNothing);
  });

  testWidgets('removes the image and explains when the active preview fails', (
    tester,
  ) async {
    final providers = <ControlledImageProvider>[];
    await _pumpApp(
      tester,
      FakeImagePickerService(onPick: () async => XFile('/tmp/a.png')),
      providers: providers,
    );

    await tester.tap(find.text(_selectLabel));
    await tester.pump();
    providers.single.fail();
    await tester.pump();
    await tester.pump();

    expect(find.byType(ImagePreview), findsNothing);
    expect(find.text(_previewError), findsOneWidget);
    expect(find.text(_selectLabel), findsOneWidget);
  });
}

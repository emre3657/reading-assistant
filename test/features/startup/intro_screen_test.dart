import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/app.dart';
import 'package:reading_assistant/features/image_import/presentation/widgets/image_preview.dart';
import 'package:reading_assistant/features/startup/intro_screen.dart';

import '../image_import/test_doubles.dart';
import '../listening/fake_preferences_store.dart';
import '../listening/fake_speech_service.dart';

Future<void> _open(
  WidgetTester tester,
  FakePreferencesStore store, {
  FakeImagePickerService? picker,
}) async {
  await tester.pumpWidget(
    ReadingAssistantApp(
      store: store,
      pickerService: picker ?? FakeImagePickerService(),
      previewImageBuilder: (_) => ControlledImageProvider(),
      speechService: FakeSpeechService(),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('first launch completes once and next launch skips intro', (
    tester,
  ) async {
    final store = FakePreferencesStore()..introCompleted = false;
    await _open(tester, store);
    expect(find.byType(IntroScreen), findsOneWidget);
    expect(find.text('Okuma Asistanı'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(introDuration);
    await tester.pump();
    expect(find.byType(IntroScreen), findsNothing);
    expect(find.text('Galeriden görsel seç'), findsOneWidget);
    expect(store.introCompleted, isTrue);
    expect(store.introWriteCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await _open(tester, store);
    expect(find.byType(IntroScreen), findsNothing);
    expect(store.introWriteCalls, 1);
  });

  testWidgets('skip saves once and opens recovered image afterward', (
    tester,
  ) async {
    final store = FakePreferencesStore()..introCompleted = false;
    var retrievals = 0;
    final picker = FakeImagePickerService(
      canRecoverLostImage: true,
      onRetrieveLost: () async {
        retrievals++;
        return XFile('lost.png');
      },
    );
    await _open(tester, store, picker: picker);
    expect(retrievals, 0);
    await tester.tap(find.text('Atla'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(IntroScreen), findsNothing);
    expect(find.byType(ImagePreview), findsOneWidget);
    expect(retrievals, 1);
    expect(store.introWriteCalls, 1);
    await tester.pump(introDuration);
    expect(store.introWriteCalls, 1);
  });

  testWidgets('back skips intro rather than returning to it', (tester) async {
    final store = FakePreferencesStore()..introCompleted = false;
    await _open(tester, store);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(IntroScreen), findsNothing);
    expect(find.text('Galeriden görsel seç'), findsOneWidget);
    expect(store.introWriteCalls, 1);
  });

  testWidgets('completion and skip near the end write only once', (
    tester,
  ) async {
    final store = FakePreferencesStore()
      ..introCompleted = false
      ..introWriteGate = Completer<void>();
    await _open(tester, store);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(introDuration - const Duration(milliseconds: 50));
    await tester.tap(find.text('Atla'));
    await tester.pump(introDuration);
    expect(store.introWriteCalls, 1);
    expect(find.text('Galeriden görsel seç'), findsOneWidget);
    store.introWriteGate!.complete();
    await tester.pump();
    expect(store.introCompleted, isTrue);
  });

  testWidgets('closing while startup loads does not update disposed app', (
    tester,
  ) async {
    final store = FakePreferencesStore()..introReadGate = Completer<void>();
    await _open(tester, store);
    await tester.pumpWidget(const SizedBox.shrink());
    store.introReadGate!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during animation cancels its pending completion', (
    tester,
  ) async {
    final store = FakePreferencesStore()..introCompleted = false;
    await _open(tester, store);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(introDuration);
    expect(store.introWriteCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion skips and saves completion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final store = FakePreferencesStore()..introCompleted = false;
    await _open(tester, store);
    await tester.pump();
    expect(find.byType(IntroScreen), findsNothing);
    expect(find.text('Galeriden görsel seç'), findsOneWidget);
    expect(store.introCompleted, isTrue);
  });

  testWidgets('animation pauses in background and resumes once', (
    tester,
  ) async {
    final store = FakePreferencesStore()..introCompleted = false;
    await _open(tester, store);
    await tester.pump(const Duration(milliseconds: 300));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(IntroScreen), findsOneWidget);
    expect(store.introWriteCalls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(introDuration);
    await tester.pump();
    expect(find.byType(IntroScreen), findsNothing);
    expect(store.introWriteCalls, 1);
  });

  testWidgets('startup waits for local settings without a second logo', (
    tester,
  ) async {
    final store = FakePreferencesStore()
      ..introCompleted = false
      ..introReadGate = Completer<void>();
    await _open(tester, store);
    expect(find.byType(IntroScreen), findsNothing);
    expect(find.text('Galeriden görsel seç'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    store.introReadGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(IntroScreen), findsOneWidget);
  });

  testWidgets('read and write failures do not block access', (tester) async {
    final failedRead = FakePreferencesStore()
      ..introReadError = StateError('read');
    await _open(tester, failedRead);
    await tester.pump();
    expect(find.text('Galeriden görsel seç'), findsOneWidget);
    expect(find.textContaining('Açılış tercihi okunamadı'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final failedWrite = FakePreferencesStore()
      ..introCompleted = false
      ..introWriteError = StateError('write');
    await _open(tester, failedWrite);
    await tester.tap(find.text('Atla'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Galeriden görsel seç'), findsOneWidget);
    expect(find.textContaining('Açılış tercihi kaydedilemedi'), findsOneWidget);
  });

  testWidgets('narrow screen and large text keep skip usable', (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _open(tester, FakePreferencesStore()..introCompleted = false);
    expect(find.text('Atla').hitTestable(), findsOneWidget);
    expect(
      tester.getSize(find.byType(TextButton).first).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.text('Okuma Asistanı'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

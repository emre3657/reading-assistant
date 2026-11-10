import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reading_assistant/features/image_import/services/image_picker_service.dart';

class _Picker extends ImagePicker {
  Completer<XFile?>? gate;
  final opened = Completer<void>();
  LostDataResponse response = LostDataResponse.empty();
  ImageSource? source;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    opened.complete();
    return gate?.future;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async => response;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late _Picker picker;
  late ImagePickerService service;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    dir = await Directory.systemTemp.createTemp('camera-recovery-test-');
    picker = _Picker();
    service = ImagePickerService(
      pickerFactory: () => picker,
      databaseDirectory: () async => dir.path,
    );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await dir.delete(recursive: true);
  });

  File marker() => File(
    '${dir.path}${Platform.pathSeparator}reading_assistant_pending_camera',
  );

  test(
    'camera writes the target before opening and clears it on return',
    () async {
      picker.gate = Completer<XFile?>();
      final pending = service.takePhoto(recoverToHome: false);
      await picker.opened.future;
      expect(await marker().readAsString(), 'page');
      expect(picker.source, ImageSource.camera);
      await expectLater(service.pickFromGallery(), throwsStateError);
      picker.gate!.complete(XFile('/camera.jpg'));
      expect((await pending)?.path, '/camera.jpg');
      expect(await marker().exists(), isFalse);
    },
  );

  test('home camera and unmarked gallery results can recover', () async {
    picker.response = LostDataResponse(file: XFile('/lost.jpg'));
    await marker().writeAsString('home');
    expect((await service.retrieveLostImage())?.path, '/lost.jpg');
    expect(await marker().exists(), isFalse);
    expect((await service.retrieveLostImage())?.path, '/lost.jpg');
  });

  test('a page camera or invalid target never becomes a home image', () async {
    picker.response = LostDataResponse(file: XFile('/lost.jpg'));
    for (final target in ['page', 'corrupted']) {
      await marker().writeAsString(target);
      await expectLater(
        service.retrieveLostImage(),
        throwsA(isA<LostCameraPageException>()),
      );
      expect(await marker().exists(), isFalse);
    }
  });
}

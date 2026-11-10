import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';

class LostCameraPageException implements Exception {
  const LostCameraPageException();
}

/// Wraps the system gallery picker so screens and tests do not touch the
/// platform plugin directly.
class ImagePickerService {
  const ImagePickerService({this.pickerFactory, this.databaseDirectory});

  final ImagePicker Function()? pickerFactory;
  final Future<String> Function()? databaseDirectory;
  static bool _operationInProgress = false;

  ImagePicker _picker() => pickerFactory?.call() ?? ImagePicker();

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_operationInProgress) {
      throw StateError('Another image picker operation is in progress.');
    }
    _operationInProgress = true;
    try {
      return await action();
    } finally {
      _operationInProgress = false;
    }
  }

  /// Lost picker results only exist on Android.
  bool get canRecoverLostImage =>
      defaultTargetPlatform == TargetPlatform.android;

  /// Opens the system photo picker. Returns null when the user cancels.
  Future<XFile?> pickFromGallery() => _run(() {
    // Full metadata is not needed and would request extra photo permissions.
    return _picker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
  });

  Future<XFile?> takePhoto({required bool recoverToHome}) => _run(() async {
    File? marker;
    if (canRecoverLostImage) {
      marker = await _cameraMarker();
      await marker.parent.create(recursive: true);
      await marker.writeAsString(recoverToHome ? 'home' : 'page', flush: true);
    }
    try {
      return await _picker().pickImage(
        source: ImageSource.camera,
        requestFullMetadata: false,
      );
    } finally {
      if (marker != null && await marker.exists()) await marker.delete();
    }
  });

  Future<File> _cameraMarker() async {
    final directory = await (databaseDirectory?.call() ?? getDatabasesPath());
    return File(
      '$directory${Platform.pathSeparator}reading_assistant_pending_camera',
    );
  }

  /// Returns an image picked before Android killed the activity, if any.
  Future<XFile?> retrieveLostImage() => _run(() async {
    final marker = await _cameraMarker();
    final cameraTarget = await marker.exists()
        ? await marker.readAsString()
        : null;
    final response = await _picker().retrieveLostData();
    if (await marker.exists()) await marker.delete();
    if (response.isEmpty) return null;
    if (response.exception != null) throw response.exception!;
    if (cameraTarget != null && cameraTarget != 'home') {
      throw const LostCameraPageException();
    }
    return response.file ?? response.files?.firstOrNull;
  });
}

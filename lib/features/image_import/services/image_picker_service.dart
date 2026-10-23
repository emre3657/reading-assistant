import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Wraps the system gallery picker so screens and tests do not touch the
/// platform plugin directly.
class ImagePickerService {
  const ImagePickerService();

  /// Lost picker results only exist on Android.
  bool get canRecoverLostImage =>
      defaultTargetPlatform == TargetPlatform.android;

  /// Opens the system photo picker. Returns null when the user cancels.
  Future<XFile?> pickFromGallery() {
    // Full metadata is not needed and would request extra photo permissions.
    return ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
  }

  /// Returns an image picked before Android killed the activity, if any.
  Future<XFile?> retrieveLostImage() async {
    final response = await ImagePicker().retrieveLostData();
    if (response.isEmpty) return null;
    if (response.exception != null) throw response.exception!;
    return response.file ?? response.files?.firstOrNull;
  }
}

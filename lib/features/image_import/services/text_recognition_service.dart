import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Wraps on-device ML Kit text recognition (Latin script) so screens and tests
/// do not touch the platform plugin directly.
class TextRecognitionService {
  const TextRecognitionService();

  /// Recognizes text in the image file at [imagePath].
  ///
  /// The file is read as is; it is never resized or modified. The recognizer
  /// is closed only after native processing has finished.
  Future<String> recognizeText(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return result.text;
    } finally {
      await recognizer.close();
    }
  }
}

import 'package:flutter/material.dart';

import 'features/image_import/presentation/image_import_screen.dart';
import 'features/image_import/services/image_picker_service.dart';
import 'features/image_import/services/image_rotation_service.dart';
import 'features/image_import/services/text_recognition_service.dart';
import 'features/listening/services/speech_service.dart';

class ReadingAssistantApp extends StatelessWidget {
  const ReadingAssistantApp({
    super.key,
    this.pickerService = const ImagePickerService(),
    this.textRecognitionService = const TextRecognitionService(),
    this.rotationService = const ImageRotationService(),
    this.previewImageBuilder = fileImageProvider,
    this.speechService,
  });

  final ImagePickerService pickerService;
  final TextRecognitionService textRecognitionService;
  final ImageRotationService rotationService;
  final PreviewImageBuilder previewImageBuilder;
  final SpeechService? speechService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reading Assistant',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: ImageImportScreen(
        pickerService: pickerService,
        textRecognitionService: textRecognitionService,
        rotationService: rotationService,
        previewImageBuilder: previewImageBuilder,
        speechService: speechService,
      ),
    );
  }
}

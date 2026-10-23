import 'package:flutter/material.dart';

import 'features/image_import/presentation/image_import_screen.dart';
import 'features/image_import/services/image_picker_service.dart';

class ReadingAssistantApp extends StatelessWidget {
  const ReadingAssistantApp({
    super.key,
    this.pickerService = const ImagePickerService(),
    this.previewImageBuilder = fileImageProvider,
  });

  final ImagePickerService pickerService;
  final PreviewImageBuilder previewImageBuilder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reading Assistant',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: ImageImportScreen(
        pickerService: pickerService,
        previewImageBuilder: previewImageBuilder,
      ),
    );
  }
}

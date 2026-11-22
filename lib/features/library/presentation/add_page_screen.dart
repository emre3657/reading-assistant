import 'package:material_ui/material_ui.dart';

import '../../image_import/presentation/image_import_screen.dart';
import '../../image_import/services/image_picker_service.dart';
import '../../image_import/services/image_rotation_service.dart';
import '../../image_import/services/text_recognition_service.dart';
import '../../listening/services/speech_service.dart';
import '../../listening/presentation/reading_preferences.dart';
import '../data/document_store.dart';

/// Reuses the import/editor UI and saves directly into the existing content.
class AddPageScreen extends StatelessWidget {
  const AddPageScreen({
    super.key,
    required this.documentId,
    required this.documentTitle,
    this.store,
    this.speechService,
    this.pickerService = const ImagePickerService(),
    this.textRecognitionService = const TextRecognitionService(),
    this.rotationService = const ImageRotationService(),
    this.previewImageBuilder = fileImageProvider,
  });

  final int documentId;
  final String documentTitle;
  final DocumentStore? store;
  final SpeechService? speechService;
  final ImagePickerService pickerService;
  final TextRecognitionService textRecognitionService;
  final ImageRotationService rotationService;
  final PreviewImageBuilder previewImageBuilder;

  @override
  Widget build(BuildContext context) {
    final resolvedStore =
        store ??
        ReadingPreferencesScope.maybeOf(context)?.store ??
        DocumentStore.instance;
    return ImageImportScreen(
      pickerService: pickerService,
      textRecognitionService: textRecognitionService,
      rotationService: rotationService,
      previewImageBuilder: previewImageBuilder,
      speechService: speechService,
      pageDocumentTitle: documentTitle,
      store: resolvedStore,
      onSavePages: (texts) =>
          resolvedStore.appendPages(documentId: documentId, texts: texts),
      onSavePage: (text) async {
        await resolvedStore.appendPage(documentId: documentId, text: text);
      },
    );
  }
}

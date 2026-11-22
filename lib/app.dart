import 'package:flutter/material.dart';

import 'features/image_import/presentation/image_import_screen.dart';
import 'features/image_import/services/image_picker_service.dart';
import 'features/image_import/services/image_rotation_service.dart';
import 'features/image_import/services/text_recognition_service.dart';
import 'features/library/data/document_store.dart';
import 'features/library/presentation/backup_screen.dart';
import 'features/listening/services/speech_service.dart';
import 'features/listening/presentation/reading_preferences.dart';

class ReadingAssistantApp extends StatefulWidget {
  const ReadingAssistantApp({
    super.key,
    this.pickerService = const ImagePickerService(),
    this.textRecognitionService = const TextRecognitionService(),
    this.rotationService = const ImageRotationService(),
    this.previewImageBuilder = fileImageProvider,
    this.speechService,
    this.readingPreferences,
    this.store,
    this.backupFileService = const BackupFileService(),
  });

  final ImagePickerService pickerService;
  final TextRecognitionService textRecognitionService;
  final ImageRotationService rotationService;
  final PreviewImageBuilder previewImageBuilder;
  final SpeechService? speechService;
  final ReadingPreferences? readingPreferences;
  final DocumentStore? store;
  final BackupFileService backupFileService;

  @override
  State<ReadingAssistantApp> createState() => _ReadingAssistantAppState();
}

class _ReadingAssistantAppState extends State<ReadingAssistantApp> {
  late DocumentStore _store;
  late ReadingPreferences _preferences;
  bool _ownsPreferences = false;

  @override
  void initState() {
    super.initState();
    _configure();
  }

  void _configure() {
    final suppliedPreferences = widget.readingPreferences;
    final suppliedStore = widget.store;
    if (suppliedPreferences != null &&
        suppliedStore != null &&
        !identical(suppliedPreferences.store, suppliedStore)) {
      throw ArgumentError(
        'ReadingPreferences and app must use the same store.',
      );
    }
    _store =
        suppliedStore ?? suppliedPreferences?.store ?? DocumentStore.instance;
    _preferences = suppliedPreferences ?? ReadingPreferences(store: _store);
    _ownsPreferences = suppliedPreferences == null;
  }

  @override
  void didUpdateWidget(ReadingAssistantApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store ||
        oldWidget.readingPreferences != widget.readingPreferences) {
      final oldPreferences = _preferences;
      final owned = _ownsPreferences;
      _configure();
      if (owned && !identical(oldPreferences, _preferences)) {
        oldPreferences.dispose();
      }
    }
  }

  @override
  void dispose() {
    if (_ownsPreferences) _preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReadingPreferencesScope(
      preferences: _preferences,
      child: MaterialApp(
        key: ObjectKey(_preferences),
        title: 'Okuma Asistanı',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: ImageImportScreen(
          pickerService: widget.pickerService,
          textRecognitionService: widget.textRecognitionService,
          rotationService: widget.rotationService,
          previewImageBuilder: widget.previewImageBuilder,
          speechService: widget.speechService,
          store: _store,
          backupFileService: widget.backupFileService,
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'features/image_import/presentation/image_import_screen.dart';
import 'features/image_import/services/image_picker_service.dart';
import 'features/image_import/services/image_rotation_service.dart';
import 'features/image_import/services/text_recognition_service.dart';
import 'features/library/data/document_store.dart';
import 'features/library/presentation/backup_screen.dart';
import 'features/listening/services/speech_service.dart';
import 'features/listening/presentation/reading_preferences.dart';
import 'theme/app_theme.dart';

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
  late bool _ready;
  late ThemeMode _themeMode;
  late AppPalette _palette;

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
    _ready = _preferences.ready;
    _themeMode = _preferences.themeMode;
    _palette = _preferences.themePalette;
    _preferences.addListener(_onPreferencesChanged);
    unawaited(_preferences.load());
  }

  void _onPreferencesChanged() {
    if (_ready == _preferences.ready &&
        _themeMode == _preferences.themeMode &&
        _palette == _preferences.themePalette) {
      return;
    }
    setState(() {
      _ready = _preferences.ready;
      _themeMode = _preferences.themeMode;
      _palette = _preferences.themePalette;
    });
  }

  @override
  void didUpdateWidget(ReadingAssistantApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store ||
        oldWidget.readingPreferences != widget.readingPreferences) {
      final oldPreferences = _preferences;
      final owned = _ownsPreferences;
      oldPreferences.removeListener(_onPreferencesChanged);
      _configure();
      if (owned && !identical(oldPreferences, _preferences)) {
        oldPreferences.dispose();
      }
    }
  }

  @override
  void dispose() {
    _preferences.removeListener(_onPreferencesChanged);
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
        debugShowCheckedModeBanner: false,
        theme: appTheme(_palette, Brightness.light),
        darkTheme: appTheme(_palette, Brightness.dark),
        themeMode: _themeMode,
        home: !_ready
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : ImageImportScreen(
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

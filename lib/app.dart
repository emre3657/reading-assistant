import 'dart:async';

import 'package:flutter/material.dart';

import 'features/image_import/presentation/image_import_screen.dart';
import 'features/image_import/services/image_picker_service.dart';
import 'features/image_import/services/image_rotation_service.dart';
import 'features/image_import/services/text_recognition_service.dart';
import 'features/guide/guide_manager.dart';
import 'features/library/data/document_store.dart';
import 'features/library/presentation/backup_screen.dart';
import 'features/listening/services/speech_service.dart';
import 'features/listening/presentation/reading_preferences.dart';
import 'features/startup/intro_screen.dart';
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
    this.deferStartupFrame = false,
  });

  final ImagePickerService pickerService;
  final TextRecognitionService textRecognitionService;
  final ImageRotationService rotationService;
  final PreviewImageBuilder previewImageBuilder;
  final SpeechService? speechService;
  final ReadingPreferences? readingPreferences;
  final DocumentStore? store;
  final BackupFileService backupFileService;
  final bool deferStartupFrame;

  @override
  State<ReadingAssistantApp> createState() => _ReadingAssistantAppState();
}

class _ReadingAssistantAppState extends State<ReadingAssistantApp> {
  late DocumentStore _store;
  late ReadingPreferences _preferences;
  late GuideManager _guides;
  bool _ownsPreferences = false;
  late bool _ready;
  late ThemeMode _themeMode;
  late AppPalette _palette;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _startupReady = false;
  bool _showIntro = false;
  bool _frameDeferred = false;
  int _startupGeneration = 0;
  String? _startupError;
  int _guideErrorSeen = 0;

  @override
  void initState() {
    super.initState();
    _frameDeferred = widget.deferStartupFrame;
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
    _guides = GuideManager(_store)..addListener(_onGuideChanged);
    _guideErrorSeen = 0;
    _startupReady = false;
    _showIntro = false;
    _startupError = null;
    unawaited(
      _loadStartup(++_startupGeneration, _preferences, _store, _guides),
    );
  }

  Future<void> _loadStartup(
    int generation,
    ReadingPreferences preferences,
    DocumentStore store,
    GuideManager guides,
  ) async {
    final preferencesLoad = preferences.load();
    final guidesLoad = guides.load();
    bool completed;
    try {
      completed = await store.hasCompletedIntro();
    } catch (error, stack) {
      debugPrint('Açılış tercihi okunamadı: $error\n$stack');
      completed = true;
      if (mounted && generation == _startupGeneration) {
        _startupError = 'Açılış tercihi okunamadı. Uygulamayı kullanabilirsin.';
      }
    }
    await preferencesLoad;
    await guidesLoad;
    if (!mounted || generation != _startupGeneration) return;
    setState(() {
      _showIntro = !completed;
      _startupReady = true;
    });
    if (_showIntro &&
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations) {
      _completeIntro();
    }
    _releaseFirstFrame();
    if (!_showIntro) {
      _showStartupError();
      _onGuideChanged();
    }
  }

  void _releaseFirstFrame() {
    if (!_frameDeferred) return;
    _frameDeferred = false;
    WidgetsBinding.instance.allowFirstFrame();
  }

  void _showStartupError() {
    if (_startupError == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _startupError == null) return;
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(_startupError!)),
      );
      _startupError = null;
    });
  }

  void _completeIntro() {
    if (!_showIntro) return;
    final store = _store;
    final generation = _startupGeneration;
    setState(() => _showIntro = false);
    _onGuideChanged();
    unawaited(_saveIntro(store, generation));
  }

  void _onGuideChanged() {
    if (!mounted ||
        !_startupReady ||
        _showIntro ||
        _guideErrorSeen == _guides.errorRevision) {
      return;
    }
    _guideErrorSeen = _guides.errorRevision;
    final message = _guides.error;
    if (message == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    });
  }

  Future<void> _saveIntro(DocumentStore store, int generation) async {
    try {
      await store.completeIntro();
    } catch (error, stack) {
      debugPrint('Açılış tercihi kaydedilemedi: $error\n$stack');
      if (!mounted || generation != _startupGeneration) return;
      _startupError =
          'Açılış tercihi kaydedilemedi. Animasyon yeniden gösterilebilir.';
      _showStartupError();
    }
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
      final oldGuides = _guides;
      oldPreferences.removeListener(_onPreferencesChanged);
      oldGuides.removeListener(_onGuideChanged);
      _configure();
      oldGuides.dispose();
      if (owned && !identical(oldPreferences, _preferences)) {
        oldPreferences.dispose();
      }
    }
  }

  @override
  void dispose() {
    _startupGeneration++;
    _releaseFirstFrame();
    _preferences.removeListener(_onPreferencesChanged);
    _guides.removeListener(_onGuideChanged);
    _guides.dispose();
    if (_ownsPreferences) _preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReadingPreferencesScope(
      preferences: _preferences,
      child: GuideScope(
        manager: _guides,
        child: MaterialApp(
          key: ObjectKey(_preferences),
          title: 'Okuma Asistanı',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: _messengerKey,
          navigatorObservers: [_guides.routes],
          theme: appTheme(_palette, Brightness.light),
          darkTheme: appTheme(_palette, Brightness.dark),
          themeMode: _themeMode,
          home: !_startupReady
              ? const Scaffold(backgroundColor: startupBackground)
              : _showIntro
              ? IntroScreen(onComplete: _completeIntro)
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
      ),
    );
  }
}

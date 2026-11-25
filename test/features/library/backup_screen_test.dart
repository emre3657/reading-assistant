import '../listening/reader_controls_test_utils.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/app.dart';
import 'package:reading_assistant/features/image_import/presentation/image_import_screen.dart';
import 'package:reading_assistant/features/image_import/services/image_picker_service.dart';
import 'package:reading_assistant/features/library/data/backup_data.dart';
import 'package:reading_assistant/features/library/presentation/backup_screen.dart';
import 'package:reading_assistant/features/listening/presentation/reading_preferences.dart';
import 'package:reading_assistant/theme/app_theme.dart';

import '../listening/fake_speech_service.dart';
import '../listening/fake_preferences_store.dart';

final _backup = BackupData.fromTables({
  'categories': [
    {'id': 'note', 'label': 'Not', 'normalized_label': 'not'},
  ],
  'documents': [
    {'id': 1, 'title': 'Örnek', 'category': 'note', 'created_at': 7},
  ],
  'pages': [
    {'id': 2, 'document_id': 1, 'position': 0, 'text': 'Bir. İki.'},
  ],
  'reading_positions': [
    {
      'document_id': 1,
      'page_id': 2,
      'sentence_index': 1,
      'page_text': 'Bir. İki.',
    },
  ],
  'bookmarks': <Map<String, Object?>>[],
  'reading_preferences': [
    {
      'id': 1,
      'speed': 'fast',
      'auto_next_page': 1,
      'follow_sentence': 1,
      'text_size': 'large',
      'text_alignment': 'justify',
      'line_spacing': 'wide',
      'page_view': 'book',
      'page_animation_enabled': 1,
      'page_animation_effect': 'slide',
      'bookmark_shape': 'corner',
      'bookmark_color': 'purple',
      'theme_mode': 'dark',
      'theme_palette': 'green',
    },
  ],
});

class _Store extends FakePreferencesStore {
  int restores = 0;
  Object? error;

  @override
  Future<Map<String, Object?>?> loadReadingPreferences() async => null;
  @override
  Future<BackupData> backupSnapshot() async => _backup;
  @override
  Future<void> restoreBackup(BackupData backup) async {
    if (error != null) throw error!;
    restores++;
  }
}

class _Files extends BackupFileService {
  Uint8List? picked;
  Uint8List? saved;
  String? name;
  int saves = 0;
  Completer<bool>? gate;
  Object? pickError;

  @override
  Future<Uint8List?> pick() async {
    if (pickError != null) throw pickError!;
    return picked;
  }

  @override
  Future<bool> save(Uint8List bytes, String fileName) async {
    saves++;
    saved = bytes;
    name = fileName;
    return await gate?.future ?? true;
  }
}

class _Picker extends ImagePickerService {
  @override
  bool get canRecoverLostImage => false;
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 1000 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finder, findsOneWidget);
}

Future<void> _show(
  WidgetTester tester,
  _Store store,
  _Files files,
  ReadingPreferences preferences,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<bool>(
                builder: (_) => BackupScreen(
                  store: store,
                  preferences: preferences,
                  files: files,
                ),
              ),
            ),
            child: const Text('Aç'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Aç'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('password controls and dialog fit large text in both themes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final (brightness, size) in [
      (Brightness.light, const Size(320, 560)),
      (Brightness.dark, const Size(560, 320)),
    ]) {
      tester.view.physicalSize = size;
      final store = _Store();
      final preferences = ReadingPreferences(store: store);
      final files = _Files()
        ..picked = Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'format': 'reading-assistant-encrypted',
              'version': 1,
              'cipher': 'AES-256-GCM',
              'kdf': 'PBKDF2-HMAC-SHA256',
              'iterations': 600000,
              'salt': 'AAECAwQFBgcICQoLDA0ODw==',
              'nonce': 'AAECAwQFBgcICQoL',
              'ciphertext': 'bR+3GObSQ4AO5JPyovcMYg==',
              'tag': '2quc6A+0MzYz/QSLumh40g==',
            }),
          ),
        );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: BackupScreen(
            store: store,
            preferences: preferences,
            files: files,
          ),
        ),
      );
      await tester.tap(find.text('Yedeği parolayla şifrele'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('backup-password-repeat')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Yedekten geri yükle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yedekten geri yükle'));
      await _waitFor(tester, find.byKey(const ValueKey('restore-password')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Yedeği aç'), findsOneWidget);
      expect(find.text('Vazgeç'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('restore-password')), findsNothing);
      expect(store.restores, 0);
      await tester.pumpWidget(const SizedBox());
      preferences.dispose();
    }
  });

  testWidgets('password requirements, encrypted export and restore', (
    tester,
  ) async {
    final store = _Store();
    final files = _Files();
    final preferences = ReadingPreferences(store: store);
    await _show(tester, store, files, preferences);
    await tester.tap(find.text('Yedeği parolayla şifrele'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Bu parola yalnızca bu yedek dosyasını açmak için kullanılır. Parolanı unutursan bu dosyadaki verileri geri yükleyemezsin. Parola sıfırlama veya kurtarma seçeneği yoktur.',
      ),
      findsOneWidget,
    );
    final pass = find.byKey(const ValueKey('backup-password'));
    final repeat = find.byKey(const ValueKey('backup-password-repeat'));
    final create = find.widgetWithText(FilledButton, 'Yedek oluştur');
    bool enabled() => tester.widget<FilledButton>(create).onPressed != null;
    await tester.enterText(pass, '            ');
    await tester.enterText(repeat, '            ');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(enabled(), isFalse);
    await tester.enterText(pass, 'kısa');
    await tester.enterText(repeat, 'kısa');
    await tester.pump();
    expect(enabled(), isFalse);
    const password = '  Türkçe şifre 123  ';
    await tester.enterText(pass, password);
    await tester.enterText(repeat, 'yanlış parola');
    await tester.pump();
    expect(find.text('Parolalar eşleşmiyor.'), findsOneWidget);
    expect(enabled(), isFalse);
    await tester.enterText(repeat, password);
    await tester.pump();
    expect(enabled(), isTrue);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(enabled(), isFalse);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.byTooltip('Parolayı göster'));
    await tester.tap(find.byTooltip('Parolayı göster'));
    await tester.pump();
    expect(tester.widget<TextField>(pass).obscureText, isFalse);
    await tester.ensureVisible(find.byTooltip('Tekrar parolasını göster'));
    await tester.tap(find.byTooltip('Tekrar parolasını göster'));
    await tester.pump();
    expect(tester.widget<TextField>(repeat).obscureText, isFalse);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.ensureVisible(create);
    await tester.tap(create);
    await _waitFor(tester, find.text('Yedek oluşturuldu.'));
    expect(files.saves, 1);
    expect(String.fromCharCodes(files.saved!), isNot(contains('Bir. İki.')));
    expect(tester.widget<TextField>(pass).controller!.text, isEmpty);

    files.picked = files.saved;
    Future<void> startRestore() async {
      ScaffoldMessenger.of(tester.element(find.byType(BackupScreen)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Yedekten geri yükle'));
      await tester.tap(find.text('Yedekten geri yükle'));
      await _waitFor(tester, find.byKey(const ValueKey('restore-password')));
    }

    await startRestore();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(store.restores, 0);
    await startRestore();
    await tester.enterText(
      find.byKey(const ValueKey('restore-password')),
      'yanlış parola',
    );
    await tester.tap(find.text('Yedeği aç'));
    await _waitFor(
      tester,
      find.text('Parola yanlış veya yedek dosyası bozulmuş.'),
    );
    expect(store.restores, 0);
    await startRestore();
    await tester.enterText(
      find.byKey(const ValueKey('restore-password')),
      password,
    );
    await tester.tap(find.text('Yedeği aç'));
    await _waitFor(tester, find.text('Yedek geri yüklensin mi?'));
    expect(store.restores, 0);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(store.restores, 0);
    await startRestore();
    await tester.enterText(
      find.byKey(const ValueKey('restore-password')),
      password,
    );
    await tester.tap(find.text('Yedeği aç'));
    await _waitFor(tester, find.text('Yedek geri yüklensin mi?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Geri yükle'));
    await tester.pumpAndSettle();
    expect(store.restores, 1);
    expect(preferences.themeMode, ThemeMode.dark);
  });

  testWidgets('restoring a backup updates the running app theme', (
    tester,
  ) async {
    final store = _Store();
    final files = _Files()..picked = _backup.encode();
    await tester.pumpWidget(
      ReadingAssistantApp(
        store: store,
        pickerService: _Picker(),
        backupFileService: files,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Diğer seçenekler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yedekle ve geri yükle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yedekten geri yükle'));
    await _waitFor(tester, find.text('Yedek geri yüklensin mi?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Geri yükle'));
    await tester.pumpAndSettle();
    expect(store.restores, 1);
    final context = tester.element(find.byType(ImageImportScreen));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(
      Theme.of(context).colorScheme.primary,
      appTheme(AppPalette.green, Brightness.dark).colorScheme.primary,
    );
  });

  testWidgets(
    'cleanup failure is reported rather than treated as cancellation',
    (tester) async {
      final store = _Store();
      final files = _Files()..pickError = const BackupCleanupException();
      await _show(tester, store, files, ReadingPreferences(store: store));
      await tester.tap(find.text('Yedekten geri yükle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.restores, 0);
      expect(
        find.text(
          'Geçici yedek dosyaları temizlenemedi. Mevcut verilerin korundu.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('unreadable selected file reports an error without restoring', (
    tester,
  ) async {
    final store = _Store();
    final files = _Files()..pickError = StateError('missing file');
    await _show(tester, store, files, ReadingPreferences(store: store));
    await tester.tap(find.text('Yedekten geri yükle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.restores, 0);
    expect(
      find.text('Yedek geri yüklenemedi. Mevcut verilerin korundu.'),
      findsOneWidget,
    );
  });

  testWidgets('save picker cancellation does not report an error or success', (
    tester,
  ) async {
    final store = _Store();
    final files = _Files()..gate = (Completer<bool>()..complete(false));
    await _show(tester, store, files, ReadingPreferences(store: store));
    await tester.tap(find.text('Yedek oluştur'));
    await _waitFor(tester, find.text('Yedek oluştur'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(files.saves, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('failed restore preserves preferences and offers retry', (
    tester,
  ) async {
    final store = _Store()..error = StateError('disk');
    final files = _Files()..picked = _backup.encode();
    final preferences = ReadingPreferences(store: store);
    await _show(tester, store, files, preferences);
    await tester.tap(find.text('Yedekten geri yükle'));
    await _waitFor(tester, find.text('Yedek geri yüklensin mi?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Geri yükle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(
      find.text('Yedek geri yüklenemedi. Mevcut verilerin korundu.'),
      findsOneWidget,
    );
    expect(store.restores, 0);
    expect(preferences.textAlignment, ReadingTextAlignment.start);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Yedekten geri yükle'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('restore confirmation fits a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = _Store();
    final files = _Files()..picked = _backup.encode();
    await _show(tester, store, files, ReadingPreferences(store: store));
    final restoreButton = find.widgetWithText(
      OutlinedButton,
      'Yedekten geri yükle',
    );
    await tester.ensureVisible(restoreButton);
    await tester.pumpAndSettle();
    await tester.tap(restoreButton);
    await _waitFor(tester, find.text('Yedek geri yüklensin mi?'));
    expect(tester.takeException(), isNull);
    expect(
      find.widgetWithText(FilledButton, 'Geri yükle').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Vazgeç').hitTestable(), findsOneWidget);
  });

  testWidgets('save blocks repeat actions and back until completed', (
    tester,
  ) async {
    final store = _Store();
    final files = _Files()..gate = Completer<bool>();
    final preferences = ReadingPreferences(store: store);
    await _show(tester, store, files, preferences);
    await tester.tap(find.text('Yedek oluştur'));
    await _waitFor(tester, find.text('Yedek kaydediliyor…'));
    expect(files.saves, 1);
    expect(BackupData.decode(files.saved!).documentCount, 1);
    expect(
      files.name,
      matches(RegExp(r'^okuma-asistani-\d{4}-\d{2}-\d{2}-\d{6}\.json$')),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Yedek oluştur'),
          )
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(BackupScreen), findsOneWidget);
    files.gate!.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Yedek oluşturuldu.'), findsOneWidget);
  });

  testWidgets(
    'cancel and invalid input preserve state; confirmation applies preferences',
    (tester) async {
      final store = _Store();
      final files = _Files();
      final preferences = ReadingPreferences(store: store);
      await _show(tester, store, files, preferences);
      await tester.tap(find.text('Yedekten geri yükle'));
      await tester.pumpAndSettle();
      expect(store.restores, 0);
      expect(find.byType(SnackBar), findsNothing);
      files.picked = Uint8List.fromList([0xff]);
      await tester.tap(find.text('Yedekten geri yükle'));
      await _waitFor(
        tester,
        find.text('Yedek bozuk, eksik veya desteklenmeyen sürümde.'),
      );
      expect(store.restores, 0);
      files.picked = _backup.encode();
      await tester.tap(find.text('Yedekten geri yükle'));
      await _waitFor(tester, find.text('Yedek geri yüklensin mi?'));
      expect(find.textContaining('1 içerik, 1 sayfa.'), findsOneWidget);
      expect(
        find.textContaining(
          'Mevcut kayıtların ve ayarların bu yedekle değiştirilecek.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(store.restores, 0);
      await tester.tap(find.text('Yedekten geri yükle'));
      await _waitFor(tester, find.text('Yedek geri yüklensin mi?'));
      await tester.tap(find.widgetWithText(FilledButton, 'Geri yükle'));
      await tester.pumpAndSettle();
      expect(store.restores, 1);
      expect(preferences.textAlignment, ReadingTextAlignment.justify);
      expect(preferences.lineSpacing, ReadingLineSpacing.wide);
      expect(preferences.pageView, ReadingPageView.book);
      expect(preferences.pageAnimationEnabled, isTrue);
      expect(preferences.pageAnimationEffect, PageAnimationEffect.slide);
      expect(preferences.bookmarkShape, BookmarkShape.corner);
      expect(preferences.bookmarkColor, BookmarkColor.purple);
      expect(preferences.themeMode, ThemeMode.dark);
      expect(preferences.themePalette, AppPalette.green);
      expect(find.byType(BackupScreen), findsNothing);
    },
  );

  testWidgets('root entry stops speech before opening backup', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _Store();
    final speech = FakeSpeechService();
    final preferences = ReadingPreferences(store: store);
    await tester.pumpWidget(
      ReadingPreferencesScope(
        preferences: preferences,
        child: MaterialApp(
          home: ImageImportScreen(
            pickerService: _Picker(),
            store: store,
            speechService: speech,
            backupFileService: _Files(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Metin yaz veya yapıştır'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('import-text')),
      'Bir cümle.',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tapReadingControl(tester, 'Sesli oku');
    await tester.pumpAndSettle();
    expect(speech.isSpeaking, isTrue);
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byTooltip('Diğer seçenekler'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yedekle ve geri yükle'));
    await tester.pumpAndSettle();
    expect(speech.isSpeaking, isFalse);
    expect(speech.stopCalls, greaterThan(0));
    expect(find.byType(BackupScreen), findsOneWidget);
  });
}

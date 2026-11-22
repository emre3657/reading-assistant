import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../../listening/presentation/reading_preferences.dart';
import '../data/backup_data.dart';
import '../data/document_store.dart';
import '../data/encrypted_backup.dart';

class BackupCleanupException implements Exception {
  const BackupCleanupException();
}

@visibleForTesting
Future<void> verifyPickerCleanup(Directory temp, String pickerDirectory) async {
  final directory = Directory(
    '${temp.path}${Platform.pathSeparator}$pickerDirectory',
  );
  if (await directory.exists() &&
      !await directory.list(followLinks: false).isEmpty) {
    throw const BackupCleanupException();
  }
}

class BackupFileService {
  const BackupFileService();

  Future<void> _cleanup() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await FilePicker.clearTemporaryFiles();
      final temp = Platform.isAndroid
          ? await getTemporaryDirectory()
          : Directory.systemTemp;
      // These are file_picker 13.4's app-owned cache directories.
      await verifyPickerCleanup(
        temp,
        Platform.isAndroid ? 'file_picker' : 'flutter_file_picker',
      );
    } catch (_) {
      throw const BackupCleanupException();
    }
  }

  Future<bool> save(Uint8List bytes, String name) async {
    try {
      return await FilePicker.saveFile(
            fileName: name,
            bytes: bytes,
            mimeType: 'application/json',
            dialogTitle: 'Yedeği kaydet',
          ) !=
          null;
    } finally {
      await _cleanup();
    }
  }

  Future<Uint8List?> pick() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Yedek dosyasını seç',
      );
      return await file?.readAsBytes();
    } finally {
      await _cleanup();
    }
  }
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.store,
    required this.preferences,
    this.files = const BackupFileService(),
  });

  final DocumentStore store;
  final ReadingPreferences preferences;
  final BackupFileService files;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String _status = '';
  bool _encrypt = false;
  bool _understood = false;
  bool _showPassword = false;
  bool _showRepeat = false;
  final _password = TextEditingController();
  final _repeat = TextEditingController();

  bool get _validPassword =>
      _password.text.characters.length >= 12 &&
      _password.text.trim().isNotEmpty &&
      _password.text == _repeat.text &&
      _understood;

  @override
  void dispose() {
    _password.clear();
    _repeat.clear();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _create() async {
    if (_busy || (_encrypt && !_validPassword)) return;
    final encrypt = _encrypt;
    String? password = encrypt ? _password.text : null;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _status = 'Yedek hazırlanıyor…';
    });
    try {
      await widget.preferences.load();
      await widget.preferences.pendingWrites;
      final backup = await widget.store.backupSnapshot();
      final plaintext = await Isolate.run(backup.encode);
      Uint8List bytes;
      if (encrypt) {
        try {
          bytes = await encryptBackup(plaintext, password!);
        } finally {
          plaintext.fillRange(0, plaintext.length, 0);
          password = null;
          if (mounted) {
            _password.clear();
            _repeat.clear();
            _understood = false;
            _showPassword = false;
            _showRepeat = false;
          }
        }
      } else {
        bytes = plaintext;
      }
      if (!mounted) return;
      setState(() => _status = 'Yedek kaydediliyor…');
      final now = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');
      final name =
          'okuma-asistani-${now.year}-${two(now.month)}-${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
      final saved = await widget.files.save(bytes, name);
      if (mounted && saved) _message('Yedek oluşturuldu.');
    } on BackupCleanupException {
      if (mounted) {
        _message(
          'Geçici yedek dosyaları temizlenemedi. Yedek kaydedilmiş olabilir.',
        );
      }
    } catch (_) {
      if (mounted) _message('Yedek oluşturulamadı. Tekrar deneyebilirsin.');
    } finally {
      if (mounted) {
        if (encrypt) {
          _password.clear();
          _repeat.clear();
          _understood = false;
          _showPassword = false;
          _showRepeat = false;
        }
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    var committed = false;
    setState(() {
      _busy = true;
      _status = 'Yedek dosyası seçiliyor…';
    });
    try {
      final bytes = await widget.files.pick();
      if (!mounted || bytes == null) return;
      setState(() => _status = 'Yedek doğrulanıyor…');
      final encrypted = await inspectEncryptedBackup(bytes);
      if (!mounted) return;
      BackupData backup;
      if (encrypted != null) {
        final password = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _RestorePasswordDialog(),
        );
        if (!mounted || password == null) return;
        setState(() => _status = 'Yedek çözülüyor…');
        final plaintext = await decryptBackup(encrypted, password);
        try {
          backup = await decodeBackup(plaintext);
        } finally {
          plaintext.fillRange(0, plaintext.length, 0);
        }
      } else {
        backup = await decodeBackup(bytes);
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Yedek geri yüklensin mi?'),
          content: Text(
            '${backup.documentCount} içerik, ${backup.pageCount} sayfa.\n\n'
            'Mevcut kayıtların ve ayarların bu yedekle değiştirilecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Geri yükle'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      setState(() => _status = 'Yedek geri yükleniyor…');
      await widget.preferences.load();
      await widget.preferences.pendingWrites;
      await widget.store.restoreBackup(backup);
      committed = true;
      widget.preferences.applyRestored(
        backup.tables['reading_preferences']!.firstOrNull,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on BackupAuthenticationException {
      if (mounted) _message('Parola yanlış veya yedek dosyası bozulmuş.');
    } on BackupCleanupException {
      if (mounted) {
        _message(
          'Geçici yedek dosyaları temizlenemedi. Mevcut verilerin korundu.',
        );
      }
    } on FormatException {
      if (mounted) _message('Yedek bozuk, eksik veya desteklenmeyen sürümde.');
    } catch (_) {
      if (mounted) {
        _message(
          committed
              ? 'Yedek geri yüklendi ancak ekran güncellenemedi. Uygulamayı yeniden aç.'
              : 'Yedek geri yüklenemedi. Mevcut verilerin korundu.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Yedekle ve geri yükle')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Yedek, kayıtlarını ve genel ayarlarını içerir.'),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Yedeği parolayla şifrele'),
                value: _encrypt,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _encrypt = value;
                        if (!value) {
                          _password.clear();
                          _repeat.clear();
                          _understood = false;
                          _showPassword = false;
                          _showRepeat = false;
                        }
                      }),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.info_outline,
                        size: 22,
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _encrypt
                            ? 'Bu parola yalnızca bu yedek dosyasını açmak için kullanılır. Parolanı unutursan bu dosyadaki verileri geri yükleyemezsin. Parola sıfırlama veya kurtarma seçeneği yoktur.'
                            : 'Yedek dosyası şifrelenmez. Dosyaya erişen kişiler '
                                  'içindeki metinleri okuyabilir.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_encrypt) ...[
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('backup-password'),
                  controller: _password,
                  enabled: !_busy,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Parola',
                    helperText: 'En az 12 karakter',
                    suffixIcon: IconButton(
                      tooltip: _showPassword
                          ? 'Parolayı gizle'
                          : 'Parolayı göster',
                      onPressed: _busy
                          ? null
                          : () =>
                                setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('backup-password-repeat'),
                  controller: _repeat,
                  enabled: !_busy,
                  obscureText: !_showRepeat,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Parolayı tekrar gir',
                    errorText:
                        _repeat.text.isNotEmpty &&
                            _repeat.text != _password.text
                        ? 'Parolalar eşleşmiyor.'
                        : null,
                    suffixIcon: IconButton(
                      tooltip: _showRepeat
                          ? 'Tekrar parolasını gizle'
                          : 'Tekrar parolasını göster',
                      onPressed: _busy
                          ? null
                          : () => setState(() => _showRepeat = !_showRepeat),
                      icon: Icon(
                        _showRepeat ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                ),
                CheckboxListTile(
                  value: _understood,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _understood = value == true),
                  title: const Text(
                    'Parolamı unutursam bu yedeği açamayacağımı anladım.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy || (_encrypt && !_validPassword)
                    ? null
                    : _create,
                icon: const Icon(Icons.save_alt),
                label: const Text('Yedek oluştur'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.restore),
                label: const Text('Yedekten geri yükle'),
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(_status, semanticsLabel: _status),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _RestorePasswordDialog extends StatefulWidget {
  const _RestorePasswordDialog();

  @override
  State<_RestorePasswordDialog> createState() => _RestorePasswordDialogState();
}

class _RestorePasswordDialogState extends State<_RestorePasswordDialog> {
  final _password = TextEditingController();
  bool _visible = false;

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Yedek parolası'),
    content: TextField(
      key: const ValueKey('restore-password'),
      controller: _password,
      obscureText: !_visible,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      decoration: InputDecoration(
        labelText: 'Parola',
        suffixIcon: IconButton(
          tooltip: _visible ? 'Parolayı gizle' : 'Parolayı göster',
          onPressed: () => setState(() => _visible = !_visible),
          icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _password.text),
        child: const Text('Yedeği aç'),
      ),
    ],
  );
}

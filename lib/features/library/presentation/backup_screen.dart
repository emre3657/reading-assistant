import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../listening/presentation/reading_preferences.dart';
import '../data/backup_data.dart';
import '../data/document_store.dart';

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

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Yedek hazırlanıyor…';
    });
    try {
      await widget.preferences.load();
      await widget.preferences.pendingWrites;
      final backup = await widget.store.backupSnapshot();
      final bytes = await Isolate.run(backup.encode);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    var committed = false;
    setState(() {
      _busy = true;
      _status = 'Yedek dosyası seçiliyor…';
    });
    try {
      final bytes = await widget.files.pick();
      if (!mounted || bytes == null) return;
      setState(() => _status = 'Yedek doğrulanıyor…');
      final backup = await decodeBackup(bytes);
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
                        'Yedek dosyası şifrelenmez. Dosyaya erişen kişiler '
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
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _create,
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

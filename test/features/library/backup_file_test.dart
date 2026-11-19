import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/presentation/backup_screen.dart';

void main() {
  test(
    'picker cleanup detects remaining files without touching unrelated data',
    () async {
      final temp = await Directory.systemTemp.createTemp('backup-cleanup-');
      final picker = Directory(
        '${temp.path}${Platform.pathSeparator}file_picker',
      );
      final leftover = File(
        '${picker.path}${Platform.pathSeparator}backup.json',
      );
      final unrelated = File('${temp.path}${Platform.pathSeparator}other.txt');
      try {
        await picker.create();
        await leftover.writeAsString('backup');
        await unrelated.writeAsString('keep');
        await expectLater(
          verifyPickerCleanup(temp, 'file_picker'),
          throwsA(isA<BackupCleanupException>()),
        );
        expect(await unrelated.readAsString(), 'keep');
        await leftover.delete();
        await verifyPickerCleanup(temp, 'file_picker');
      } finally {
        if (await leftover.exists()) await leftover.delete();
        if (await picker.exists()) await picker.delete();
        if (await unrelated.exists()) await unrelated.delete();
        await temp.delete();
      }
    },
  );
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/library/data/encrypted_backup.dart';

Uint8List _encode(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

void main() {
  test('decrypts an independent PBKDF2/AES-GCM test vector', () async {
    final envelope = (await inspectEncryptedBackup(
      _encode({
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
    ))!;
    expect(
      utf8.decode(await decryptBackup(envelope, '  Türkçe şifre 123  ')),
      'Merhaba, dünya!',
    );
  });

  test('encrypted backups use random salt and nonce, authenticate and preserve passwords', () async {
    const password = '  Türkçe şifre 123  ';
    const text = '{"text":"Gizli belge içeriği"}';
    final clear = Uint8List.fromList(utf8.encode(text));
    final first = await encryptBackup(clear, password);
    final second = await encryptBackup(clear, password);
    final firstJson = jsonDecode(utf8.decode(first)) as Map<String, dynamic>;
    final secondJson = jsonDecode(utf8.decode(second)) as Map<String, dynamic>;
    expect(firstJson['salt'], isNot(secondJson['salt']));
    expect(firstJson['nonce'], isNot(secondJson['nonce']));
    expect(utf8.decode(first), isNot(contains('Gizli belge')));
    final envelope = (await inspectEncryptedBackup(first))!;
    expect(utf8.decode(await decryptBackup(envelope, password)), text);
    await expectLater(
      decryptBackup(envelope, password.trim()),
      throwsA(isA<BackupAuthenticationException>()),
    );
    for (final field in ['ciphertext', 'salt', 'nonce', 'tag']) {
      final altered = Map<String, dynamic>.from(firstJson);
      final bytes = base64Decode(altered[field] as String);
      bytes[0] ^= 1;
      altered[field] = base64Encode(bytes);
      await expectLater(
        decryptBackup(
          (await inspectEncryptedBackup(_encode(altered)))!,
          password,
        ),
        throwsA(isA<BackupAuthenticationException>()),
      );
    }
  });

  test(
    'rejects invalid metadata and truncated envelopes before key derivation',
    () async {
      final encoded = await encryptBackup(
        Uint8List.fromList([1, 2, 3]),
        'örnek parola 123',
      );
      final json = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
      for (final (field, value) in [
        ('version', 2),
        ('cipher', 'other'),
        ('kdf', 'other'),
        ('iterations', 999999999),
        ('iterations', -1),
        ('salt', base64Encode([1])),
        ('nonce', base64Encode([1])),
        ('tag', base64Encode([1])),
        ('ciphertext', ''),
      ]) {
        final invalid = Map<String, dynamic>.from(json)..[field] = value;
        await expectLater(
          inspectEncryptedBackup(_encode(invalid)),
          throwsFormatException,
        );
      }
      await expectLater(
        inspectEncryptedBackup(
          Uint8List.sublistView(encoded, 0, encoded.length - 4),
        ),
        throwsFormatException,
      );
      expect(
        await inspectEncryptedBackup(_encode({'format': 'reading-assistant'})),
        isNull,
      );
    },
  );
}

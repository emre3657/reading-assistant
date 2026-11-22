import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

const encryptedBackupFormat = 'reading-assistant-encrypted';
const encryptedBackupVersion = 1;
const backupKdfIterations = 600000;
const _cipher = 'AES-256-GCM';
const _kdf = 'PBKDF2-HMAC-SHA256';

class EncryptedBackup {
  const EncryptedBackup._(this.salt, this.nonce, this.ciphertext, this.tag);

  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List tag;
}

class BackupAuthenticationException implements Exception {
  const BackupAuthenticationException();
}

Map<String, Object> _header(List<int> salt, List<int> nonce) => {
  'format': encryptedBackupFormat,
  'version': encryptedBackupVersion,
  'cipher': _cipher,
  'kdf': _kdf,
  'iterations': backupKdfIterations,
  'salt': base64Encode(salt),
  'nonce': base64Encode(nonce),
};

Future<SecretKey> _derive(String password, List<int> salt) async {
  final passwordBytes = Uint8List.fromList(utf8.encode(password));
  final passwordKey = SecretKeyData(
    passwordBytes,
    overwriteWhenDestroyed: true,
  );
  try {
    final derived = await DartPbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: backupKdfIterations,
      bits: 256,
      pausePeriod: Duration.zero,
    ).deriveKey(secretKey: passwordKey, nonce: salt);
    try {
      return SecretKeyData(
        Uint8List.fromList(await derived.extractBytes()),
        overwriteWhenDestroyed: true,
      );
    } finally {
      derived.destroy();
    }
  } finally {
    passwordKey.destroy();
  }
}

Future<Uint8List> encryptBackup(Uint8List plaintext, String password) =>
    Isolate.run(() => _encrypt(plaintext, password));

Future<Uint8List> _encrypt(Uint8List plaintext, String password) async {
  final random = Random.secure();
  final salt = Uint8List.fromList(
    List.generate(16, (_) => random.nextInt(256)),
  );
  final nonce = Uint8List.fromList(
    List.generate(12, (_) => random.nextInt(256)),
  );
  final header = _header(salt, nonce);
  SecretKey? key;
  try {
    key = await _derive(password, salt);
    final box = await DartAesGcm.with256bits().encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(jsonEncode(header)),
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          ...header,
          'ciphertext': base64Encode(box.cipherText),
          'tag': base64Encode(box.mac.bytes),
        }),
      ),
    );
  } finally {
    key?.destroy();
    plaintext.fillRange(0, plaintext.length, 0);
  }
}

Future<EncryptedBackup?> inspectEncryptedBackup(Uint8List bytes) =>
    Isolate.run(() => _inspect(bytes));

EncryptedBackup? _inspect(Uint8List bytes) {
  final Object? decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map || decoded['format'] != encryptedBackupFormat) {
    return null;
  }
  const keys = {
    'format',
    'version',
    'cipher',
    'kdf',
    'iterations',
    'salt',
    'nonce',
    'ciphertext',
    'tag',
  };
  if (decoded.length != keys.length ||
      !keys.every(decoded.containsKey) ||
      decoded['version'] is! int ||
      decoded['version'] != encryptedBackupVersion ||
      decoded['cipher'] != _cipher ||
      decoded['kdf'] != _kdf ||
      decoded['iterations'] is! int ||
      decoded['iterations'] != backupKdfIterations) {
    throw const FormatException('Unsupported encrypted backup.');
  }
  Uint8List field(String name, {int? length}) {
    final value = decoded[name];
    if (value is! String ||
        (length != null && value.length != 4 * ((length + 2) ~/ 3))) {
      throw const FormatException('Invalid encrypted backup field.');
    }
    final result = base64Decode(value);
    if ((length != null && result.length != length) ||
        base64Encode(result) != value ||
        result.isEmpty) {
      throw const FormatException('Invalid encrypted backup field.');
    }
    return result;
  }

  return EncryptedBackup._(
    field('salt', length: 16),
    field('nonce', length: 12),
    field('ciphertext'),
    field('tag', length: 16),
  );
}

Future<Uint8List> decryptBackup(EncryptedBackup backup, String password) =>
    Isolate.run(() => _decrypt(backup, password));

Future<Uint8List> _decrypt(EncryptedBackup backup, String password) async {
  final key = await _derive(password, backup.salt);
  try {
    final plaintext = await DartAesGcm.with256bits().decrypt(
      SecretBox(backup.ciphertext, nonce: backup.nonce, mac: Mac(backup.tag)),
      secretKey: key,
      aad: utf8.encode(jsonEncode(_header(backup.salt, backup.nonce))),
    );
    try {
      return Uint8List.fromList(plaintext);
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  } on SecretBoxAuthenticationError {
    throw const BackupAuthenticationException();
  } finally {
    key.destroy();
  }
}

/// Cryptographic and encoding utilities.
///
/// Provides hashing, encoding, UUID generation, obfuscation,
/// simple XOR encryption, and platform keychain access.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/utils/security/neomage_network_guard.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Hashing (pure-Dart cryptographic implementation — zero shell spawning)
// ---------------------------------------------------------------------------

/// Compute SHA-256 hash of [text] using pure-Dart `package:crypto`.
Future<String> sha256(String text) async => sha256Sync(text);

/// Compute SHA-256 synchronously using pure-Dart `package:crypto`.
String sha256Sync(String text) =>
    dart_crypto.sha256.convert(utf8.encode(text)).toString();

/// Compute MD5 hash of [text] using pure-Dart `package:crypto`.
Future<String> md5(String text) async =>
    dart_crypto.md5.convert(utf8.encode(text)).toString();

/// Compute HMAC-SHA256 of [text] with [key] using pure-Dart `package:crypto`
/// (never exposing [key] on OS process command lines).
Future<String> hmacSha256(String key, String text) async {
  final hmac = dart_crypto.Hmac(dart_crypto.sha256, utf8.encode(key));
  return hmac.convert(utf8.encode(text)).toString();
}

// ---------------------------------------------------------------------------
// Base64
// ---------------------------------------------------------------------------

/// Base64-encode a string.
String base64Encode(String text) {
  return base64.encode(utf8.encode(text));
}

/// Base64-decode a string.
String base64Decode(String encoded) {
  return utf8.decode(base64.decode(encoded));
}

/// URL-safe Base64 encode.
String base64UrlEncode(String text) {
  return base64Url.encode(utf8.encode(text));
}

/// URL-safe Base64 decode.
String base64UrlDecode(String encoded) {
  // Pad if necessary
  var padded = encoded;
  final remainder = padded.length % 4;
  if (remainder != 0) {
    padded += '=' * (4 - remainder);
  }
  return utf8.decode(base64Url.decode(padded));
}

// ---------------------------------------------------------------------------
// ID / Token generation
// ---------------------------------------------------------------------------

final _secureRandom = Random.secure();

/// Generate a v4 UUID.
String generateUuid() {
  final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
  // Set version to 4
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  // Set variant to RFC 4122
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}

/// Generate a short alphanumeric ID.
///
/// [prefix] is prepended with an underscore separator.
/// [length] controls the random portion (default 12).
String generateId({String? prefix, int length = 12}) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final buf = StringBuffer();
  for (var i = 0; i < length; i++) {
    buf.write(chars[_secureRandom.nextInt(chars.length)]);
  }
  final id = buf.toString();
  return prefix != null ? '${prefix}_$id' : id;
}

/// Generate a cryptographically random token as a hex string.
String generateToken(int length) {
  final bytes = List<int>.generate(
    (length / 2).ceil(),
    (_) => _secureRandom.nextInt(256),
  );
  return bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .substring(0, length);
}

// ---------------------------------------------------------------------------
// File / directory hashing
// ---------------------------------------------------------------------------

void _validateHashTargetPath(String path) {
  if (path.isEmpty || path.contains('\x00')) {
    throw ArgumentError('Invalid path: empty or contains NUL byte');
  }
  if (path.startsWith('//') || path.startsWith(r'\\')) {
    throw ArgumentError('Invalid path: UNC network paths are disallowed');
  }
  final protectedReason = NeomageNetworkGuard.checkProtectedFilesystemPath(
    path,
  );
  if (protectedReason != null) {
    throw FileSystemException(protectedReason, path);
  }
}

/// Compute SHA-256 hash of a file at [path] using pure-Dart streaming.
Future<String> hashFile(String path) async {
  _validateHashTargetPath(path);
  if (await FileSystemEntity.isLink(path)) {
    throw FileSystemException('Refusing to hash symbolic link', path);
  }
  final file = File(path);
  final digest = await dart_crypto.sha256.bind(file.openRead()).first;
  return digest.toString();
}

/// Compute a combined SHA-256 hash of all regular files in a directory at
/// [path] without following symbolic links or spawning external shells.
///
/// Files are sorted by relative path for deterministic output.
Future<String> hashDirectory(String path) async {
  _validateHashTargetPath(path);
  if (await FileSystemEntity.isLink(path)) {
    throw FileSystemException('Refusing to hash symbolic link directory', path);
  }
  final dir = Directory(path);
  if (!await dir.exists()) {
    throw FileSystemException('Directory does not exist', path);
  }

  final files = <String>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      files.add(entity.path);
    }
    if (files.length > 50000) {
      throw StateError('Directory contains more than 50,000 files');
    }
  }
  files.sort();

  final hashes = <String>[];
  for (final file in files) {
    final rel = p.relative(file, from: path).replaceAll('\\', '/');
    final fileDigest = await hashFile(file);
    hashes.add('$rel:$fileDigest\n');
  }

  return sha256Sync(hashes.join());
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

/// Constant-time string comparison over UTF-8 bytes without length-leak
/// early return.
bool constantTimeEquals(String a, String b) {
  if (a.isEmpty && b.isEmpty) return true;
  return NeomageNetworkGuard.constantTimeEquals(a, b);
}

// ---------------------------------------------------------------------------
// Obfuscation / redaction
// ---------------------------------------------------------------------------

/// Obfuscate [text], showing only the last [visibleChars] characters.
String obfuscate(String text, {int visibleChars = 4}) {
  if (text.length <= visibleChars) return '*' * text.length;
  final hidden = text.length - visibleChars;
  return '${'*' * hidden}${text.substring(hidden)}';
}

/// Redact an API key, showing only the first and last few characters.
String redactApiKey(String key) {
  if (key.length <= 8) return '*' * key.length;
  final showChars = (key.length > 20) ? 4 : 2;
  return '${key.substring(0, showChars)}${'*' * (key.length - showChars * 2)}${key.substring(key.length - showChars)}';
}

// ---------------------------------------------------------------------------
// XOR encryption
// ---------------------------------------------------------------------------

/// Simple XOR encrypt/decrypt for local storage.
///
/// This is NOT cryptographically secure and should only be used for
/// lightweight obfuscation of locally stored data.
class XorCipher {
  const XorCipher._();

  /// Encrypt [plaintext] with [key] using XOR, returning a Base64-encoded string.
  static String encrypt(String plaintext, String key) {
    if (key.isEmpty) throw ArgumentError('Key must not be empty');
    final data = utf8.encode(plaintext);
    final keyBytes = utf8.encode(key);
    final result = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      result[i] = data[i] ^ keyBytes[i % keyBytes.length];
    }
    return base64.encode(result);
  }

  /// Decrypt a Base64-encoded [ciphertext] with [key] using XOR.
  static String decrypt(String ciphertext, String key) {
    if (key.isEmpty) throw ArgumentError('Key must not be empty');
    final data = base64.decode(ciphertext);
    final keyBytes = utf8.encode(key);
    final result = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      result[i] = data[i] ^ keyBytes[i % keyBytes.length];
    }
    return utf8.decode(result);
  }
}

// ---------------------------------------------------------------------------
// SecureStorage
// ---------------------------------------------------------------------------

/// Platform-aware secure storage using system keychains.
///
/// - macOS: uses the `security` command (Keychain Access)
/// - Linux: uses `secret-tool` (GNOME Keyring / libsecret)
class SecureStorage {
  final String serviceName;

  const SecureStorage({this.serviceName = 'neomage'});

  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');

  /// Validates keychain `serviceName` and `key` to prevent option injection
  /// (`-a` / `--label`) and NUL/control-byte corruption.
  static void validateKeychainIdentifier(String value, {String label = 'key'}) {
    if (value.isEmpty || value.length > 256) {
      throw ArgumentError('Invalid $label length');
    }
    if (value.startsWith('-')) {
      throw ArgumentError('Invalid $label: must not start with "-"');
    }
    if (_controlChars.hasMatch(value)) {
      throw ArgumentError('Invalid $label: contains control characters');
    }
  }

  void _validateServiceAndKey(String key) {
    validateKeychainIdentifier(serviceName, label: 'serviceName');
    validateKeychainIdentifier(key, label: 'key');
  }

  /// Store a value in the system keychain.
  Future<bool> write(String key, String value) async {
    _validateServiceAndKey(key);
    if (value.contains('\x00') || value.length > 65536) {
      throw ArgumentError('Invalid secret value');
    }
    final cleanEnv = NeomageNetworkGuard.sanitizeSubprocessEnv(
      Platform.environment,
    );

    if (Platform.isMacOS) {
      final result = await Process.run(
        'security',
        [
          'add-generic-password',
          '-a',
          key,
          '-s',
          serviceName,
          '-w',
          value,
          '-U',
        ],
        environment: cleanEnv,
      ).timeout(const Duration(seconds: 15));
      return result.exitCode == 0;
    } else if (Platform.isLinux) {
      final proc = await Process.start(
        'secret-tool',
        [
          'store',
          '--label=$serviceName:$key',
          '--',
          'service',
          serviceName,
          'account',
          key,
        ],
        environment: cleanEnv,
      );
      proc.stdin.write(value);
      await proc.stdin.close();
      final code = await proc.exitCode.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          proc.kill();
          return -1;
        },
      );
      return code == 0;
    }
    throw UnsupportedError('SecureStorage is not supported on this platform');
  }

  /// Read a value from the system keychain.
  Future<String?> read(String key) async {
    _validateServiceAndKey(key);
    final cleanEnv = NeomageNetworkGuard.sanitizeSubprocessEnv(
      Platform.environment,
    );

    if (Platform.isMacOS) {
      final result = await Process.run(
        'security',
        [
          'find-generic-password',
          '-a',
          key,
          '-s',
          serviceName,
          '-w',
        ],
        stdoutEncoding: utf8,
        environment: cleanEnv,
      ).timeout(const Duration(seconds: 15));
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
      return null;
    } else if (Platform.isLinux) {
      final result = await Process.run(
        'secret-tool',
        [
          'lookup',
          '--',
          'service',
          serviceName,
          'account',
          key,
        ],
        stdoutEncoding: utf8,
        environment: cleanEnv,
      ).timeout(const Duration(seconds: 15));
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
      return null;
    }
    throw UnsupportedError('SecureStorage is not supported on this platform');
  }

  /// Delete a value from the system keychain.
  Future<bool> delete(String key) async {
    _validateServiceAndKey(key);
    final cleanEnv = NeomageNetworkGuard.sanitizeSubprocessEnv(
      Platform.environment,
    );

    if (Platform.isMacOS) {
      final result = await Process.run(
        'security',
        [
          'delete-generic-password',
          '-a',
          key,
          '-s',
          serviceName,
        ],
        environment: cleanEnv,
      ).timeout(const Duration(seconds: 15));
      return result.exitCode == 0;
    } else if (Platform.isLinux) {
      final result = await Process.run(
        'secret-tool',
        [
          'clear',
          '--',
          'service',
          serviceName,
          'account',
          key,
        ],
        environment: cleanEnv,
      ).timeout(const Duration(seconds: 15));
      return result.exitCode == 0;
    }
    throw UnsupportedError('SecureStorage is not supported on this platform');
  }

  /// Check if a key exists in the keychain.
  Future<bool> has(String key) async {
    final value = await read(key);
    return value != null;
  }
}

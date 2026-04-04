/// Cryptographic and encoding utilities.
///
/// Provides hashing, encoding, UUID generation, obfuscation,
/// simple XOR encryption, and platform keychain access.
library;

import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math';
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Hashing (using dart:convert and manual implementations for no-dependency)
// ---------------------------------------------------------------------------

/// Compute SHA-256 hash of [text].
///
/// Uses the `shasum` command on macOS/Linux for simplicity without
/// requiring a crypto package.
Future<String> sha256(String text) async {
  final result = await Process.run('shasum', ['-a', '256'],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      environment: Platform.environment);
  // Fallback: use openssl
  if (result.exitCode != 0) {
    return _hashViaOpenssl('sha256', text);
  }
  // Use printf + shasum via shell
  final proc = await Process.run(
    'sh',
    ['-c', 'printf "%s" \${1} | shasum -a 256', '--', text],
    stdoutEncoding: utf8,
  );
  if (proc.exitCode == 0) {
    return (proc.stdout as String).split(' ').first.trim();
  }
  return _hashViaOpenssl('sha256', text);
}

/// Compute SHA-256 synchronously using Process.runSync.
String sha256Sync(String text) {
  final result = Process.runSync(
    'sh',
    ['-c', 'printf "%s" "\$1" | shasum -a 256', '--', text],
    stdoutEncoding: utf8,
  );
  if (result.exitCode == 0) {
    return (result.stdout as String).split(' ').first.trim();
  }
  // Fallback to openssl
  final r2 = Process.runSync(
    'sh',
    ['-c', 'printf "%s" "\$1" | openssl dgst -sha256 -hex', '--', text],
    stdoutEncoding: utf8,
  );
  final output = (r2.stdout as String).trim();
  // openssl may prefix with "(stdin)= "
  final idx = output.indexOf('= ');
  return idx >= 0 ? output.substring(idx + 2).trim() : output;
}

/// Compute MD5 hash of [text].
Future<String> md5(String text) async {
  // Try md5sum first (Linux), then md5 (macOS)
  for (final cmd in ['md5sum', 'md5']) {
    try {
      final proc = await Process.run(
        'sh',
        ['-c', 'printf "%s" "\$1" | $cmd', '--', text],
        stdoutEncoding: utf8,
      );
      if (proc.exitCode == 0) {
        final out = (proc.stdout as String).trim();
        if (cmd == 'md5sum') return out.split(' ').first;
        // macOS md5 outputs "MD5 (...) = <hash>" or just the hash
        final eqIdx = out.indexOf('= ');
        return eqIdx >= 0 ? out.substring(eqIdx + 2).trim() : out.split(' ').last;
      }
    } catch (_) {}
  }
  return _hashViaOpenssl('md5', text);
}

/// Compute HMAC-SHA256 of [text] with [key].
Future<String> hmacSha256(String key, String text) async {
  final proc = await Process.run(
    'sh',
    ['-c', 'printf "%s" "\$1" | openssl dgst -sha256 -hmac "\$2" -hex', '--', text, key],
    stdoutEncoding: utf8,
  );
  final output = (proc.stdout as String).trim();
  final idx = output.indexOf('= ');
  return idx >= 0 ? output.substring(idx + 2).trim() : output;
}

Future<String> _hashViaOpenssl(String algo, String text) async {
  final proc = await Process.run(
    'sh',
    ['-c', 'printf "%s" "\$1" | openssl dgst -$algo -hex', '--', text],
    stdoutEncoding: utf8,
  );
  final output = (proc.stdout as String).trim();
  final idx = output.indexOf('= ');
  return idx >= 0 ? output.substring(idx + 2).trim() : output;
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

/// Compute SHA-256 hash of a file at [path].
Future<String> hashFile(String path) async {
  final proc = await Process.run('shasum', ['-a', '256', path],
      stdoutEncoding: utf8);
  if (proc.exitCode == 0) {
    return (proc.stdout as String).split(' ').first.trim();
  }
  // Fallback
  final proc2 = await Process.run(
    'openssl', ['dgst', '-sha256', '-hex', path],
    stdoutEncoding: utf8,
  );
  final output = (proc2.stdout as String).trim();
  final idx = output.indexOf('= ');
  return idx >= 0 ? output.substring(idx + 2).trim() : output;
}

/// Compute a combined SHA-256 hash of all files in a directory at [path].
///
/// Files are sorted by path for deterministic output.
Future<String> hashDirectory(String path) async {
  // Find all files, sort, hash each, then hash the combined hashes
  final findResult = await Process.run(
    'find', [path, '-type', 'f'],
    stdoutEncoding: utf8,
  );
  if (findResult.exitCode != 0) {
    throw ProcessException('find', [path], 'Failed to list directory', findResult.exitCode);
  }

  final files = (findResult.stdout as String)
      .split('\n')
      .where((f) => f.isNotEmpty)
      .toList()
    ..sort();

  final hashes = <String>[];
  for (final file in files) {
    hashes.add(await hashFile(file));
  }

  // Hash the concatenated hashes
  final combined = hashes.join();
  return sha256Sync(combined).isNotEmpty
      ? sha256Sync(combined)
      : (await sha256(combined));
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

/// Constant-time string comparison to prevent timing attacks.
bool constantTimeEquals(String a, String b) {
  final aBytes = utf8.encode(a);
  final bBytes = utf8.encode(b);
  if (aBytes.length != bBytes.length) return false;

  var result = 0;
  for (var i = 0; i < aBytes.length; i++) {
    result |= aBytes[i] ^ bBytes[i];
  }
  return result == 0;
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

  const SecureStorage({this.serviceName = 'neom_claw'});

  /// Store a value in the system keychain.
  Future<bool> write(String key, String value) async {
    if (Platform.isMacOS) {
      final result = await Process.run('security', [
        'add-generic-password',
        '-a', key,
        '-s', serviceName,
        '-w', value,
        '-U', // Update if exists
      ]);
      return result.exitCode == 0;
    } else if (Platform.isLinux) {
      final result = await Process.run('secret-tool', [
        'store',
        '--label', '$serviceName:$key',
        'service', serviceName,
        'account', key,
      ], environment: Platform.environment);
      // secret-tool reads the secret from stdin
      if (result.exitCode != 0) {
        // Try with stdin
        final proc = await Process.start('secret-tool', [
          'store',
          '--label', '$serviceName:$key',
          'service', serviceName,
          'account', key,
        ]);
        proc.stdin.writeln(value);
        await proc.stdin.close();
        final code = await proc.exitCode;
        return code == 0;
      }
      return true;
    }
    throw UnsupportedError('SecureStorage is not supported on this platform');
  }

  /// Read a value from the system keychain.
  Future<String?> read(String key) async {
    if (Platform.isMacOS) {
      final result = await Process.run('security', [
        'find-generic-password',
        '-a', key,
        '-s', serviceName,
        '-w',
      ], stdoutEncoding: utf8);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
      return null;
    } else if (Platform.isLinux) {
      final result = await Process.run('secret-tool', [
        'lookup',
        'service', serviceName,
        'account', key,
      ], stdoutEncoding: utf8);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
      return null;
    }
    throw UnsupportedError('SecureStorage is not supported on this platform');
  }

  /// Delete a value from the system keychain.
  Future<bool> delete(String key) async {
    if (Platform.isMacOS) {
      final result = await Process.run('security', [
        'delete-generic-password',
        '-a', key,
        '-s', serviceName,
      ]);
      return result.exitCode == 0;
    } else if (Platform.isLinux) {
      final result = await Process.run('secret-tool', [
        'clear',
        'service', serviceName,
        'account', key,
      ]);
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

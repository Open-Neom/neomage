import 'package:crypto/crypto.dart' show sha256;
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/utils/security/neomage_network_guard.dart';

/// Pure-Dart / `neomage_io` safety guards for the native binary installer.
///
/// Kept free of UI/state-framework imports so PID probing, version-slug
/// validation, and SHA-256 verification can be tested directly on both VM and
/// Chrome Web.
final RegExp _sha256HexPattern = RegExp(r'^[0-9a-fA-F]{64}$');

/// Checks whether a process with [targetPid] is alive WITHOUT sending a fatal
/// signal (`SIGUSR1` terminates processes by default on POSIX!).
///
/// Uses `kill -0` on macOS/Linux and `tasklist` on Windows.
bool checkProcessRunningSafe(int targetPid) {
  if (targetPid <= 1) return false;
  try {
    if (Platform.isWindows) {
      final result = Process.runSync('tasklist', [
        '/FI',
        'PID eq $targetPid',
        '/NH',
      ]);
      if (result.exitCode != 0) return false;
      final out = (result.stdout?.toString() ?? '');
      return out.contains('$targetPid');
    }
    if (Platform.isMacOS || Platform.isLinux) {
      final result = Process.runSync('kill', ['-0', '$targetPid']);
      return result.exitCode == 0;
    }
    return false;
  } catch (_) {
    return false;
  }
}

/// Verifies that [targetPid] belongs to a Neomage executable (mitigating PID
/// reuse), comparing [targetPid] against [currentPid] rather than shadowing
/// `pid`.
bool isExpectedInstallerProcess(
  int targetPid,
  int currentPid,
  String expectedExecPath,
) {
  if (!checkProcessRunningSafe(targetPid)) return false;
  if (targetPid > 1 && targetPid == currentPid) return true;
  if (Platform.isWindows) return true;

  try {
    final result = Process.runSync('ps', ['-p', '$targetPid', '-o', 'command=']);
    if (result.exitCode != 0) return false;
    final command = (result.stdout?.toString() ?? '').toLowerCase().trim();
    if (command.isEmpty) return false;
    final cleanExpected = expectedExecPath.trim().toLowerCase();
    return command.contains('neomage') ||
        (cleanExpected.isNotEmpty && command.contains(cleanExpected));
  } catch (_) {
    return false;
  }
}

/// Normalizes (`v1.2.3` -> `1.2.3`) and validates a semantic version slug,
/// rejecting path traversal (`..`, `/`, `\`), reserved `99.99.*` smoke-test
/// versions, and arbitrary HTML/error payloads returned by upstream repos.
String normalizeAndValidateVersionSlug(String raw) {
  final trimmed = raw.trim();
  final normalized = trimmed.startsWith('v') ? trimmed.substring(1) : trimmed;
  if (!NeomageNetworkGuard.isSafeSemverSlug(normalized)) {
    throw FormatException('Invalid version string: "$raw"');
  }
  if (normalized.startsWith('99.99.')) {
    throw Exception(
      "Version $normalized is not available for installation. Use 'stable' or 'latest'.",
    );
  }
  return normalized;
}

/// Validates that [checksum] is a 64-character hexadecimal SHA-256 digest.
bool isValidSha256Hex(String checksum) =>
    _sha256HexPattern.hasMatch(checksum.trim());

/// Verifies the SHA-256 digest of [bytes] against [expectedHex] in constant
/// time.
bool verifySha256ConstantTime(List<int> bytes, String expectedHex) {
  final cleanExpected = expectedHex.trim().toLowerCase();
  if (!_sha256HexPattern.hasMatch(cleanExpected)) return false;
  final actual = sha256.convert(bytes).toString().toLowerCase();
  return NeomageNetworkGuard.constantTimeEquals(actual, cleanExpected);
}

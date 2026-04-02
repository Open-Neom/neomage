// Binary file detection — ported from OpenClaude src/constants/files.ts.

import 'dart:typed_data';

/// File extensions known to be binary.
const Set<String> binaryExtensions = {
  // Images
  'png', 'jpg', 'jpeg', 'gif', 'bmp', 'ico', 'webp', 'avif', 'tiff', 'tif',
  'svg', 'heic', 'heif', 'raw', 'cr2', 'nef', 'arw', 'dng',
  // Video
  'mp4', 'avi', 'mov', 'wmv', 'flv', 'mkv', 'webm', 'm4v', 'mpg', 'mpeg',
  '3gp', 'ogv',
  // Audio
  'mp3', 'wav', 'ogg', 'flac', 'aac', 'wma', 'm4a', 'opus', 'aiff', 'mid',
  'midi',
  // Archives
  'zip', 'tar', 'gz', 'bz2', 'xz', '7z', 'rar', 'zst', 'lz4', 'lzma',
  'cab', 'iso', 'dmg',
  // Executables / Libraries
  'exe', 'dll', 'so', 'dylib', 'bin', 'app', 'msi', 'deb', 'rpm', 'apk',
  'ipa',
  // Documents (binary)
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp',
  'epub',
  // Fonts
  'ttf', 'otf', 'woff', 'woff2', 'eot',
  // Bytecode / compiled
  'pyc', 'pyo', 'class', 'o', 'obj', 'a', 'lib', 'wasm',
  // Databases
  'db', 'sqlite', 'sqlite3', 'mdb',
  // Design
  'psd', 'ai', 'sketch', 'fig', 'xd',
  // Other
  'dat', 'pak', 'bundle', 'node', 'map',
};

/// Bytes to check for binary content detection.
const int binaryCheckSize = 8192;

/// Check if a file path has a known binary extension.
bool hasBinaryExtension(String filePath) {
  final dot = filePath.lastIndexOf('.');
  if (dot < 0 || dot == filePath.length - 1) return false;
  final ext = filePath.substring(dot + 1).toLowerCase();
  return binaryExtensions.contains(ext);
}

/// Detect binary content by checking for null bytes or >10% non-printable
/// characters in the first [binaryCheckSize] bytes.
bool isBinaryContent(Uint8List buffer) {
  final checkLength =
      buffer.length < binaryCheckSize ? buffer.length : binaryCheckSize;
  if (checkLength == 0) return false;

  int nonPrintable = 0;
  for (int i = 0; i < checkLength; i++) {
    final byte = buffer[i];
    // Null byte → definitely binary
    if (byte == 0) return true;
    // Non-printable: not tab (9), not newline (10), not carriage return (13),
    // and outside printable ASCII range (32-126)
    if (byte != 9 && byte != 10 && byte != 13 && (byte < 32 || byte > 126)) {
      nonPrintable++;
    }
  }

  return nonPrintable / checkLength > 0.1;
}

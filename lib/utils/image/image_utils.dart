/// Image handling utilities: resizing, clipboard, storage, validation.
///
/// Ported from openneomclaw/src/utils/imageResizer.ts (880 LOC),
/// openneomclaw/src/utils/imagePaste.ts (416 LOC),
/// openneomclaw/src/utils/imageStore.ts (167 LOC),
/// openneomclaw/src/utils/imageValidation.ts (104 LOC).
library;

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math';
import 'dart:typed_data';

import 'package:sint/sint.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// API limit for base64-encoded image data.
const int apiImageMaxBase64Size = 5242880; // 5MB

/// Maximum image dimensions.
const int imageMaxWidth = 8000;
const int imageMaxHeight = 8000;

/// Target raw size for images (before base64 encoding).
const int imageTargetRawSize = 3932160; // ~3.75MB

/// Threshold in characters for when to consider text a "large paste".
const int pasteThreshold = 800;

/// Maximum number of stored image paths to cache.
const int _maxStoredImagePaths = 200;

// ---------------------------------------------------------------------------
// Image media types
// ---------------------------------------------------------------------------

/// Supported image media types.
enum ImageMediaType {
  png('image/png'),
  jpeg('image/jpeg'),
  gif('image/gif'),
  webp('image/webp');

  final String value;
  const ImageMediaType(this.value);
}

/// Regex pattern to match supported image file extensions.
final RegExp imageExtensionRegex = RegExp(r'\.(png|jpe?g|gif|webp)$', caseSensitive: false);

// ---------------------------------------------------------------------------
// Error types
// ---------------------------------------------------------------------------

/// Error type constants for analytics.
enum ImageErrorType {
  moduleLoad(1),
  processing(2),
  unknown(3),
  pixelLimit(4),
  memory(5),
  timeout(6),
  vips(7),
  permission(8);

  final int code;
  const ImageErrorType(this.code);
}

/// Error thrown when image resizing fails and the image exceeds the API limit.
class ImageResizeError implements Exception {
  final String message;
  ImageResizeError(this.message);

  @override
  String toString() => 'ImageResizeError: $message';
}

/// Error thrown when one or more images exceed the API size limit.
class ImageSizeError implements Exception {
  final List<OversizedImage> oversizedImages;
  final int maxSize;
  late final String message;

  ImageSizeError(this.oversizedImages, this.maxSize) {
    if (oversizedImages.length == 1) {
      final first = oversizedImages.first;
      message =
          'Image base64 size (${formatFileSize(first.size)}) exceeds API limit '
          '(${formatFileSize(maxSize)}). Please resize the image before sending.';
    } else {
      final details = oversizedImages
          .map((img) => 'Image ${img.index}: ${formatFileSize(img.size)}')
          .join(', ');
      message =
          '${oversizedImages.length} images exceed the API limit '
          '(${formatFileSize(maxSize)}): $details. '
          'Please resize these images before sending.';
    }
  }

  @override
  String toString() => 'ImageSizeError: $message';
}

/// Information about an oversized image.
class OversizedImage {
  final int index;
  final int size;
  const OversizedImage({required this.index, required this.size});
}

// ---------------------------------------------------------------------------
// Image dimensions
// ---------------------------------------------------------------------------

/// Image dimension information.
class ImageDimensions {
  final int? originalWidth;
  final int? originalHeight;
  final int? displayWidth;
  final int? displayHeight;

  const ImageDimensions({
    this.originalWidth,
    this.originalHeight,
    this.displayWidth,
    this.displayHeight,
  });

  Map<String, dynamic> toJson() => {
        if (originalWidth != null) 'originalWidth': originalWidth,
        if (originalHeight != null) 'originalHeight': originalHeight,
        if (displayWidth != null) 'displayWidth': displayWidth,
        if (displayHeight != null) 'displayHeight': displayHeight,
      };
}

/// Result of resizing an image.
class ResizeResult {
  final Uint8List buffer;
  final String mediaType;
  final ImageDimensions? dimensions;

  const ResizeResult({
    required this.buffer,
    required this.mediaType,
    this.dimensions,
  });
}

/// Image with dimensions and base64 data.
class ImageWithDimensions {
  final String base64;
  final String mediaType;
  final ImageDimensions? dimensions;

  const ImageWithDimensions({
    required this.base64,
    required this.mediaType,
    this.dimensions,
  });
}

/// Image block with dimension information.
class ImageBlockWithDimensions {
  final Map<String, dynamic> block;
  final ImageDimensions? dimensions;

  const ImageBlockWithDimensions({required this.block, this.dimensions});
}

/// Compressed image result.
class CompressedImageResult {
  final String base64;
  final String mediaType;
  final int originalSize;

  const CompressedImageResult({
    required this.base64,
    required this.mediaType,
    required this.originalSize,
  });
}

// ---------------------------------------------------------------------------
// Clipboard commands
// ---------------------------------------------------------------------------

/// Platform-specific clipboard commands.
class _ClipboardCommands {
  final String checkImage;
  final String saveImage;
  final String getPath;
  final String deleteFile;

  const _ClipboardCommands({
    required this.checkImage,
    required this.saveImage,
    required this.getPath,
    required this.deleteFile,
  });
}

// ---------------------------------------------------------------------------
// Format detection
// ---------------------------------------------------------------------------

/// Detect image format from a buffer using magic bytes.
ImageMediaType detectImageFormatFromBuffer(Uint8List buffer) {
  if (buffer.length < 4) return ImageMediaType.png;

  // PNG signature
  if (buffer[0] == 0x89 &&
      buffer[1] == 0x50 &&
      buffer[2] == 0x4E &&
      buffer[3] == 0x47) {
    return ImageMediaType.png;
  }

  // JPEG signature (FFD8FF)
  if (buffer[0] == 0xFF && buffer[1] == 0xD8 && buffer[2] == 0xFF) {
    return ImageMediaType.jpeg;
  }

  // GIF signature (GIF87a or GIF89a)
  if (buffer[0] == 0x47 && buffer[1] == 0x49 && buffer[2] == 0x46) {
    return ImageMediaType.gif;
  }

  // WebP signature (RIFF....WEBP)
  if (buffer[0] == 0x52 &&
      buffer[1] == 0x49 &&
      buffer[2] == 0x46 &&
      buffer[3] == 0x46) {
    if (buffer.length >= 12 &&
        buffer[8] == 0x57 &&
        buffer[9] == 0x45 &&
        buffer[10] == 0x42 &&
        buffer[11] == 0x50) {
      return ImageMediaType.webp;
    }
  }

  return ImageMediaType.png;
}

/// Detect image format from base64 data using magic bytes.
ImageMediaType detectImageFormatFromBase64(String base64Data) {
  try {
    final buffer = Uint8List.fromList(base64Decode(base64Data.substring(
      0,
      min(base64Data.length, 64),
    )));
    return detectImageFormatFromBuffer(buffer);
  } catch (_) {
    return ImageMediaType.png;
  }
}

// ---------------------------------------------------------------------------
// Error classification
// ---------------------------------------------------------------------------

/// Classifies image processing errors for analytics.
ImageErrorType classifyImageError(Object error) {
  final message = error.toString().toLowerCase();

  if (message.contains('module not found') ||
      message.contains('dlopen') ||
      message.contains('native image processor module not available')) {
    return ImageErrorType.moduleLoad;
  }
  if (message.contains('unsupported image format') ||
      message.contains('input buffer') ||
      message.contains('corrupt header') ||
      message.contains('corrupt image') ||
      message.contains('premature end') ||
      message.contains('zero width') ||
      message.contains('zero height')) {
    return ImageErrorType.processing;
  }
  if (message.contains('pixel limit') ||
      message.contains('too many pixels') ||
      message.contains('image dimensions')) {
    return ImageErrorType.pixelLimit;
  }
  if (message.contains('out of memory') ||
      message.contains('cannot allocate') ||
      message.contains('memory allocation')) {
    return ImageErrorType.memory;
  }
  if (message.contains('timeout') || message.contains('timed out')) {
    return ImageErrorType.timeout;
  }
  if (message.contains('vips')) {
    return ImageErrorType.vips;
  }
  if (message.contains('permission denied') || message.contains('eacces')) {
    return ImageErrorType.permission;
  }
  return ImageErrorType.unknown;
}

/// Computes a simple numeric hash of a string for analytics grouping.
/// Uses djb2 algorithm, returning a 32-bit unsigned integer.
int hashString(String str) {
  int hash = 5381;
  for (int i = 0; i < str.length; i++) {
    hash = ((hash << 5) + hash + str.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  return hash;
}

// ---------------------------------------------------------------------------
// File size formatting
// ---------------------------------------------------------------------------

/// Format a file size in bytes to a human-readable string.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

// ---------------------------------------------------------------------------
// Image metadata text
// ---------------------------------------------------------------------------

/// Creates a text description of image metadata including dimensions and source path.
String? createImageMetadataText(ImageDimensions dims, {String? sourcePath}) {
  final originalWidth = dims.originalWidth;
  final originalHeight = dims.originalHeight;
  final displayWidth = dims.displayWidth;
  final displayHeight = dims.displayHeight;

  if (originalWidth == null ||
      originalHeight == null ||
      displayWidth == null ||
      displayHeight == null ||
      displayWidth <= 0 ||
      displayHeight <= 0) {
    if (sourcePath != null) return '[Image source: $sourcePath]';
    return null;
  }

  final wasResized =
      originalWidth != displayWidth || originalHeight != displayHeight;
  if (!wasResized && sourcePath == null) return null;

  final parts = <String>[];
  if (sourcePath != null) parts.add('source: $sourcePath');
  if (wasResized) {
    final scaleFactor = originalWidth / displayWidth;
    parts.add(
      'original ${originalWidth}x$originalHeight, displayed at '
      '${displayWidth}x$displayHeight. Multiply coordinates by '
      '${scaleFactor.toStringAsFixed(2)} to map to original image.',
    );
  }

  return '[Image: ${parts.join(', ')}]';
}

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

/// Remove outer single or double quotes from a string.
String _removeOuterQuotes(String text) {
  if ((text.startsWith('"') && text.endsWith('"')) ||
      (text.startsWith("'") && text.endsWith("'"))) {
    return text.substring(1, text.length - 1);
  }
  return text;
}

/// Remove shell escape backslashes from a path.
String _stripBackslashEscapes(String path) {
  if (Platform.isWindows) return path;

  // Temporarily replace double backslashes
  const placeholder = '__DOUBLE_BACKSLASH__';
  final withPlaceholder = path.replaceAll(r'\\', placeholder);
  final withoutEscapes = withPlaceholder.replaceAllMapped(
    RegExp(r'\\(.)'),
    (m) => m.group(1)!,
  );
  return withoutEscapes.replaceAll(placeholder, r'\');
}

/// Check if a given text represents an image file path.
bool isImageFilePath(String text) {
  final cleaned = _removeOuterQuotes(text.trim());
  final unescaped = _stripBackslashEscapes(cleaned);
  return imageExtensionRegex.hasMatch(unescaped);
}

/// Clean and normalize a text string that might be an image file path.
String? asImageFilePath(String text) {
  final cleaned = _removeOuterQuotes(text.trim());
  final unescaped = _stripBackslashEscapes(cleaned);
  if (imageExtensionRegex.hasMatch(unescaped)) return unescaped;
  return null;
}

// ---------------------------------------------------------------------------
// ImageUtils SintController
// ---------------------------------------------------------------------------

/// Manages image handling: resizing, clipboard access, storage, and validation.
class ImageUtils extends SintController {
  /// In-memory cache of stored image paths.
  final RxMap<int, String> _storedImagePaths = <int, String>{}.obs;

  /// Path to the image store directory.
  String Function() _getImageStoreDir =
      () => '${Platform.environment['HOME'] ?? ''}/.neomclaw/image-cache';

  /// Session ID for image store directory.
  String Function() _getSessionId = () => 'default';

  /// Image processor callback (sharp equivalent).
  Future<Uint8List> Function(
    Uint8List buffer, {
    int? width,
    int? height,
    String? format,
    int? quality,
    int? compressionLevel,
    bool? palette,
    int? colors,
  })? _imageProcessor;

  /// Image metadata reader callback.
  Future<({int? width, int? height, String? format})> Function(
    Uint8List buffer,
  )? _getImageMetadata;

  /// Logging callback.
  void Function(String message, {String? level}) _logForDebugging =
      (message, {level}) {};

  /// Error logging callback.
  void Function(Object error) _logError = (_) {};

  /// Event logging callback.
  void Function(String event, Map<String, dynamic> data) _logEvent =
      (event, data) {};

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  void configure({
    String Function()? getImageStoreDir,
    String Function()? getSessionId,
    Future<Uint8List> Function(
      Uint8List buffer, {
      int? width,
      int? height,
      String? format,
      int? quality,
      int? compressionLevel,
      bool? palette,
      int? colors,
    })? imageProcessor,
    Future<({int? width, int? height, String? format})> Function(
      Uint8List buffer,
    )? getImageMetadata,
    void Function(String, {String? level})? logForDebugging,
    void Function(Object)? logError,
    void Function(String, Map<String, dynamic>)? logEvent,
  }) {
    if (getImageStoreDir != null) _getImageStoreDir = getImageStoreDir;
    if (getSessionId != null) _getSessionId = getSessionId;
    if (imageProcessor != null) _imageProcessor = imageProcessor;
    if (getImageMetadata != null) _getImageMetadata = getImageMetadata;
    if (logForDebugging != null) _logForDebugging = logForDebugging;
    if (logError != null) _logError = logError;
    if (logEvent != null) _logEvent = logEvent;
  }

  // ---------------------------------------------------------------------------
  // Image resizing
  // ---------------------------------------------------------------------------

  /// Resizes image buffer to meet size and dimension constraints.
  Future<ResizeResult> maybeResizeAndDownsampleImageBuffer(
    Uint8List imageBuffer,
    int originalSize,
    String ext,
  ) async {
    if (imageBuffer.isEmpty) {
      throw ImageResizeError('Image file is empty (0 bytes)');
    }

    try {
      if (_imageProcessor == null || _getImageMetadata == null) {
        throw StateError('Image processor not configured');
      }

      final metadata = await _getImageMetadata!(imageBuffer);
      final mediaType = metadata.format ?? ext;
      final normalizedMediaType = mediaType == 'jpg' ? 'jpeg' : mediaType;

      if (metadata.width == null || metadata.height == null) {
        if (originalSize > imageTargetRawSize) {
          final compressed = await _imageProcessor!(
            imageBuffer,
            format: 'jpeg',
            quality: 80,
          );
          return ResizeResult(buffer: compressed, mediaType: 'jpeg');
        }
        return ResizeResult(buffer: imageBuffer, mediaType: normalizedMediaType);
      }

      final originalWidth = metadata.width!;
      final originalHeight = metadata.height!;
      int width = originalWidth;
      int height = originalHeight;

      // Check if original just works
      if (originalSize <= imageTargetRawSize &&
          width <= imageMaxWidth &&
          height <= imageMaxHeight) {
        return ResizeResult(
          buffer: imageBuffer,
          mediaType: normalizedMediaType,
          dimensions: ImageDimensions(
            originalWidth: originalWidth,
            originalHeight: originalHeight,
            displayWidth: width,
            displayHeight: height,
          ),
        );
      }

      final needsDimensionResize =
          width > imageMaxWidth || height > imageMaxHeight;
      final isPng = normalizedMediaType == 'png';

      // If dimensions are within limits but file is too large, try compression
      if (!needsDimensionResize && originalSize > imageTargetRawSize) {
        if (isPng) {
          final pngCompressed = await _imageProcessor!(
            imageBuffer,
            format: 'png',
            compressionLevel: 9,
            palette: true,
          );
          if (pngCompressed.length <= imageTargetRawSize) {
            return ResizeResult(
              buffer: pngCompressed,
              mediaType: 'png',
              dimensions: ImageDimensions(
                originalWidth: originalWidth,
                originalHeight: originalHeight,
                displayWidth: width,
                displayHeight: height,
              ),
            );
          }
        }
        for (final quality in [80, 60, 40, 20]) {
          final compressed = await _imageProcessor!(
            imageBuffer,
            format: 'jpeg',
            quality: quality,
          );
          if (compressed.length <= imageTargetRawSize) {
            return ResizeResult(
              buffer: compressed,
              mediaType: 'jpeg',
              dimensions: ImageDimensions(
                originalWidth: originalWidth,
                originalHeight: originalHeight,
                displayWidth: width,
                displayHeight: height,
              ),
            );
          }
        }
      }

      // Constrain dimensions
      if (width > imageMaxWidth) {
        height = (height * imageMaxWidth / width).round();
        width = imageMaxWidth;
      }
      if (height > imageMaxHeight) {
        width = (width * imageMaxHeight / height).round();
        height = imageMaxHeight;
      }

      _logForDebugging('Resizing to ${width}x$height');
      final resized = await _imageProcessor!(
        imageBuffer,
        width: width,
        height: height,
      );

      // If still too large, try compression
      if (resized.length > imageTargetRawSize) {
        for (final quality in [80, 60, 40, 20]) {
          final compressed = await _imageProcessor!(
            imageBuffer,
            width: width,
            height: height,
            format: 'jpeg',
            quality: quality,
          );
          if (compressed.length <= imageTargetRawSize) {
            return ResizeResult(
              buffer: compressed,
              mediaType: 'jpeg',
              dimensions: ImageDimensions(
                originalWidth: originalWidth,
                originalHeight: originalHeight,
                displayWidth: width,
                displayHeight: height,
              ),
            );
          }
        }

        // Last resort: smaller dimensions + aggressive compression
        final smallerWidth = min(width, 1000);
        final smallerHeight = (height * smallerWidth / max(width, 1)).round();
        final compressed = await _imageProcessor!(
          imageBuffer,
          width: smallerWidth,
          height: smallerHeight,
          format: 'jpeg',
          quality: 20,
        );
        return ResizeResult(
          buffer: compressed,
          mediaType: 'jpeg',
          dimensions: ImageDimensions(
            originalWidth: originalWidth,
            originalHeight: originalHeight,
            displayWidth: smallerWidth,
            displayHeight: smallerHeight,
          ),
        );
      }

      return ResizeResult(
        buffer: resized,
        mediaType: normalizedMediaType,
        dimensions: ImageDimensions(
          originalWidth: originalWidth,
          originalHeight: originalHeight,
          displayWidth: width,
          displayHeight: height,
        ),
      );
    } catch (error) {
      _logError(error);
      final errorType = classifyImageError(error);

      final detected = detectImageFormatFromBuffer(imageBuffer);
      final normalizedExt = detected.value.substring(6); // Remove 'image/'

      final base64Size = (originalSize * 4 / 3).ceil();

      // Check for oversized PNG dimensions
      bool overDim = false;
      if (imageBuffer.length >= 24 &&
          imageBuffer[0] == 0x89 &&
          imageBuffer[1] == 0x50 &&
          imageBuffer[2] == 0x4E &&
          imageBuffer[3] == 0x47) {
        final w = _readUint32BE(imageBuffer, 16);
        final h = _readUint32BE(imageBuffer, 20);
        overDim = w > imageMaxWidth || h > imageMaxHeight;
      }

      if (base64Size <= apiImageMaxBase64Size && !overDim) {
        _logEvent('tengu_image_resize_fallback', {
          'original_size_bytes': originalSize,
          'base64_size_bytes': base64Size,
          'error_type': errorType.code,
        });
        return ResizeResult(buffer: imageBuffer, mediaType: normalizedExt);
      }

      throw ImageResizeError(
        overDim
            ? 'Unable to resize image -- dimensions exceed the '
                '${imageMaxWidth}x${imageMaxHeight}px limit and image processing failed. '
                'Please resize the image to reduce its pixel dimensions.'
            : 'Unable to resize image (${formatFileSize(originalSize)} raw, '
                '${formatFileSize(base64Size)} base64). The image exceeds the 5MB API '
                'limit and compression failed. Please resize the image manually '
                'or use a smaller image.',
      );
    }
  }

  /// Read uint32 big-endian from buffer at offset.
  static int _readUint32BE(Uint8List buffer, int offset) {
    return (buffer[offset] << 24) |
        (buffer[offset + 1] << 16) |
        (buffer[offset + 2] << 8) |
        buffer[offset + 3];
  }

  /// Resizes an image content block if needed.
  Future<ImageBlockWithDimensions> maybeResizeAndDownsampleImageBlock(
    Map<String, dynamic> imageBlock,
  ) async {
    final source = imageBlock['source'] as Map<String, dynamic>?;
    if (source == null || source['type'] != 'base64') {
      return ImageBlockWithDimensions(block: imageBlock);
    }

    final base64Data = source['data'] as String;
    final imageBuffer = Uint8List.fromList(base64Decode(base64Data));
    final originalSize = imageBuffer.length;
    final mediaType = source['media_type'] as String? ?? 'image/png';
    final ext = mediaType.split('/').last;

    final resized = await maybeResizeAndDownsampleImageBuffer(
      imageBuffer,
      originalSize,
      ext,
    );

    return ImageBlockWithDimensions(
      block: {
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/${resized.mediaType}',
          'data': base64Encode(resized.buffer),
        },
      },
      dimensions: resized.dimensions,
    );
  }

  // ---------------------------------------------------------------------------
  // Image compression
  // ---------------------------------------------------------------------------

  /// Compresses an image buffer to fit within a maximum byte size.
  Future<CompressedImageResult> compressImageBuffer(
    Uint8List imageBuffer, {
    int maxBytes = imageTargetRawSize,
    String? originalMediaType,
  }) async {
    final fallbackFormat = originalMediaType?.split('/').last ?? 'jpeg';
    final normalizedFallback = fallbackFormat == 'jpg' ? 'jpeg' : fallbackFormat;

    if (imageBuffer.length <= maxBytes) {
      return CompressedImageResult(
        base64: base64Encode(imageBuffer),
        mediaType: 'image/$normalizedFallback',
        originalSize: imageBuffer.length,
      );
    }

    if (_imageProcessor == null || _getImageMetadata == null) {
      throw ImageResizeError(
        'Unable to compress image (${formatFileSize(imageBuffer.length)}) '
        'to fit within ${formatFileSize(maxBytes)}. Image processor not configured.',
      );
    }

    try {
      final metadata = await _getImageMetadata!(imageBuffer);
      final format = metadata.format ?? normalizedFallback;

      // Try progressive resizing with format preservation
      for (final scalingFactor in [1.0, 0.75, 0.5, 0.25]) {
        final newWidth =
            ((metadata.width ?? 2000) * scalingFactor).round();
        final newHeight =
            ((metadata.height ?? 2000) * scalingFactor).round();

        final resized = await _imageProcessor!(
          imageBuffer,
          width: newWidth,
          height: newHeight,
          format: format,
          quality: format == 'jpeg' || format == 'webp' ? 80 : null,
          compressionLevel: format == 'png' ? 9 : null,
          palette: format == 'png' ? true : null,
        );

        if (resized.length <= maxBytes) {
          return CompressedImageResult(
            base64: base64Encode(resized),
            mediaType: 'image/$format',
            originalSize: imageBuffer.length,
          );
        }
      }

      // Try JPEG with moderate compression
      final jpegBuffer = await _imageProcessor!(
        imageBuffer,
        width: 600,
        height: 600,
        format: 'jpeg',
        quality: 50,
      );
      if (jpegBuffer.length <= maxBytes) {
        return CompressedImageResult(
          base64: base64Encode(jpegBuffer),
          mediaType: 'image/jpeg',
          originalSize: imageBuffer.length,
        );
      }

      // Ultra-compressed JPEG
      final ultraCompressed = await _imageProcessor!(
        imageBuffer,
        width: 400,
        height: 400,
        format: 'jpeg',
        quality: 20,
      );
      return CompressedImageResult(
        base64: base64Encode(ultraCompressed),
        mediaType: 'image/jpeg',
        originalSize: imageBuffer.length,
      );
    } catch (error) {
      _logError(error);
      if (imageBuffer.length <= maxBytes) {
        final detected = detectImageFormatFromBuffer(imageBuffer);
        return CompressedImageResult(
          base64: base64Encode(imageBuffer),
          mediaType: detected.value,
          originalSize: imageBuffer.length,
        );
      }
      throw ImageResizeError(
        'Unable to compress image (${formatFileSize(imageBuffer.length)}) '
        'to fit within ${formatFileSize(maxBytes)}. Please use a smaller image.',
      );
    }
  }

  /// Compresses an image buffer to fit within a token limit.
  Future<CompressedImageResult> compressImageBufferWithTokenLimit(
    Uint8List imageBuffer,
    int maxTokens, {
    String? originalMediaType,
  }) async {
    final maxBase64Chars = (maxTokens / 0.125).floor();
    final maxBytes = (maxBase64Chars * 0.75).floor();
    return compressImageBuffer(
      imageBuffer,
      maxBytes: maxBytes,
      originalMediaType: originalMediaType,
    );
  }

  // ---------------------------------------------------------------------------
  // Clipboard operations
  // ---------------------------------------------------------------------------

  _ClipboardCommands _getClipboardCommands() {
    final tmpDir = Platform.environment['NEOMCLAW_TMPDIR'] ?? '/tmp';
    final screenshotPath = '$tmpDir/neomclaw_cli_latest_screenshot.png';

    if (Platform.isMacOS) {
      return _ClipboardCommands(
        checkImage: "osascript -e 'the clipboard as \u00abclass PNGf\u00bb'",
        saveImage:
            "osascript -e 'set png_data to (the clipboard as \u00abclass PNGf\u00bb)' "
            "-e 'set fp to open for access POSIX file \"$screenshotPath\" with write permission' "
            "-e 'write png_data to fp' -e 'close access fp'",
        getPath:
            "osascript -e 'get POSIX path of (the clipboard as \u00abclass furl\u00bb)'",
        deleteFile: 'rm -f "$screenshotPath"',
      );
    } else if (Platform.isLinux) {
      return _ClipboardCommands(
        checkImage:
            'xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -E "image/(png|jpeg|jpg|gif|webp|bmp)"',
        saveImage:
            'xclip -selection clipboard -t image/png -o > "$screenshotPath" 2>/dev/null',
        getPath:
            'xclip -selection clipboard -t text/plain -o 2>/dev/null || wl-paste 2>/dev/null',
        deleteFile: 'rm -f "$screenshotPath"',
      );
    }
    return _ClipboardCommands(
      checkImage: '',
      saveImage: '',
      getPath: '',
      deleteFile: '',
    );
  }

  /// Check if clipboard contains an image without retrieving it.
  Future<bool> hasImageInClipboard() async {
    if (!Platform.isMacOS) return false;
    try {
      final commands = _getClipboardCommands();
      final result = await Process.run('bash', ['-c', commands.checkImage]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Get image data from the clipboard.
  Future<ImageWithDimensions?> getImageFromClipboard() async {
    final commands = _getClipboardCommands();
    final tmpDir = Platform.environment['NEOMCLAW_TMPDIR'] ?? '/tmp';
    final screenshotPath = '$tmpDir/neomclaw_cli_latest_screenshot.png';

    try {
      // Check for image
      final checkResult =
          await Process.run('bash', ['-c', commands.checkImage]);
      if (checkResult.exitCode != 0) return null;

      // Save image
      final saveResult =
          await Process.run('bash', ['-c', commands.saveImage]);
      if (saveResult.exitCode != 0) return null;

      // Read image
      var imageBuffer = await File(screenshotPath).readAsBytes();
      final buffer = Uint8List.fromList(imageBuffer);

      // Resize if needed
      final resized = await maybeResizeAndDownsampleImageBuffer(
        buffer,
        buffer.length,
        'png',
      );
      final base64Image = base64Encode(resized.buffer);
      final mediaType = detectImageFormatFromBase64(base64Image);

      // Cleanup (fire-and-forget)
      unawaited(Process.run('bash', ['-c', commands.deleteFile]));

      return ImageWithDimensions(
        base64: base64Image,
        mediaType: mediaType.value,
        dimensions: resized.dimensions,
      );
    } catch (_) {
      return null;
    }
  }

  /// Try to get an image file path from the clipboard.
  Future<String?> getImagePathFromClipboard() async {
    final commands = _getClipboardCommands();
    try {
      final result = await Process.run('bash', ['-c', commands.getPath]);
      if (result.exitCode != 0 || (result.stdout as String).isEmpty) {
        return null;
      }
      return (result.stdout as String).trim();
    } catch (e) {
      _logError(e);
      return null;
    }
  }

  /// Try to find and read an image file, falling back to clipboard search.
  Future<({String path, ImageWithDimensions image})?> tryReadImageFromPath(
    String text,
  ) async {
    final cleanedPath = asImageFilePath(text);
    if (cleanedPath == null) return null;

    Uint8List? imageBuffer;
    try {
      if (cleanedPath.startsWith('/')) {
        imageBuffer = await File(cleanedPath).readAsBytes();
      } else {
        final clipboardPath = await getImagePathFromClipboard();
        if (clipboardPath != null &&
            cleanedPath == clipboardPath.split('/').last) {
          imageBuffer = await File(clipboardPath).readAsBytes();
        }
      }
    } catch (e) {
      _logError(e);
      return null;
    }

    if (imageBuffer == null || imageBuffer.isEmpty) return null;

    final ext = cleanedPath.split('.').last.toLowerCase();
    final buffer = Uint8List.fromList(imageBuffer);
    final resized = await maybeResizeAndDownsampleImageBuffer(
      buffer,
      buffer.length,
      ext.isEmpty ? 'png' : ext,
    );
    final base64Image = base64Encode(resized.buffer);
    final mediaType = detectImageFormatFromBase64(base64Image);

    return (
      path: cleanedPath,
      image: ImageWithDimensions(
        base64: base64Image,
        mediaType: mediaType.value,
        dimensions: resized.dimensions,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Image store
  // ---------------------------------------------------------------------------

  String _getSessionImageStoreDir() {
    return '${_getImageStoreDir()}/${_getSessionId()}';
  }

  String _getImagePath(int imageId, String mediaType) {
    final extension = mediaType.split('/').last;
    return '${_getSessionImageStoreDir()}/$imageId.$extension';
  }

  /// Cache the image path immediately (fast, no file I/O).
  String? cacheImagePath({
    required int id,
    required String type,
    String mediaType = 'image/png',
  }) {
    if (type != 'image') return null;
    final imagePath = _getImagePath(id, mediaType);
    _evictOldestIfAtCap();
    _storedImagePaths[id] = imagePath;
    return imagePath;
  }

  /// Store an image to disk.
  Future<String?> storeImage({
    required int id,
    required String type,
    required String content,
    String mediaType = 'image/png',
  }) async {
    if (type != 'image') return null;

    try {
      final dir = _getSessionImageStoreDir();
      await Directory(dir).create(recursive: true);
      final imagePath = _getImagePath(id, mediaType);
      await File(imagePath).writeAsBytes(base64Decode(content));
      _evictOldestIfAtCap();
      _storedImagePaths[id] = imagePath;
      _logForDebugging('Stored image $id to $imagePath');
      return imagePath;
    } catch (error) {
      _logForDebugging('Failed to store image: $error');
      return null;
    }
  }

  /// Store all images from pasted contents to disk.
  Future<Map<int, String>> storeImages(
    Map<int, Map<String, dynamic>> pastedContents,
  ) async {
    final pathMap = <int, String>{};
    for (final entry in pastedContents.entries) {
      if (entry.value['type'] == 'image') {
        final path = await storeImage(
          id: entry.key,
          type: 'image',
          content: entry.value['content'] as String,
          mediaType: entry.value['mediaType'] as String? ?? 'image/png',
        );
        if (path != null) pathMap[entry.key] = path;
      }
    }
    return pathMap;
  }

  /// Get the file path for a stored image by ID.
  String? getStoredImagePath(int imageId) {
    return _storedImagePaths[imageId];
  }

  /// Clear the in-memory cache of stored image paths.
  void clearStoredImagePaths() {
    _storedImagePaths.clear();
  }

  void _evictOldestIfAtCap() {
    while (_storedImagePaths.length >= _maxStoredImagePaths) {
      final oldest = _storedImagePaths.keys.first;
      _storedImagePaths.remove(oldest);
    }
  }

  /// Clean up old image cache directories from previous sessions.
  Future<void> cleanupOldImageCaches() async {
    final baseDir = _getImageStoreDir();
    final currentSessionId = _getSessionId();

    try {
      final dir = Directory(baseDir);
      if (!await dir.exists()) return;

      await for (final sessionDir in dir.list()) {
        if (sessionDir is! Directory) continue;
        if (sessionDir.path.split('/').last == currentSessionId) continue;

        try {
          await sessionDir.delete(recursive: true);
          _logForDebugging('Cleaned up old image cache: ${sessionDir.path}');
        } catch (_) {}
      }

      // Remove base dir if empty
      try {
        final remaining = await dir.list().toList();
        if (remaining.isEmpty) await dir.delete();
      } catch (_) {}
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Image validation
  // ---------------------------------------------------------------------------

  /// Validates that all images in messages are within the API size limit.
  void validateImagesForAPI(List<Map<String, dynamic>> messages) {
    final oversizedImages = <OversizedImage>[];
    int imageIndex = 0;

    for (final msg in messages) {
      if (msg['type'] != 'user') continue;

      final innerMessage = msg['message'] as Map<String, dynamic>?;
      if (innerMessage == null) continue;

      final content = innerMessage['content'];
      if (content is! List) continue;

      for (final block in content) {
        if (block is Map &&
            block['type'] == 'image' &&
            block['source'] is Map &&
            block['source']['type'] == 'base64' &&
            block['source']['data'] is String) {
          imageIndex++;
          final base64Size = (block['source']['data'] as String).length;
          if (base64Size > apiImageMaxBase64Size) {
            _logEvent('tengu_image_api_validation_failed', {
              'base64_size_bytes': base64Size,
              'max_bytes': apiImageMaxBase64Size,
            });
            oversizedImages
                .add(OversizedImage(index: imageIndex, size: base64Size));
          }
        }
      }
    }

    if (oversizedImages.isNotEmpty) {
      throw ImageSizeError(oversizedImages, apiImageMaxBase64Size);
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
  }

  @override
  void onClose() {
    super.onClose();
  }
}

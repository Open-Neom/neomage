import 'package:flutter/foundation.dart' show kIsWeb;

import 'platform_interface.dart';

// Conditional imports — the compiler picks one based on the target platform.
// On native: native_platform.dart is used.
// On web: web_platform.dart is used.
import 'platform_init_native.dart'
    if (dart.library.js_interop) 'platform_init_web.dart' as platform_impl;

/// Initialise the platform abstraction layer.
///
/// Call this once at application startup, before any code accesses
/// `PlatformService.instance`.
///
/// ```dart
/// void main() {
///   initializePlatform();
///   runApp(const MyApp());
/// }
/// ```
void initializePlatform() {
  PlatformService.initialize(platform_impl.createPlatformService());
}

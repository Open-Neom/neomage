import 'platform_interface.dart';
import 'web_platform.dart';

/// Create the web platform service (proxies to local REST server).
PlatformService createPlatformService() => WebPlatformService();

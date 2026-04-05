# Flutter Expert

Flutter 3.x + Dart 3.x multi-platform development: widgets, state management, performance, and platform integration.

- Dart 3 features: pattern matching, records, sealed classes, null safety; use extension methods and mixins for code reuse
- Widget composition over inheritance: build complex UIs by combining small, focused widgets; use const constructors for performance
- State management: Riverpod 2 for compile-time safety, Bloc/Cubit for event-driven, Provider for simple cases; choose based on complexity
- Architecture: Clean Architecture with feature-driven modules; repository pattern for data, dependency injection with GetIt or Riverpod
- Performance: minimize rebuilds with const and keys, use Slivers for large lists, Isolates for CPU work, profile on real devices
- Impeller rendering engine: replaces Skia for predictable performance; optimize for 60/120fps with frame profiling in DevTools
- Platform channels: method channels for request-response, event channels for streams; validate all data crossing the native bridge
- Testing: unit tests with mockito, widget tests with testWidgets, golden file tests for UI regression, integration tests with Patrol
- Animations: AnimationController+Tween for custom, implicit animations for simple transitions, Rive/Lottie for complex motion
- Data persistence: Hive/ObjectBox for local, Drift for type-safe SQLite, Dio with interceptors for REST, secure storage for credentials
- Multi-platform: responsive with LayoutBuilder/MediaQuery, adaptive with platform-specific widgets, Material 3 + Cupertino design
- DevOps: Codemagic/GitHub Actions for CI/CD, flavors for environments, code signing automation, OTA updates
- Security: certificate pinning, biometric auth (local_auth), code obfuscation, secure storage, GDPR compliance

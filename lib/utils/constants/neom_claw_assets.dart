/// Centralized asset paths for Neom Claw.
///
/// Use these constants instead of hardcoding asset paths:
/// ```dart
/// Image.asset(NeomClawAssets.appIcon)
/// Image.asset(NeomClawAssets.appIconNoBackground)
/// Image.asset(NeomClawAssets.logoProject)
/// ```
class NeomClawAssets {
  NeomClawAssets._();

  /// App icon with purple background (1080x1080).
  /// Use for: app icon, splash screen, about dialog.
  static const String appIcon = 'assets/appIcon.png';

  /// App icon without background — transparent PNG (1080x1080).
  /// Use for: overlay icons, dark backgrounds, notification icons.
  static const String appIconNoBackground = 'assets/appIcon_noBackground.png';

  /// Project logo with "Neom Claw" text — transparent PNG (1080x1080).
  /// Use for: onboarding, login, about screen, splash.
  static const String logoProject = 'assets/logo_project.png';
}

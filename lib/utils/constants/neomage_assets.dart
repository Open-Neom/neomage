/// Centralized asset paths for Neomage.
///
/// Assets live in the neomage package. When used as a dependency,
/// access via `packages/neomage/` prefix is handled automatically
/// by Flutter's asset bundling.
///
/// ```dart
/// Image.asset(NeomageAssets.icon)
/// Image.asset(NeomageAssets.logo)
/// ```
class NeomageAssets {
  NeomageAssets._();

  /// App icon (1080x1080).
  static const String icon = 'assets/neomage_icon.png';

  /// Project logo with "Neomage" text (1080x1080).
  static const String logo = 'assets/neomage_logo.png';
}

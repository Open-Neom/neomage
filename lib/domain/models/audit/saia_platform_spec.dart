/// Creative asset specifications per platform.
class SaiaPlatformSpec {
  /// Platform identifier.
  final String platformId;

  /// Platform display name.
  final String name;

  /// Supported creative dimensions.
  final List<SaiaCreativeDimension> dimensions;

  /// Character limits per copy field.
  final Map<String, int> charLimits;

  /// Copy zone statement for image generation.
  final String copyZone;

  const SaiaPlatformSpec({
    required this.platformId,
    required this.name,
    required this.dimensions,
    required this.charLimits,
    this.copyZone = '',
  });

  /// Pre-defined platform specs.
  static const metaFeed = SaiaPlatformSpec(
    platformId: 'meta_feed',
    name: 'Meta Feed',
    dimensions: [
      SaiaCreativeDimension(1080, 1350, '4:5'),
      SaiaCreativeDimension(1080, 1080, '1:1'),
    ],
    charLimits: {'primary': 125, 'headline': 40, 'description': 30},
    copyZone: 'lower 30% minimal and uncluttered for copy overlay',
  );

  static const metaStory = SaiaPlatformSpec(
    platformId: 'meta_story',
    name: 'Meta Story/Reel',
    dimensions: [SaiaCreativeDimension(1080, 1920, '9:16')],
    charLimits: {'primary': 125, 'headline': 40},
    copyZone: 'top 15% and bottom 20% minimal, active visual centered',
  );

  static const googleRsa = SaiaPlatformSpec(
    platformId: 'google_rsa',
    name: 'Google RSA',
    dimensions: [],
    charLimits: {'headline': 30, 'description': 90},
  );

  static const linkedIn = SaiaPlatformSpec(
    platformId: 'linkedin',
    name: 'LinkedIn',
    dimensions: [SaiaCreativeDimension(1200, 1200, '1:1')],
    charLimits: {'text': 150, 'headline': 70},
    copyZone: 'generous margin all sides, centered composition',
  );

  static const tikTok = SaiaPlatformSpec(
    platformId: 'tiktok',
    name: 'TikTok',
    dimensions: [SaiaCreativeDimension(1080, 1920, '9:16')],
    charLimits: {'text': 100, 'headline': 40},
    copyZone: 'top 15% and bottom 20% minimal, active visual centered',
  );

  static const youtube = SaiaPlatformSpec(
    platformId: 'youtube',
    name: 'YouTube',
    dimensions: [SaiaCreativeDimension(1920, 1080, '16:9')],
    charLimits: {'headline': 40, 'description': 90},
    copyZone: 'right 40% minimal for caption/copy overlay',
  );

  static const all = [metaFeed, metaStory, googleRsa, linkedIn, tikTok, youtube];
}

/// A single creative asset dimension specification.
class SaiaCreativeDimension {
  final int width;
  final int height;
  final String aspectRatio;

  const SaiaCreativeDimension(this.width, this.height, this.aspectRatio);

  @override
  String toString() => '${width}x$height ($aspectRatio)';
}

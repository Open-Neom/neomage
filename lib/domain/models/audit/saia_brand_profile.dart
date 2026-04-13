import 'saia_voice_axes.dart';

/// Brand DNA profile extracted from a website or provided manually.
///
/// Used to generate on-brand creative assets and copy.
class SaiaBrandProfile {
  final String schemaVersion;
  final String brandName;
  final String? websiteUrl;
  final DateTime extractedAt;

  /// Brand voice characteristics.
  final SaiaVoiceAxes voice;

  /// Brand color palette.
  final SaiaBrandColors colors;

  /// Typography preferences.
  final SaiaBrandTypography typography;

  /// Imagery style and preferences.
  final SaiaBrandImagery imagery;

  /// Aesthetic mood and texture.
  final SaiaBrandAesthetic aesthetic;

  /// Core brand values.
  final List<String> brandValues;

  /// Target audience definition.
  final SaiaTargetAudience? targetAudience;

  const SaiaBrandProfile({
    this.schemaVersion = '1.0',
    required this.brandName,
    this.websiteUrl,
    required this.extractedAt,
    required this.voice,
    required this.colors,
    this.typography = const SaiaBrandTypography(),
    this.imagery = const SaiaBrandImagery(),
    this.aesthetic = const SaiaBrandAesthetic(),
    this.brandValues = const [],
    this.targetAudience,
  });

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'brand_name': brandName,
        'website_url': websiteUrl,
        'extracted_at': extractedAt.toIso8601String(),
        'voice': {...voice.toMap(), 'descriptors': voice.descriptors},
        'colors': colors.toJson(),
        'typography': typography.toJson(),
        'imagery': imagery.toJson(),
        'aesthetic': aesthetic.toJson(),
        'brand_values': brandValues,
        if (targetAudience != null) 'target_audience': targetAudience!.toJson(),
      };

  factory SaiaBrandProfile.fromJson(Map<String, dynamic> json) {
    return SaiaBrandProfile(
      schemaVersion: json['schema_version'] as String? ?? '1.0',
      brandName: json['brand_name'] as String,
      websiteUrl: json['website_url'] as String?,
      extractedAt: DateTime.parse(json['extracted_at'] as String),
      voice: SaiaVoiceAxes.fromMap(json['voice'] as Map<String, dynamic>),
      colors: SaiaBrandColors.fromJson(json['colors'] as Map<String, dynamic>),
      typography: json['typography'] != null
          ? SaiaBrandTypography.fromJson(json['typography'] as Map<String, dynamic>)
          : const SaiaBrandTypography(),
      imagery: json['imagery'] != null
          ? SaiaBrandImagery.fromJson(json['imagery'] as Map<String, dynamic>)
          : const SaiaBrandImagery(),
      aesthetic: json['aesthetic'] != null
          ? SaiaBrandAesthetic.fromJson(json['aesthetic'] as Map<String, dynamic>)
          : const SaiaBrandAesthetic(),
      brandValues: (json['brand_values'] as List?)?.cast<String>() ?? [],
      targetAudience: json['target_audience'] != null
          ? SaiaTargetAudience.fromJson(json['target_audience'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Build an image generation prompt from this profile.
  String toImagePrompt({
    required String subject,
    required String composition,
  }) {
    final parts = [
      subject,
      imagery.style,
      composition,
      'brand colors ${colors.primary}',
      if (colors.secondary.isNotEmpty) 'and ${colors.secondary.first}',
      '${aesthetic.moodKeywords.join(', ')} atmosphere',
      if (aesthetic.texture.isNotEmpty) '${aesthetic.texture} texture',
      if (aesthetic.negativeSpace.isNotEmpty) '${aesthetic.negativeSpace} composition',
      if (imagery.forbidden.isNotEmpty) 'no ${imagery.forbidden.join(', ')}',
    ];
    return parts.where((p) => p.isNotEmpty).join(', ');
  }
}

class SaiaBrandColors {
  final String primary;
  final List<String> secondary;
  final List<String> forbidden;
  final String background;
  final String text;

  const SaiaBrandColors({
    this.primary = '#000000',
    this.secondary = const [],
    this.forbidden = const [],
    this.background = '#FFFFFF',
    this.text = '#000000',
  });

  Map<String, dynamic> toJson() => {
        'primary': primary,
        'secondary': secondary,
        'forbidden': forbidden,
        'background': background,
        'text': text,
      };

  factory SaiaBrandColors.fromJson(Map<String, dynamic> json) => SaiaBrandColors(
        primary: json['primary'] as String? ?? '#000000',
        secondary: (json['secondary'] as List?)?.cast<String>() ?? [],
        forbidden: (json['forbidden'] as List?)?.cast<String>() ?? [],
        background: json['background'] as String? ?? '#FFFFFF',
        text: json['text'] as String? ?? '#000000',
      );
}

class SaiaBrandTypography {
  final String headingFont;
  final String bodyFont;
  final String pairingDescriptor;

  const SaiaBrandTypography({
    this.headingFont = 'system-ui',
    this.bodyFont = 'system-ui',
    this.pairingDescriptor = '',
  });

  Map<String, dynamic> toJson() => {
        'heading_font': headingFont,
        'body_font': bodyFont,
        'pairing_descriptor': pairingDescriptor,
      };

  factory SaiaBrandTypography.fromJson(Map<String, dynamic> json) => SaiaBrandTypography(
        headingFont: json['heading_font'] as String? ?? 'system-ui',
        bodyFont: json['body_font'] as String? ?? 'system-ui',
        pairingDescriptor: json['pairing_descriptor'] as String? ?? '',
      );
}

class SaiaBrandImagery {
  final String style;
  final List<String> subjects;
  final String composition;
  final List<String> forbidden;

  const SaiaBrandImagery({
    this.style = '',
    this.subjects = const [],
    this.composition = '',
    this.forbidden = const [],
  });

  Map<String, dynamic> toJson() => {
        'style': style,
        'subjects': subjects,
        'composition': composition,
        'forbidden': forbidden,
      };

  factory SaiaBrandImagery.fromJson(Map<String, dynamic> json) => SaiaBrandImagery(
        style: json['style'] as String? ?? '',
        subjects: (json['subjects'] as List?)?.cast<String>() ?? [],
        composition: json['composition'] as String? ?? '',
        forbidden: (json['forbidden'] as List?)?.cast<String>() ?? [],
      );
}

class SaiaBrandAesthetic {
  final List<String> moodKeywords;
  final String texture;
  final String negativeSpace;

  const SaiaBrandAesthetic({
    this.moodKeywords = const [],
    this.texture = '',
    this.negativeSpace = '',
  });

  Map<String, dynamic> toJson() => {
        'mood_keywords': moodKeywords,
        'texture': texture,
        'negative_space': negativeSpace,
      };

  factory SaiaBrandAesthetic.fromJson(Map<String, dynamic> json) => SaiaBrandAesthetic(
        moodKeywords: (json['mood_keywords'] as List?)?.cast<String>() ?? [],
        texture: json['texture'] as String? ?? '',
        negativeSpace: json['negative_space'] as String? ?? '',
      );
}

class SaiaTargetAudience {
  final String ageRange;
  final String profession;
  final List<String> painPoints;
  final List<String> aspirations;

  const SaiaTargetAudience({
    this.ageRange = '',
    this.profession = '',
    this.painPoints = const [],
    this.aspirations = const [],
  });

  Map<String, dynamic> toJson() => {
        'age_range': ageRange,
        'profession': profession,
        'pain_points': painPoints,
        'aspirations': aspirations,
      };

  factory SaiaTargetAudience.fromJson(Map<String, dynamic> json) => SaiaTargetAudience(
        ageRange: json['age_range'] as String? ?? '',
        profession: json['profession'] as String? ?? '',
        painPoints: (json['pain_points'] as List?)?.cast<String>() ?? [],
        aspirations: (json['aspirations'] as List?)?.cast<String>() ?? [],
      );
}

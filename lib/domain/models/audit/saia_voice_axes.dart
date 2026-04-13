/// Brand voice axes on a 1-10 scale.
///
/// Extracted from a brand's website, content, and existing ads.
/// Used to guide copy tone and visual style generation.
class SaiaVoiceAxes {
  /// 1=Very formal, corporate → 10=Very casual, conversational.
  final double formalCasual;

  /// 1=Data-driven, logical → 10=Emotionally evocative.
  final double rationalEmotional;

  /// 1=Fun, humorous → 10=Serious, no-nonsense.
  final double playfulSerious;

  /// 1=Big claims, loud → 10=Understated, nuanced.
  final double boldSubtle;

  /// 1=Classic, established → 10=Cutting-edge, disruptive.
  final double traditionalInnovative;

  /// 1=Deep expertise, jargon → 10=Everyone understands.
  final double expertAccessible;

  /// 3-5 adjectives describing the brand voice.
  final List<String> descriptors;

  const SaiaVoiceAxes({
    this.formalCasual = 5,
    this.rationalEmotional = 5,
    this.playfulSerious = 5,
    this.boldSubtle = 5,
    this.traditionalInnovative = 5,
    this.expertAccessible = 5,
    this.descriptors = const [],
  });

  Map<String, double> toMap() => {
        'formal_casual': formalCasual,
        'rational_emotional': rationalEmotional,
        'playful_serious': playfulSerious,
        'bold_subtle': boldSubtle,
        'traditional_innovative': traditionalInnovative,
        'expert_accessible': expertAccessible,
      };

  factory SaiaVoiceAxes.fromMap(Map<String, dynamic> map) => SaiaVoiceAxes(
        formalCasual: (map['formal_casual'] as num?)?.toDouble() ?? 5,
        rationalEmotional: (map['rational_emotional'] as num?)?.toDouble() ?? 5,
        playfulSerious: (map['playful_serious'] as num?)?.toDouble() ?? 5,
        boldSubtle: (map['bold_subtle'] as num?)?.toDouble() ?? 5,
        traditionalInnovative: (map['traditional_innovative'] as num?)?.toDouble() ?? 5,
        expertAccessible: (map['expert_accessible'] as num?)?.toDouble() ?? 5,
        descriptors: (map['descriptors'] as List?)?.cast<String>() ?? [],
      );
}

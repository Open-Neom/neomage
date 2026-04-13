import 'saia_copy_framework.dart';
import 'saia_platform_spec.dart';

/// A campaign concept generated from brand DNA + audit insights.
class SaiaCampaignConcept {
  /// Concept name (memorable, descriptive — not "Campaign A").
  final String name;

  /// Why this concept will work (grounded in brand or audit data).
  final String hypothesis;

  /// Single core message.
  final String primaryMessage;

  /// Voice axis reading for this concept (e.g., "formal 7/10, bold 8/10").
  final String toneDescription;

  /// Selected copy framework.
  final SaiaCopyFramework copyFramework;

  /// Visual direction variants.
  final List<SaiaVisualDirection> visualDirections;

  /// Target platforms with rationale.
  final List<String> targetPlatforms;

  /// Primary call to action.
  final String cta;

  /// Which audit finding this concept addresses (or "general awareness").
  final String addresses;

  const SaiaCampaignConcept({
    required this.name,
    required this.hypothesis,
    required this.primaryMessage,
    required this.toneDescription,
    required this.copyFramework,
    this.visualDirections = const [],
    required this.targetPlatforms,
    required this.cta,
    this.addresses = 'general brand awareness',
  });
}

/// Visual direction for image generation.
class SaiaVisualDirection {
  /// Direction label (e.g., "Photography", "Illustration").
  final String label;

  /// Image generation prompt (2-3 sentences).
  final String prompt;

  /// Target dimensions.
  final SaiaCreativeDimension dimensions;

  /// Aspect ratio for the image.
  final String aspectRatio;

  /// Copy zone statement for safe areas.
  final String copyZone;

  const SaiaVisualDirection({
    required this.label,
    required this.prompt,
    required this.dimensions,
    required this.aspectRatio,
    this.copyZone = '',
  });
}

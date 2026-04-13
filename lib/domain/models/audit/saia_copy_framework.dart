/// Ad copy framework for structured content generation.
///
/// Each framework provides a proven structure for persuasive
/// messaging, optimized for different audiences and objectives.
enum SaiaCopyFramework {
  /// Attention → Interest → Desire → Action.
  /// Best for: Cold audiences, awareness, product launches.
  aida(
    name: 'AIDA',
    fullName: 'Attention, Interest, Desire, Action',
    bestFor: ['cold audiences', 'awareness campaigns', 'product launches'],
    sections: ['attention', 'interest', 'desire', 'action'],
  ),

  /// Problem → Agitate → Solution.
  /// Best for: Pain-point products, retargeting, problem-aware audiences.
  pas(
    name: 'PAS',
    fullName: 'Problem, Agitate, Solution',
    bestFor: ['pain-point products', 'retargeting', 'problem-aware audiences'],
    sections: ['problem', 'agitate', 'solution'],
  ),

  /// Before → After → Bridge.
  /// Best for: Transformation offers, coaching, fitness, lifestyle.
  bab(
    name: 'BAB',
    fullName: 'Before, After, Bridge',
    bestFor: ['transformation offers', 'coaching', 'fitness', 'lifestyle'],
    sections: ['before', 'after', 'bridge'],
  ),

  /// Promise → Picture → Proof → Push.
  /// Best for: High-ticket items, premium services, B2B enterprise.
  fourP(
    name: '4P',
    fullName: 'Promise, Picture, Proof, Push',
    bestFor: ['high-ticket items', 'premium services', 'B2B enterprise'],
    sections: ['promise', 'picture', 'proof', 'push'],
  ),

  /// Features → Advantages → Benefits.
  /// Best for: Technical products, comparison shoppers, search intent.
  fab(
    name: 'FAB',
    fullName: 'Features, Advantages, Benefits',
    bestFor: ['technical products', 'comparison shoppers', 'search intent'],
    sections: ['features', 'advantages', 'benefits'],
  ),

  /// Star → Story → Solution.
  /// Best for: Brand storytelling, emotional campaigns, UGC content.
  starStory(
    name: 'Star-Story-Solution',
    fullName: 'Star, Story, Solution',
    bestFor: ['brand storytelling', 'emotional campaigns', 'UGC content'],
    sections: ['star', 'story', 'solution'],
  );

  final String name;
  final String fullName;
  final List<String> bestFor;
  final List<String> sections;

  const SaiaCopyFramework({
    required this.name,
    required this.fullName,
    required this.bestFor,
    required this.sections,
  });

  /// Select best framework based on audience warmth.
  static SaiaCopyFramework forAudience(AudienceWarmth warmth, CopyObjective objective) {
    return switch ((warmth, objective)) {
      (AudienceWarmth.cold, CopyObjective.awareness) => aida,
      (AudienceWarmth.cold, CopyObjective.consideration) => bab,
      (AudienceWarmth.cold, CopyObjective.conversion) => aida,
      (AudienceWarmth.warm, CopyObjective.awareness) => starStory,
      (AudienceWarmth.warm, CopyObjective.consideration) => pas,
      (AudienceWarmth.warm, CopyObjective.conversion) => fab,
      (AudienceWarmth.hot, CopyObjective.awareness) => starStory,
      (AudienceWarmth.hot, CopyObjective.consideration) => fourP,
      (AudienceWarmth.hot, CopyObjective.conversion) => fab,
    };
  }
}

/// Audience temperature for framework selection.
enum AudienceWarmth {
  /// Unaware of brand/product.
  cold,
  /// Engaged but not converted.
  warm,
  /// Past customers or high-intent.
  hot,
}

/// Campaign objective for framework selection.
enum CopyObjective {
  awareness,
  consideration,
  conversion,
}

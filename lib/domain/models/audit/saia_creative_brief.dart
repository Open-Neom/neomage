import 'saia_brand_profile.dart';
import 'saia_campaign_concept.dart';

/// Complete creative brief assembling brand DNA + campaign concepts.
///
/// Sequential pipeline output:
/// 1. Brand DNA extraction → [SaiaBrandProfile]
/// 2. Strategy + concepts → [SaiaCampaignConcept]s
/// 3. This brief → ready for copy writing + image generation
class SaiaCreativeBrief {
  /// Brand profile driving the creative direction.
  final SaiaBrandProfile brandProfile;

  /// Campaign concepts (3-5 recommended).
  final List<SaiaCampaignConcept> concepts;

  /// Overall campaign objective.
  final String objective;

  /// Target audience summary.
  final String audienceSummary;

  /// Budget context (if available).
  final String? budgetContext;

  /// Audit findings that informed the strategy (if audit was run).
  final List<String> auditInsights;

  /// When the brief was generated.
  final DateTime createdAt;

  const SaiaCreativeBrief({
    required this.brandProfile,
    required this.concepts,
    required this.objective,
    required this.audienceSummary,
    this.budgetContext,
    this.auditInsights = const [],
    required this.createdAt,
  });

  /// Format the brief as markdown.
  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('# Creative Brief: ${brandProfile.brandName}');
    buf.writeln();
    buf.writeln('**Objective:** $objective');
    buf.writeln('**Audience:** $audienceSummary');
    if (budgetContext != null) buf.writeln('**Budget:** $budgetContext');
    buf.writeln('**Generated:** ${createdAt.toIso8601String().substring(0, 10)}');
    buf.writeln();

    // Brand voice summary
    buf.writeln('## Brand Voice');
    buf.writeln();
    final v = brandProfile.voice;
    buf.writeln('- Formal/Casual: ${v.formalCasual.toStringAsFixed(0)}/10');
    buf.writeln('- Rational/Emotional: ${v.rationalEmotional.toStringAsFixed(0)}/10');
    buf.writeln('- Bold/Subtle: ${v.boldSubtle.toStringAsFixed(0)}/10');
    if (v.descriptors.isNotEmpty) {
      buf.writeln('- Descriptors: ${v.descriptors.join(', ')}');
    }
    buf.writeln();

    // Audit insights
    if (auditInsights.isNotEmpty) {
      buf.writeln('## Audit Insights');
      buf.writeln();
      for (final insight in auditInsights) {
        buf.writeln('- $insight');
      }
      buf.writeln();
    }

    // Concepts
    for (int i = 0; i < concepts.length; i++) {
      final c = concepts[i];
      buf.writeln('## Concept ${i + 1}: ${c.name}');
      buf.writeln();
      buf.writeln('**Hypothesis:** ${c.hypothesis}');
      buf.writeln('**Primary Message:** ${c.primaryMessage}');
      buf.writeln('**Tone:** ${c.toneDescription}');
      buf.writeln('**Copy Framework:** ${c.copyFramework.name}');
      buf.writeln('**Platforms:** ${c.targetPlatforms.join(', ')}');
      buf.writeln('**CTA:** ${c.cta}');
      buf.writeln('**Addresses:** ${c.addresses}');
      buf.writeln();

      for (final vd in c.visualDirections) {
        buf.writeln('### Visual: ${vd.label} (${vd.dimensions})');
        buf.writeln('**Prompt:** ${vd.prompt}');
        if (vd.copyZone.isNotEmpty) {
          buf.writeln('**Copy Zone:** ${vd.copyZone}');
        }
        buf.writeln();
      }
    }

    return buf.toString();
  }
}

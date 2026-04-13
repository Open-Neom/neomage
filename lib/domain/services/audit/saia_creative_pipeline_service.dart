import '../../models/audit/saia_brand_profile.dart';
import '../../models/audit/saia_campaign_concept.dart';
import '../../models/audit/saia_creative_brief.dart';

/// Service contract for the sequential creative pipeline.
///
/// Pipeline stages:
/// 1. Extract brand DNA → [SaiaBrandProfile]
/// 2. Generate campaign concepts → [SaiaCampaignConcept]s
/// 3. Assemble creative brief → [SaiaCreativeBrief]
/// 4. Generate copy per concept (external — LLM)
/// 5. Generate images per visual direction (external — image gen)
abstract class SaiaCreativePipelineService {
  /// Stage 1: Extract brand DNA from a URL or provided content.
  Future<SaiaBrandProfile> extractBrandDna({
    String? url,
    String? htmlContent,
    Map<String, dynamic>? manualInput,
  });

  /// Stage 2: Generate campaign concepts from brand profile + optional audit.
  Future<List<SaiaCampaignConcept>> generateConcepts({
    required SaiaBrandProfile profile,
    List<String>? auditInsights,
    String? objective,
    int conceptCount = 3,
  });

  /// Stage 3: Assemble a complete creative brief.
  Future<SaiaCreativeBrief> assembleBrief({
    required SaiaBrandProfile profile,
    required List<SaiaCampaignConcept> concepts,
    required String objective,
    required String audienceSummary,
    String? budgetContext,
    List<String> auditInsights = const [],
  });

  /// Run the full pipeline: DNA → concepts → brief.
  Future<SaiaCreativeBrief> runFullPipeline({
    String? url,
    String? objective,
    int conceptCount = 3,
  });
}

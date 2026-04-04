// Billing utilities — port of billing.ts + modelCost.ts + extraUsage.ts +
// attribution.ts + privacyLevel.ts.
// Billing access checks, model cost calculation, extra usage detection,
// attribution text generation, privacy level controls.

import 'dart:async';
import 'package:flutter_claw/core/platform/claw_io.dart';

import 'package:sint/sint.dart';

// ============================================================================
// Privacy Level
// ============================================================================

/// Privacy level controls how much nonessential network traffic and telemetry
/// the application generates.
///
/// Levels are ordered by restrictiveness:
///   default < noTelemetry < essentialTraffic
///
/// - defaultLevel:       Everything enabled.
/// - noTelemetry:        Analytics/telemetry disabled.
/// - essentialTraffic:   ALL nonessential network traffic disabled
///                       (telemetry + auto-updates, grove, release notes, etc.).
enum PrivacyLevel {
  defaultLevel,
  noTelemetry,
  essentialTraffic,
}

/// Get the current privacy level based on environment variables.
///
/// The resolved level is the most restrictive signal from:
///   NEOMCLAW_DISABLE_NONESSENTIAL_TRAFFIC -> essentialTraffic
///   DISABLE_TELEMETRY                        -> noTelemetry
PrivacyLevel getPrivacyLevel() {
  if (Platform.environment.containsKey(
      'NEOMCLAW_DISABLE_NONESSENTIAL_TRAFFIC')) {
    return PrivacyLevel.essentialTraffic;
  }
  if (Platform.environment.containsKey('DISABLE_TELEMETRY')) {
    return PrivacyLevel.noTelemetry;
  }
  return PrivacyLevel.defaultLevel;
}

/// True when all nonessential network traffic should be suppressed.
/// Equivalent to the old NEOMCLAW_DISABLE_NONESSENTIAL_TRAFFIC check.
bool isEssentialTrafficOnly() {
  return getPrivacyLevel() == PrivacyLevel.essentialTraffic;
}

/// True when telemetry/analytics should be suppressed.
/// True at both noTelemetry and essentialTraffic levels.
bool isTelemetryDisabled() {
  return getPrivacyLevel() != PrivacyLevel.defaultLevel;
}

/// Returns the env var name responsible for the current essential-traffic
/// restriction, or null if unrestricted. Used for user-facing
/// "unset X to re-enable" messages.
String? getEssentialTrafficOnlyReason() {
  if (Platform.environment.containsKey(
      'NEOMCLAW_DISABLE_NONESSENTIAL_TRAFFIC')) {
    return 'NEOMCLAW_DISABLE_NONESSENTIAL_TRAFFIC';
  }
  return null;
}

// ============================================================================
// Model Costs
// ============================================================================

/// Cost structure for a model (per million tokens).
/// @see https://platform.neomclaw.com/docs/en/about-claude/pricing
class ModelCosts {
  final double inputTokens;
  final double outputTokens;
  final double promptCacheWriteTokens;
  final double promptCacheReadTokens;
  final double webSearchRequests;

  const ModelCosts({
    required this.inputTokens,
    required this.outputTokens,
    required this.promptCacheWriteTokens,
    required this.promptCacheReadTokens,
    required this.webSearchRequests,
  });
}

/// Standard pricing tier for Sonnet models: $3 input / $15 output per Mtok.
const ModelCosts costTier3_15 = ModelCosts(
  inputTokens: 3,
  outputTokens: 15,
  promptCacheWriteTokens: 3.75,
  promptCacheReadTokens: 0.3,
  webSearchRequests: 0.01,
);

/// Pricing tier for Opus 4/4.1: $15 input / $75 output per Mtok.
const ModelCosts costTier15_75 = ModelCosts(
  inputTokens: 15,
  outputTokens: 75,
  promptCacheWriteTokens: 18.75,
  promptCacheReadTokens: 1.5,
  webSearchRequests: 0.01,
);

/// Pricing tier for Opus 4.5: $5 input / $25 output per Mtok.
const ModelCosts costTier5_25 = ModelCosts(
  inputTokens: 5,
  outputTokens: 25,
  promptCacheWriteTokens: 6.25,
  promptCacheReadTokens: 0.5,
  webSearchRequests: 0.01,
);

/// Fast mode pricing for Opus 4.6: $30 input / $150 output per Mtok.
const ModelCosts costTier30_150 = ModelCosts(
  inputTokens: 30,
  outputTokens: 150,
  promptCacheWriteTokens: 37.5,
  promptCacheReadTokens: 3,
  webSearchRequests: 0.01,
);

/// Pricing for Haiku 3.5: $0.80 input / $4 output per Mtok.
const ModelCosts costHaiku35 = ModelCosts(
  inputTokens: 0.8,
  outputTokens: 4,
  promptCacheWriteTokens: 1,
  promptCacheReadTokens: 0.08,
  webSearchRequests: 0.01,
);

/// Pricing for Haiku 4.5: $1 input / $5 output per Mtok.
const ModelCosts costHaiku45 = ModelCosts(
  inputTokens: 1,
  outputTokens: 5,
  promptCacheWriteTokens: 1.25,
  promptCacheReadTokens: 0.1,
  webSearchRequests: 0.01,
);

/// Default cost when model is unknown.
const ModelCosts _defaultUnknownModelCost = costTier5_25;

/// Token usage from an API response.
class TokenUsageInfo {
  final int inputTokens;
  final int outputTokens;
  final int? cacheReadInputTokens;
  final int? cacheCreationInputTokens;
  final int? webSearchRequestCount;
  final String? speed;

  const TokenUsageInfo({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheReadInputTokens,
    this.cacheCreationInputTokens,
    this.webSearchRequestCount,
    this.speed,
  });
}

/// Raw token counts for cost calculation without a full usage object.
class RawTokenCounts {
  final int inputTokens;
  final int outputTokens;
  final int cacheReadInputTokens;
  final int cacheCreationInputTokens;

  const RawTokenCounts({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadInputTokens,
    required this.cacheCreationInputTokens,
  });
}

/// Model short name type alias.
typedef ModelShortName = String;

// ── Model name resolution (stubs, real impls in model_catalog.dart) ──

/// Callback type for resolving canonical model names.
typedef CanonicalNameResolver = ModelShortName Function(String model);

/// Callback type for resolving the default main-loop model setting.
typedef DefaultModelResolver = String Function();

/// Callback type for checking if fast mode is enabled.
typedef FastModeChecker = bool Function();

/// Callback type for flagging an unknown model cost.
typedef UnknownModelCostFlagged = void Function();

/// Callback type for analytics logging.
typedef AnalyticsLogger = void Function(
    String eventName, Map<String, dynamic> metadata);

// ── Model cost registry ──

/// Known model cost mappings.
/// @[MODEL LAUNCH]: Add a pricing entry for the new model below.
/// Costs from https://platform.neomclaw.com/docs/en/about-claude/pricing
final Map<ModelShortName, ModelCosts> modelCosts = {
  'claude-3-5-haiku': costHaiku35,
  'claude-haiku-4-5': costHaiku45,
  'claude-3-5-sonnet-v2': costTier3_15,
  'claude-3-7-sonnet': costTier3_15,
  'claude-sonnet-4': costTier3_15,
  'claude-sonnet-4-5': costTier3_15,
  'claude-sonnet-4-6': costTier3_15,
  'claude-opus-4': costTier15_75,
  'claude-opus-4-1': costTier15_75,
  'claude-opus-4-5': costTier5_25,
  'claude-opus-4-6': costTier5_25,
};

/// Get the cost tier for Opus 4.6 based on fast mode.
ModelCosts getOpus46CostTier({
  required bool fastMode,
  required FastModeChecker isFastModeEnabled,
}) {
  if (isFastModeEnabled() && fastMode) {
    return costTier30_150;
  }
  return costTier5_25;
}

/// Calculates the USD cost based on token usage and model cost configuration.
double _tokensToUsdCost(ModelCosts costs, TokenUsageInfo usage) {
  return (usage.inputTokens / 1000000) * costs.inputTokens +
      (usage.outputTokens / 1000000) * costs.outputTokens +
      ((usage.cacheReadInputTokens ?? 0) / 1000000) *
          costs.promptCacheReadTokens +
      ((usage.cacheCreationInputTokens ?? 0) / 1000000) *
          costs.promptCacheWriteTokens +
      (usage.webSearchRequestCount ?? 0) * costs.webSearchRequests;
}

/// Get the model costs for a model, handling Opus 4.6 fast mode and unknown
/// models.
ModelCosts getModelCostsForModel(
  String model,
  TokenUsageInfo usage, {
  required CanonicalNameResolver getCanonicalName,
  required DefaultModelResolver getDefaultMainLoopModelSetting,
  required FastModeChecker isFastModeEnabled,
  UnknownModelCostFlagged? onUnknownModelCost,
  AnalyticsLogger? logEvent,
}) {
  final shortName = getCanonicalName(model);

  // Check if this is an Opus 4.6 model with fast mode active.
  if (shortName == 'claude-opus-4-6') {
    final isFastMode = usage.speed == 'fast';
    return getOpus46CostTier(
      fastMode: isFastMode,
      isFastModeEnabled: isFastModeEnabled,
    );
  }

  final costs = modelCosts[shortName];
  if (costs == null) {
    _trackUnknownModelCost(
      model,
      shortName,
      logEvent: logEvent,
      onUnknownModelCost: onUnknownModelCost,
    );
    return modelCosts[getCanonicalName(getDefaultMainLoopModelSetting())] ??
        _defaultUnknownModelCost;
  }
  return costs;
}

/// Track that a model's cost is unknown via analytics.
void _trackUnknownModelCost(
  String model,
  ModelShortName shortName, {
  AnalyticsLogger? logEvent,
  UnknownModelCostFlagged? onUnknownModelCost,
}) {
  logEvent?.call('tengu_unknown_model_cost', {
    'model': model,
    'shortName': shortName,
  });
  onUnknownModelCost?.call();
}

/// Calculate the cost of a query in US dollars.
/// If the model's costs are not found, use the default model's costs.
double calculateUsdCost(
  String resolvedModel,
  TokenUsageInfo usage, {
  required CanonicalNameResolver getCanonicalName,
  required DefaultModelResolver getDefaultMainLoopModelSetting,
  required FastModeChecker isFastModeEnabled,
  UnknownModelCostFlagged? onUnknownModelCost,
  AnalyticsLogger? logEvent,
}) {
  final costs = getModelCostsForModel(
    resolvedModel,
    usage,
    getCanonicalName: getCanonicalName,
    getDefaultMainLoopModelSetting: getDefaultMainLoopModelSetting,
    isFastModeEnabled: isFastModeEnabled,
    onUnknownModelCost: onUnknownModelCost,
    logEvent: logEvent,
  );
  return _tokensToUsdCost(costs, usage);
}

/// Calculate cost from raw token counts without requiring a full TokenUsageInfo
/// object. Useful for side queries (e.g. classifier) that track token counts
/// independently.
double calculateCostFromTokens(
  String model,
  RawTokenCounts tokens, {
  required CanonicalNameResolver getCanonicalName,
  required DefaultModelResolver getDefaultMainLoopModelSetting,
  required FastModeChecker isFastModeEnabled,
  UnknownModelCostFlagged? onUnknownModelCost,
  AnalyticsLogger? logEvent,
}) {
  final usage = TokenUsageInfo(
    inputTokens: tokens.inputTokens,
    outputTokens: tokens.outputTokens,
    cacheReadInputTokens: tokens.cacheReadInputTokens,
    cacheCreationInputTokens: tokens.cacheCreationInputTokens,
  );
  return calculateUsdCost(
    model,
    usage,
    getCanonicalName: getCanonicalName,
    getDefaultMainLoopModelSetting: getDefaultMainLoopModelSetting,
    isFastModeEnabled: isFastModeEnabled,
    onUnknownModelCost: onUnknownModelCost,
    logEvent: logEvent,
  );
}

/// Format a price value for display.
/// Integers render without decimals, others with 2 decimal places.
/// e.g., 3 -> "\$3", 0.8 -> "\$0.80", 22.5 -> "\$22.50"
String _formatPrice(double price) {
  if (price == price.truncateToDouble()) {
    return '\$${price.toInt()}';
  }
  return '\$${price.toStringAsFixed(2)}';
}

/// Format model costs as a pricing string for display.
/// e.g., "\$3/\$15 per Mtok"
String formatModelPricing(ModelCosts costs) {
  return '${_formatPrice(costs.inputTokens)}/${_formatPrice(costs.outputTokens)} per Mtok';
}

/// Get formatted pricing string for a model.
/// Accepts either a short name or full model name.
/// Returns null if model is not found.
String? getModelPricingString(
  String model, {
  required CanonicalNameResolver getCanonicalName,
}) {
  final shortName = getCanonicalName(model);
  final costs = modelCosts[shortName];
  if (costs == null) return null;
  return formatModelPricing(costs);
}

// ============================================================================
// Billing Access
// ============================================================================

/// OAuth account information relevant to billing access checks.
class OAuthAccountInfo {
  final String? organizationRole;
  final String? workspaceRole;

  const OAuthAccountInfo({
    this.organizationRole,
    this.workspaceRole,
  });
}

/// Global config relevant to billing.
class BillingConfig {
  final OAuthAccountInfo? oauthAccount;

  const BillingConfig({this.oauthAccount});
}

/// Auth token source information.
class AuthTokenSource {
  final bool hasToken;

  const AuthTokenSource({required this.hasToken});
}

/// Subscription type.
typedef SubscriptionType = String;

/// Check if user has Console billing access.
///
/// Checks authentication state, subscriber status, and org/workspace roles
/// to determine if the user can see billing information.
bool hasConsoleBillingAccess({
  required bool Function() isDisableCostWarnings,
  required bool Function() isNeomClawAiSubscriber,
  required AuthTokenSource Function() getAuthTokenSource,
  required bool Function() hasApiKey,
  required BillingConfig Function() getGlobalConfig,
}) {
  // Check if cost reporting is disabled via environment variable.
  if (isDisableCostWarnings()) {
    return false;
  }

  final isSubscriber = isNeomClawAiSubscriber();

  // This might be wrong if user is signed into Max but also using an API key,
  // but we already show a warning on launch in that case.
  if (isSubscriber) return false;

  // Check if user has any form of authentication.
  final authSource = getAuthTokenSource();
  final apiKeyPresent = hasApiKey();

  // If user has no authentication at all (logged out), don't show costs.
  if (!authSource.hasToken && !apiKeyPresent) {
    return false;
  }

  final config = getGlobalConfig();
  final orgRole = config.oauthAccount?.organizationRole;
  final workspaceRole = config.oauthAccount?.workspaceRole;

  if (orgRole == null || workspaceRole == null) {
    return false; // hide cost for grandfathered users who have not re-authed
  }

  // Users have billing access if they are admins or billing roles at either
  // workspace or organization level.
  return ['admin', 'billing'].contains(orgRole) ||
      ['workspace_admin', 'workspace_billing'].contains(workspaceRole);
}

/// Mock billing access for /mock-limits testing.
bool? _mockBillingAccessOverride;

/// Set or clear the mock billing access override.
void setMockBillingAccessOverride(bool? value) {
  _mockBillingAccessOverride = value;
}

/// Check if user has NeomClaw AI billing access.
///
/// Consumer plans (Max/Pro) - individual users always have billing access.
/// Team/Enterprise - check for admin or billing roles.
bool hasNeomClawAiBillingAccess({
  required bool Function() isNeomClawAiSubscriber,
  required SubscriptionType? Function() getSubscriptionType,
  required BillingConfig Function() getGlobalConfig,
}) {
  // Check for mock billing access first (for /mock-limits testing).
  if (_mockBillingAccessOverride != null) {
    return _mockBillingAccessOverride!;
  }

  if (!isNeomClawAiSubscriber()) {
    return false;
  }

  final subscriptionType = getSubscriptionType();

  // Consumer plans (Max/Pro) - individual users always have billing access.
  if (subscriptionType == 'max' || subscriptionType == 'pro') {
    return true;
  }

  // Team/Enterprise - check for admin or billing roles.
  final config = getGlobalConfig();
  final orgRole = config.oauthAccount?.organizationRole;

  return orgRole != null &&
      ['admin', 'billing', 'owner', 'primary_owner'].contains(orgRole);
}

// ============================================================================
// Extra Usage Detection
// ============================================================================

/// Determines if the current request is billed as extra usage.
///
/// Extra usage applies to NeomClaw AI subscribers when:
/// - Fast mode is enabled
/// - Using Opus 4.6 or Sonnet 4.6 with 1M context (unless Opus 1M is merged)
bool isBilledAsExtraUsage({
  required String? model,
  required bool isFastMode,
  required bool isOpus1mMerged,
  required bool Function() isNeomClawAiSubscriber,
  required bool Function(String) has1mContext,
}) {
  if (!isNeomClawAiSubscriber()) return false;
  if (isFastMode) return true;
  if (model == null || !has1mContext(model)) return false;

  final m = model
      .toLowerCase()
      .replaceAll(RegExp(r'\[1m\]$'), '')
      .trim();
  final isOpus46 = m == 'opus' || m.contains('opus-4-6');
  final isSonnet46 = m == 'sonnet' || m.contains('sonnet-4-6');

  if (isOpus46 && isOpus1mMerged) return false;

  return isOpus46 || isSonnet46;
}

// ============================================================================
// Attribution
// ============================================================================

/// Attribution texts for commits and PRs.
class AttributionTexts {
  final String commit;
  final String pr;

  const AttributionTexts({
    required this.commit,
    required this.pr,
  });
}

/// Attribution data summary.
class AttributionDataSummary {
  final int neomClawPercent;

  const AttributionDataSummary({required this.neomClawPercent});
}

/// Full attribution data from commit analysis.
class AttributionData {
  final AttributionDataSummary summary;

  const AttributionData({required this.summary});
}

/// File state map for attribution tracking.
class AttributionState {
  final Map<String, dynamic> fileStates;

  const AttributionState({required this.fileStates});

  /// Get the list of tracked file paths.
  List<String> get trackedFiles => fileStates.keys.toList();
}

/// App state relevant to attribution.
class AttributionAppState {
  final AttributionState? attribution;

  const AttributionAppState({this.attribution});
}

/// Settings relevant to attribution.
class AttributionSettings {
  final AttributionSettingOverride? attribution;
  final bool? includeCoAuthoredBy;

  const AttributionSettings({
    this.attribution,
    this.includeCoAuthoredBy,
  });
}

/// Custom attribution overrides from settings.
class AttributionSettingOverride {
  final String? commit;
  final String? pr;

  const AttributionSettingOverride({this.commit, this.pr});
}

/// XML tags that mark terminal output.
const List<String> terminalOutputTags = [
  'bash_input',
  'bash_output',
  'bash_stderr',
  'local_command_caveat',
];

/// Message structure for counting user prompts.
class PromptCountMessage {
  final String type;
  final dynamic content;
  final bool isSidechain;

  const PromptCountMessage({
    required this.type,
    this.content,
    this.isSidechain = false,
  });
}

/// Check if a message content string is terminal output rather than a user
/// prompt. Terminal output includes bash input/output tags and caveat messages.
bool _isTerminalOutput(String content) {
  for (final tag in terminalOutputTags) {
    if (content.contains('<$tag>')) {
      return true;
    }
  }
  return false;
}

/// Count user messages with visible text content in a list of non-sidechain
/// messages. Excludes tool_result blocks, terminal output, and empty messages.
///
/// Callers should pass messages already filtered to exclude sidechain messages.
int countUserPromptsInMessages(List<PromptCountMessage> messages) {
  var count = 0;

  for (final message in messages) {
    if (message.type != 'user') {
      continue;
    }

    final content = message.content;
    if (content == null) {
      continue;
    }

    bool hasUserText = false;

    if (content is String) {
      if (_isTerminalOutput(content)) {
        continue;
      }
      hasUserText = content.trim().isNotEmpty;
    } else if (content is List) {
      hasUserText = content.any((block) {
        if (block is! Map<String, dynamic>) {
          return false;
        }
        final blockType = block['type'];
        if (blockType == 'text') {
          final text = block['text'];
          return text is String && !_isTerminalOutput(text);
        }
        return blockType == 'image' || blockType == 'document';
      });
    }

    if (hasUserText) {
      count++;
    }
  }

  return count;
}

/// Count non-sidechain user messages in transcript entries.
/// Used to calculate the number of "steers" (user prompts - 1).
int countUserPromptsFromEntries(List<PromptCountMessage> entries) {
  final nonSidechain =
      entries.where((entry) => entry.type == 'user' && !entry.isSidechain);
  return countUserPromptsInMessages(nonSidechain.toList());
}

/// Tool names used for memory file access detection.
const Set<String> memoryAccessToolNames = {
  'file_read',
  'grep',
  'glob',
  'file_edit',
  'file_write',
};

/// Transcript entry for memory access counting.
class TranscriptEntry {
  final String type;
  final List<Map<String, dynamic>>? contentBlocks;

  const TranscriptEntry({
    required this.type,
    this.contentBlocks,
  });
}

/// Callback type for checking if a tool invocation accesses a memory file.
typedef MemoryFileAccessChecker = bool Function(
    String toolName, dynamic input);

/// Count memory file accesses in transcript entries.
/// Uses the same detection conditions as the PostToolUse session file access
/// hooks.
int countMemoryFileAccessFromEntries(
  List<TranscriptEntry> entries, {
  required MemoryFileAccessChecker isMemoryFileAccess,
}) {
  var count = 0;
  for (final entry in entries) {
    if (entry.type != 'assistant') continue;
    final blocks = entry.contentBlocks;
    if (blocks == null) continue;
    for (final block in blocks) {
      if (block['type'] != 'tool_use' ||
          !memoryAccessToolNames.contains(block['name'])) {
        continue;
      }
      if (isMemoryFileAccess(block['name'] as String, block['input'])) {
        count++;
      }
    }
  }
  return count;
}

/// Transcript stats result.
class TranscriptStats {
  final int promptCount;
  final int memoryAccessCount;

  const TranscriptStats({
    required this.promptCount,
    required this.memoryAccessCount,
  });
}

/// Returns attribution text for commits and PRs based on user settings.
///
/// Handles:
/// - Dynamic model name via getPublicModelName()
/// - Custom attribution settings (settings.attribution.commit/pr)
/// - Backward compatibility with deprecated includeCoAuthoredBy setting
/// - Remote mode: returns session URL for attribution
AttributionTexts getAttributionTexts({
  required String? userType,
  required bool Function() isUndercover,
  required String Function() getClientType,
  required String? remoteSessionId,
  required String? ingressUrl,
  required bool Function(String, String?) isRemoteSessionLocal,
  required String Function(String, String?) getRemoteSessionUrl,
  required String Function() getMainLoopModel,
  required String? Function(String) getPublicModelDisplayName,
  required String Function(String) getPublicModelName,
  required bool Function() isInternalModelRepoCached,
  required AttributionSettings Function() getInitialSettings,
  required bool Function() isDisableCoAuthoredBy,
}) {
  if (userType == 'ant' && isUndercover()) {
    return const AttributionTexts(commit: '', pr: '');
  }

  if (getClientType() == 'remote') {
    if (remoteSessionId != null) {
      // Skip for local dev - URLs won't persist.
      if (!isRemoteSessionLocal(remoteSessionId, ingressUrl)) {
        final sessionUrl = getRemoteSessionUrl(remoteSessionId, ingressUrl);
        return AttributionTexts(commit: sessionUrl, pr: sessionUrl);
      }
    }
    return const AttributionTexts(commit: '', pr: '');
  }

  // @[MODEL LAUNCH]: Update the hardcoded fallback model name below.
  final model = getMainLoopModel();
  final isKnownPublicModel = getPublicModelDisplayName(model) != null;
  final modelName = isInternalModelRepoCached() || isKnownPublicModel
      ? getPublicModelName(model)
      : 'NeomClaw Opus 4.6';
  const defaultAttribution =
      'Generated with [OpenNeomClaw](https://github.com/Gitlawb/openneomclaw)';
  final defaultCommit = isDisableCoAuthoredBy()
      ? ''
      : 'Co-Authored-By: $modelName <noreply@anthropic.com>';

  final settings = getInitialSettings();

  // New attribution setting takes precedence over deprecated
  // includeCoAuthoredBy.
  if (settings.attribution != null) {
    return AttributionTexts(
      commit: settings.attribution!.commit ?? defaultCommit,
      pr: settings.attribution!.pr ?? defaultAttribution,
    );
  }

  // Backward compatibility: deprecated includeCoAuthoredBy setting.
  if (settings.includeCoAuthoredBy == false) {
    return const AttributionTexts(commit: '', pr: '');
  }

  return AttributionTexts(commit: defaultCommit, pr: defaultAttribution);
}

/// Get full attribution data from the provided AppState's attribution state.
/// Uses ALL tracked files from the attribution state (not just staged files)
/// because for PR attribution, files may not be staged yet.
/// Returns null if no attribution data is available.
Future<AttributionData?> getPrAttributionData(
  AttributionAppState appState, {
  required Future<AttributionData?> Function(
          List<AttributionState>, List<String>)
      calculateCommitAttribution,
}) async {
  final attribution = appState.attribution;
  if (attribution == null) {
    return null;
  }

  final trackedFiles = attribution.trackedFiles;
  if (trackedFiles.isEmpty) {
    return null;
  }

  try {
    return await calculateCommitAttribution([attribution], trackedFiles);
  } catch (e) {
    // Log error but don't throw.
    return null;
  }
}

/// Get enhanced PR attribution text with NeomClaw contribution stats.
///
/// Format: "Generated with NeomClaw (93% 3-shotted by claude-opus-4-5)"
///
/// Rules:
/// - Shows NeomClaw contribution percentage from commit attribution
/// - Shows N-shotted where N is the prompt count
/// - Shows short model name
/// - Returns default attribution if stats can't be computed
Future<String> getEnhancedPrAttribution({
  required AttributionAppState Function() getAppState,
  required String? userType,
  required bool Function() isUndercover,
  required String Function() getClientType,
  required String? remoteSessionId,
  required String? ingressUrl,
  required bool Function(String, String?) isRemoteSessionLocal,
  required String Function(String, String?) getRemoteSessionUrl,
  required AttributionSettings Function() getInitialSettings,
  required String Function(String) getCanonicalName,
  required String Function() getMainLoopModel,
  required String Function(String) sanitizeModelName,
  required Future<bool> Function() isInternalModelRepo,
  required Future<AttributionData?> Function(AttributionAppState)
      getAttributionData,
  required Future<TranscriptStats> Function() getTranscriptStats,
}) async {
  if (userType == 'ant' && isUndercover()) {
    return '';
  }

  if (getClientType() == 'remote') {
    if (remoteSessionId != null) {
      if (!isRemoteSessionLocal(remoteSessionId, ingressUrl)) {
        return getRemoteSessionUrl(remoteSessionId, ingressUrl);
      }
    }
    return '';
  }

  final settings = getInitialSettings();

  // If user has custom PR attribution, use that.
  if (settings.attribution?.pr != null) {
    return settings.attribution!.pr!;
  }

  // Backward compatibility: deprecated includeCoAuthoredBy setting.
  if (settings.includeCoAuthoredBy == false) {
    return '';
  }

  const defaultAttribution =
      'Generated with [OpenNeomClaw](https://github.com/Gitlawb/openneomclaw)';

  // Get AppState.
  final appState = getAppState();

  // Get attribution stats in parallel.
  final results = await Future.wait([
    getAttributionData(appState),
    getTranscriptStats(),
    isInternalModelRepo(),
  ]);

  final attributionData = results[0] as AttributionData?;
  final transcriptStats = results[1] as TranscriptStats;
  final isInternal = results[2] as bool;

  final neomClawPercent = attributionData?.summary.neomClawPercent ?? 0;
  final promptCount = transcriptStats.promptCount;
  final memoryAccessCount = transcriptStats.memoryAccessCount;

  // Get short model name, sanitized for non-internal repos.
  final rawModelName = getCanonicalName(getMainLoopModel());
  final shortModelName =
      isInternal ? rawModelName : sanitizeModelName(rawModelName);

  // If no attribution data, return default.
  if (neomClawPercent == 0 && promptCount == 0 && memoryAccessCount == 0) {
    return defaultAttribution;
  }

  // Build the enhanced attribution.
  final memSuffix = memoryAccessCount > 0
      ? ', $memoryAccessCount ${memoryAccessCount == 1 ? 'memory' : 'memories'} recalled'
      : '';
  final summary =
      'Generated with [OpenNeomClaw](https://github.com/Gitlawb/openneomclaw) '
      '($neomClawPercent% $promptCount-shotted by $shortModelName$memSuffix)';

  return summary;
}

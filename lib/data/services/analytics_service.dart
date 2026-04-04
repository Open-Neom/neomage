// Analytics service — port of neom_claw/src/services/analytics/.
// Public API for event logging, sink routing, sampling, metadata enrichment,
// Datadog batching, first-party event logging, feature gating (GrowthBook),
// and sink killswitch.
//
// DESIGN: The public [logEvent] / [logEventAsync] queue events until
// [attachAnalyticsSink] is called during app initialisation. The sink
// handles routing to Datadog and first-party event logging.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sint/sint.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Marker types — Dart doesn't have TS's `never`, so we use typedefs
// annotating developer intent.
// ═══════════════════════════════════════════════════════════════════════════

/// Marker verifying analytics metadata contains no code or file paths.
typedef AnalyticsVerifiedString = String;

/// Marker for values routed to PII-tagged proto columns.
typedef AnalyticsPiiTaggedString = String;

// ═══════════════════════════════════════════════════════════════════════════
// Strip _PROTO_* keys
// ═══════════════════════════════════════════════════════════════════════════

/// Strip `_PROTO_*` keys from a payload destined for general-access storage.
/// Returns the input unchanged when no _PROTO_ keys present.
Map<String, V> stripProtoFields<V>(Map<String, V> metadata) {
  final hasProto = metadata.keys.any((k) => k.startsWith('_PROTO_'));
  if (!hasProto) return metadata;
  return Map<String, V>.fromEntries(
    metadata.entries.where((e) => !e.key.startsWith('_PROTO_')),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Log event metadata type
// ═══════════════════════════════════════════════════════════════════════════

/// Internal metadata type for logEvent — intentionally excludes raw strings
/// to avoid accidentally logging code / file paths.
typedef LogEventMetadata = Map<String, Object?>;

// ═══════════════════════════════════════════════════════════════════════════
// Queued event
// ═══════════════════════════════════════════════════════════════════════════

class _QueuedEvent {
  final String eventName;
  final LogEventMetadata metadata;
  final bool isAsync;

  const _QueuedEvent({
    required this.eventName,
    required this.metadata,
    required this.isAsync,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Analytics sink interface
// ═══════════════════════════════════════════════════════════════════════════

/// Sink interface for the analytics backend.
abstract class AnalyticsSink {
  void logEvent(String eventName, LogEventMetadata metadata);
  Future<void> logEventAsync(String eventName, LogEventMetadata metadata);
}

// ═══════════════════════════════════════════════════════════════════════════
// Analytics config
// ═══════════════════════════════════════════════════════════════════════════

/// Check if analytics operations should be disabled.
///
/// Analytics is disabled when:
/// - Test environment
/// - Third-party cloud providers (Bedrock/Vertex/Foundry)
/// - Privacy level is no-telemetry or essential-traffic
class AnalyticsConfig {
  final bool Function() isTestEnvironment;
  final bool Function() isThirdPartyProvider;
  final bool Function() isTelemetryDisabled;

  const AnalyticsConfig({
    required this.isTestEnvironment,
    required this.isThirdPartyProvider,
    required this.isTelemetryDisabled,
  });

  bool get isAnalyticsDisabled =>
      isTestEnvironment() || isThirdPartyProvider() || isTelemetryDisabled();

  /// Unlike [isAnalyticsDisabled], this does NOT block on 3P providers.
  /// The feedback survey is a local UI prompt with no transcript data.
  bool get isFeedbackSurveyDisabled =>
      isTestEnvironment() || isTelemetryDisabled();
}

// ═══════════════════════════════════════════════════════════════════════════
// Sink killswitch
// ═══════════════════════════════════════════════════════════════════════════

/// Names of analytics sinks that can be individually killed.
enum SinkName { datadog, firstParty }

/// Per-sink analytics killswitch backed by a dynamic config.
///
/// Shape: `{ "datadog": true, "firstParty": true }`
/// A value of `true` stops all dispatch to that sink.
/// Default `{}` (nothing killed). Fail-open: missing/malformed = sink stays on.
class SinkKillswitch {
  final Map<String, bool> Function() _getConfig;

  const SinkKillswitch({required Map<String, bool> Function() getConfig})
    : _getConfig = getConfig;

  bool isSinkKilled(SinkName sink) {
    final config = _getConfig();
    return config[sink.name] == true;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Event sampling
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for sampling individual event types.
/// Each event name maps to an object containing sample_rate (0–1).
/// Events not in the config are logged at 100% rate.
typedef EventSamplingConfig = Map<String, EventSampleRate>;

class EventSampleRate {
  final double sampleRate;
  const EventSampleRate({required this.sampleRate});

  factory EventSampleRate.fromJson(Map<String, dynamic> json) {
    return EventSampleRate(
      sampleRate: (json['sample_rate'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Determine if an event should be sampled based on its sample rate.
/// Returns the sample rate if sampled, `null` if not configured, `0` if dropped.
double? shouldSampleEvent(String eventName, EventSamplingConfig config) {
  final eventConfig = config[eventName];
  if (eventConfig == null) return null;

  final rate = eventConfig.sampleRate;
  if (rate < 0 || rate > 1 || rate.isNaN) return null;
  if (rate >= 1) return null;
  if (rate <= 0) return 0;

  final random = Random();
  return random.nextDouble() < rate ? rate : 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// Metadata sanitisation helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Sanitises tool names for analytics logging to avoid PII exposure.
///
/// MCP tool names follow the format `mcp__<server>__<tool>` and can reveal
/// user-specific server configurations (PII-medium). This function redacts
/// MCP tool names while preserving built-in tool names.
AnalyticsVerifiedString sanitizeToolNameForAnalytics(String toolName) {
  if (toolName.startsWith('mcp__')) return 'mcp_tool';
  return toolName;
}

/// Extract MCP server and tool names from a full MCP tool name.
/// MCP tool names follow the format: `mcp__<server>__<tool>`
class McpToolDetails {
  final AnalyticsVerifiedString serverName;
  final AnalyticsVerifiedString mcpToolName;

  const McpToolDetails({required this.serverName, required this.mcpToolName});
}

/// Parse MCP tool details from a full tool name.
/// Returns `null` if not an MCP tool.
McpToolDetails? extractMcpToolDetails(String toolName) {
  if (!toolName.startsWith('mcp__')) return null;
  final parts = toolName.split('__');
  if (parts.length < 3) return null;
  final serverName = parts[1];
  final mcpToolName = parts.sublist(2).join('__');
  if (serverName.isEmpty || mcpToolName.isEmpty) return null;
  return McpToolDetails(serverName: serverName, mcpToolName: mcpToolName);
}

/// Extract skill name from Skill tool input.
AnalyticsVerifiedString? extractSkillName(String toolName, Object? input) {
  if (toolName != 'Skill') return null;
  if (input is Map && input['skill'] is String) {
    return input['skill'] as String;
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// Tool input truncation for telemetry
// ═══════════════════════════════════════════════════════════════════════════

const _toolInputStringTruncateAt = 512;
const _toolInputStringTruncateTo = 128;
const _toolInputMaxJsonChars = 4 * 1024;
const _toolInputMaxCollectionItems = 20;
const _toolInputMaxDepth = 2;

Object? _truncateToolInputValue(Object? value, [int depth = 0]) {
  if (value is String) {
    if (value.length > _toolInputStringTruncateAt) {
      return '${value.substring(0, _toolInputStringTruncateTo)}...[${value.length} chars]';
    }
    return value;
  }
  if (value is num || value is bool || value == null) return value;
  if (depth >= _toolInputMaxDepth) return '<nested>';
  if (value is List) {
    final mapped = value
        .take(_toolInputMaxCollectionItems)
        .map((v) => _truncateToolInputValue(v, depth + 1))
        .toList();
    if (value.length > _toolInputMaxCollectionItems) {
      mapped.add('...[${value.length} items]');
    }
    return mapped;
  }
  if (value is Map) {
    final entries = value.entries
        .where((e) => e.key is String && !(e.key as String).startsWith('_'))
        .toList();
    final mapped = entries
        .take(_toolInputMaxCollectionItems)
        .map(
          (e) => MapEntry(e.key, _truncateToolInputValue(e.value, depth + 1)),
        )
        .toList();
    if (entries.length > _toolInputMaxCollectionItems) {
      mapped.add(MapEntry('...', '${entries.length} keys'));
    }
    return Map.fromEntries(mapped);
  }
  return value.toString();
}

/// Serialize a tool's input arguments for the OTel tool_result event.
/// Truncates long strings and deep nesting to keep the output bounded.
/// Returns `null` when tool details logging is not enabled.
String? extractToolInputForTelemetry(
  Object? input, {
  required bool isToolDetailsLoggingEnabled,
}) {
  if (!isToolDetailsLoggingEnabled) return null;
  final truncated = _truncateToolInputValue(input);
  var json = jsonEncode(truncated);
  if (json.length > _toolInputMaxJsonChars) {
    json = '${json.substring(0, _toolInputMaxJsonChars)}...[truncated]';
  }
  return json;
}

// ═══════════════════════════════════════════════════════════════════════════
// File extension analytics helpers
// ═══════════════════════════════════════════════════════════════════════════

const _maxFileExtensionLength = 10;

/// Extracts and sanitises a file extension for analytics logging.
AnalyticsVerifiedString? getFileExtensionForAnalytics(String filePath) {
  final dotIndex = filePath.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == filePath.length - 1) return null;
  final ext = filePath.substring(dotIndex + 1).toLowerCase();
  if (ext.isEmpty) return null;
  if (ext.length > _maxFileExtensionLength) return 'other';
  return ext;
}

/// Allow-list of commands we extract file extensions from.
const _fileCommands = <String>{
  'rm',
  'mv',
  'cp',
  'touch',
  'mkdir',
  'chmod',
  'chown',
  'cat',
  'head',
  'tail',
  'sort',
  'stat',
  'diff',
  'wc',
  'grep',
  'rg',
  'sed',
};

final _compoundOperatorRegex = RegExp(r'\s*(?:&&|\|\||[;|])\s*');
final _whitespaceRegex = RegExp(r'\s+');

/// Extracts file extensions from a bash command for analytics.
AnalyticsVerifiedString? getFileExtensionsFromBashCommand(
  String command, [
  String? simulatedSedEditFilePath,
]) {
  if (!command.contains('.') && simulatedSedEditFilePath == null) return null;

  String? result;
  final seen = <String>{};

  if (simulatedSedEditFilePath != null) {
    final ext = getFileExtensionForAnalytics(simulatedSedEditFilePath);
    if (ext != null) {
      seen.add(ext);
      result = ext;
    }
  }

  for (final subcmd in command.split(_compoundOperatorRegex)) {
    if (subcmd.isEmpty) continue;
    final tokens = subcmd.split(_whitespaceRegex);
    if (tokens.length < 2) continue;

    final firstToken = tokens[0];
    final slashIdx = firstToken.lastIndexOf('/');
    final baseCmd = slashIdx >= 0
        ? firstToken.substring(slashIdx + 1)
        : firstToken;
    if (!_fileCommands.contains(baseCmd)) continue;

    for (var i = 1; i < tokens.length; i++) {
      final arg = tokens[i];
      if (arg.startsWith('-')) continue;
      final ext = getFileExtensionForAnalytics(arg);
      if (ext != null && !seen.contains(ext)) {
        seen.add(ext);
        result = result != null ? '$result,$ext' : ext;
      }
    }
  }

  return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// Environment context
// ═══════════════════════════════════════════════════════════════════════════

/// Environment context metadata included with analytics events.
class EnvContext {
  final String platform;
  final String platformRaw;
  final String arch;
  final String nodeVersion;
  final String? terminal;
  final String packageManagers;
  final String runtimes;
  final bool isCi;
  final bool isRemote;
  final bool isLocalAgentMode;
  final String version;
  final String? versionBase;
  final String buildTime;
  final String deploymentEnvironment;
  final String? wslVersion;
  final String? linuxDistroId;
  final String? vcs;

  const EnvContext({
    required this.platform,
    required this.platformRaw,
    required this.arch,
    this.nodeVersion = '',
    this.terminal,
    this.packageManagers = '',
    this.runtimes = '',
    this.isCi = false,
    this.isRemote = false,
    this.isLocalAgentMode = false,
    this.version = '',
    this.versionBase,
    this.buildTime = '',
    this.deploymentEnvironment = 'production',
    this.wslVersion,
    this.linuxDistroId,
    this.vcs,
  });

  Map<String, Object?> toMap() => {
    'platform': platform,
    'platformRaw': platformRaw,
    'arch': arch,
    'nodeVersion': nodeVersion,
    'terminal': terminal,
    'packageManagers': packageManagers,
    'runtimes': runtimes,
    'isCi': isCi,
    'isRemote': isRemote,
    'isLocalAgentMode': isLocalAgentMode,
    'version': version,
    'versionBase': versionBase,
    'buildTime': buildTime,
    'deploymentEnvironment': deploymentEnvironment,
    'wslVersion': wslVersion,
    'linuxDistroId': linuxDistroId,
    'vcs': vcs,
  };
}

/// Process metrics included with all analytics events.
class ProcessMetrics {
  final double uptime;
  final int rss;
  final int heapTotal;
  final int heapUsed;
  final int external;
  final int arrayBuffers;

  const ProcessMetrics({
    required this.uptime,
    required this.rss,
    required this.heapTotal,
    required this.heapUsed,
    this.external = 0,
    this.arrayBuffers = 0,
  });

  Map<String, Object> toMap() => {
    'uptime': uptime,
    'rss': rss,
    'heapTotal': heapTotal,
    'heapUsed': heapUsed,
    'external': external,
    'arrayBuffers': arrayBuffers,
  };
}

/// Core event metadata shared across all analytics systems.
class EventMetadata {
  final String model;
  final String sessionId;
  final String userType;
  final String? betas;
  final EnvContext envContext;
  final String? entrypoint;
  final String isInteractive;
  final String clientType;
  final ProcessMetrics? processMetrics;
  final String? subscriptionType;
  final String? repoHash;
  final String? agentId;
  final String? parentSessionId;
  final String? agentType;
  final String? teamName;

  const EventMetadata({
    required this.model,
    required this.sessionId,
    required this.userType,
    this.betas,
    required this.envContext,
    this.entrypoint,
    this.isInteractive = 'true',
    this.clientType = 'cli',
    this.processMetrics,
    this.subscriptionType,
    this.repoHash,
    this.agentId,
    this.parentSessionId,
    this.agentType,
    this.teamName,
  });

  Map<String, Object?> toMap() => {
    'model': model,
    'sessionId': sessionId,
    'userType': userType,
    'betas': betas,
    'envContext': envContext.toMap(),
    'entrypoint': entrypoint,
    'isInteractive': isInteractive,
    'clientType': clientType,
    'processMetrics': processMetrics?.toMap(),
    'subscriptionType': subscriptionType,
    'rh': repoHash,
    'agentId': agentId,
    'parentSessionId': parentSessionId,
    'agentType': agentType,
    'teamName': teamName,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// Datadog log entry
// ═══════════════════════════════════════════════════════════════════════════

/// A single Datadog log entry.
class DatadogLog {
  final String ddsource;
  final String ddtags;
  final String message;
  final String service;
  final String hostname;
  final Map<String, Object?> extra;

  const DatadogLog({
    required this.ddsource,
    required this.ddtags,
    required this.message,
    required this.service,
    required this.hostname,
    this.extra = const {},
  });

  Map<String, Object?> toJson() => {
    'ddsource': ddsource,
    'ddtags': ddtags,
    'message': message,
    'service': service,
    'hostname': hostname,
    ...extra,
  };
}

/// Convert camelCase to snake_case.
String _camelToSnakeCase(String str) {
  return str.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (m) => '_${m.group(0)!.toLowerCase()}',
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Datadog allowed events
// ═══════════════════════════════════════════════════════════════════════════

const _datadogAllowedEvents = <String>{
  'chrome_bridge_connection_succeeded',
  'chrome_bridge_connection_failed',
  'chrome_bridge_disconnected',
  'chrome_bridge_tool_call_completed',
  'chrome_bridge_tool_call_error',
  'chrome_bridge_tool_call_started',
  'chrome_bridge_tool_call_timeout',
  'tengu_api_error',
  'tengu_api_success',
  'tengu_brief_mode_enabled',
  'tengu_brief_mode_toggled',
  'tengu_brief_send',
  'tengu_cancel',
  'tengu_compact_failed',
  'tengu_exit',
  'tengu_flicker',
  'tengu_init',
  'tengu_model_fallback_triggered',
  'tengu_oauth_error',
  'tengu_oauth_success',
  'tengu_oauth_token_refresh_failure',
  'tengu_oauth_token_refresh_success',
  'tengu_oauth_token_refresh_lock_acquiring',
  'tengu_oauth_token_refresh_lock_acquired',
  'tengu_oauth_token_refresh_starting',
  'tengu_oauth_token_refresh_completed',
  'tengu_oauth_token_refresh_lock_releasing',
  'tengu_oauth_token_refresh_lock_released',
  'tengu_query_error',
  'tengu_session_file_read',
  'tengu_started',
  'tengu_tool_use_error',
  'tengu_tool_use_granted_in_prompt_permanent',
  'tengu_tool_use_granted_in_prompt_temporary',
  'tengu_tool_use_rejected_in_prompt',
  'tengu_tool_use_success',
  'tengu_uncaught_exception',
  'tengu_unhandled_rejection',
  'tengu_voice_recording_started',
  'tengu_voice_toggled',
  'tengu_team_mem_sync_pull',
  'tengu_team_mem_sync_push',
  'tengu_team_mem_sync_started',
  'tengu_team_mem_entries_capped',
};

/// Tag fields to include in Datadog log tags.
const _tagFields = <String>[
  'arch',
  'clientType',
  'errorType',
  'http_status_range',
  'http_status',
  'kairosActive',
  'model',
  'platform',
  'provider',
  'skillMode',
  'subscriptionType',
  'toolName',
  'userBucket',
  'userType',
  'version',
  'versionBase',
];

// ═══════════════════════════════════════════════════════════════════════════
// Datadog service
// ═══════════════════════════════════════════════════════════════════════════

const _datadogLogsEndpoint =
    'https://http-intake.logs.us5.datadoghq.com/api/v2/logs';
const _datadogClientToken = 'pubbbf48e6d78dae54bceaa4acf463299bf';
const _defaultFlushIntervalMs = 15000;
const _maxBatchSize = 100;
const _networkTimeoutMs = 5000;
const _numUserBuckets = 30;

/// Datadog event tracking service with batched log dispatch.
class DatadogService {
  final Future<EventMetadata> Function({Object? model, Object? betas})
  getEventMetadata;
  final String Function() getUserId;
  final String Function() getApiProvider;
  final String Function(String) getCanonicalModelName;
  final bool Function(String) isKnownModel;
  final bool Function() isAnalyticsDisabled;
  final Future<void> Function(
    String url,
    Object body,
    Map<String, String> headers,
  )
  httpPost;

  final List<DatadogLog> _logBatch = [];
  Timer? _flushTimer;
  bool _initialized = false;
  int? _cachedUserBucket;

  DatadogService({
    required this.getEventMetadata,
    required this.getUserId,
    required this.getApiProvider,
    required this.getCanonicalModelName,
    required this.isKnownModel,
    required this.isAnalyticsDisabled,
    required this.httpPost,
  });

  /// Initialise Datadog. Returns false if analytics is disabled.
  bool initialize() {
    if (isAnalyticsDisabled()) {
      _initialized = false;
      return false;
    }
    _initialized = true;
    return true;
  }

  /// Flush remaining logs and shut down.
  Future<void> shutdown() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flushLogs();
  }

  /// Get user bucket for cardinality reduction.
  int getUserBucket() {
    if (_cachedUserBucket != null) return _cachedUserBucket!;
    final userId = getUserId();
    final hash = sha256.convert(utf8.encode(userId)).toString();
    _cachedUserBucket =
        int.parse(hash.substring(0, 8), radix: 16) % _numUserBuckets;
    return _cachedUserBucket!;
  }

  /// Track a Datadog event.
  Future<void> trackEvent(
    String eventName,
    Map<String, Object?> properties,
  ) async {
    // Don't send for 3P providers.
    if (getApiProvider() != 'firstParty') return;
    if (!_initialized) {
      final ok = initialize();
      if (!ok) return;
    }
    if (!_datadogAllowedEvents.contains(eventName)) return;

    try {
      final metadata = await getEventMetadata(
        model: properties['model'],
        betas: properties['betas'],
      );
      final envCtx = metadata.envContext.toMap();
      final restMetadata = metadata.toMap()..remove('envContext');
      final allData = <String, Object?>{
        ...restMetadata,
        ...envCtx,
        ...properties,
        'userBucket': getUserBucket(),
      };

      // Normalise MCP tool names for cardinality reduction.
      if (allData['toolName'] is String &&
          (allData['toolName'] as String).startsWith('mcp__')) {
        allData['toolName'] = 'mcp';
      }

      // Normalise model names for cardinality reduction.
      if (allData['model'] is String) {
        final modelStr = (allData['model'] as String).replaceAll(
          RegExp(r'\[1m]$', caseSensitive: false),
          '',
        );
        final shortName = getCanonicalModelName(modelStr);
        allData['model'] = isKnownModel(shortName) ? shortName : 'other';
      }

      // Truncate dev version.
      if (allData['version'] is String) {
        allData['version'] = (allData['version'] as String).replaceFirstMapped(
          RegExp(r'^(\d+\.\d+\.\d+-dev\.\d{8})\.t\d+\.sha[a-f0-9]+$'),
          (m) => m.group(1)!,
        );
      }

      // Transform status to http_status.
      if (allData['status'] != null) {
        final statusCode = allData['status'].toString();
        allData['http_status'] = statusCode;
        final firstDigit = statusCode.isNotEmpty ? statusCode[0] : '';
        if (firstDigit.compareTo('1') >= 0 && firstDigit.compareTo('5') <= 0) {
          allData['http_status_range'] = '${firstDigit}xx';
        }
        allData.remove('status');
      }

      // Build ddtags.
      final tags = <String>[
        'event:$eventName',
        ..._tagFields
            .where((f) => allData[f] != null)
            .map((f) => '${_camelToSnakeCase(f)}:${allData[f]}'),
      ];

      final log = DatadogLog(
        ddsource: 'dart',
        ddtags: tags.join(','),
        message: eventName,
        service: 'neom-claw',
        hostname: 'neom-claw',
        extra: {
          for (final e in allData.entries)
            if (e.value != null) _camelToSnakeCase(e.key): e.value,
        },
      );

      _logBatch.add(log);

      if (_logBatch.length >= _maxBatchSize) {
        _flushTimer?.cancel();
        _flushTimer = null;
        unawaited(_flushLogs());
      } else {
        _scheduleFlush();
      }
    } catch (_) {
      // Swallow — analytics must not crash the app.
    }
  }

  void _scheduleFlush() {
    if (_flushTimer != null) return;
    _flushTimer = Timer(
      const Duration(milliseconds: _defaultFlushIntervalMs),
      () {
        _flushTimer = null;
        unawaited(_flushLogs());
      },
    );
  }

  Future<void> _flushLogs() async {
    if (_logBatch.isEmpty) return;
    final batch = List<DatadogLog>.from(_logBatch);
    _logBatch.clear();

    try {
      await httpPost(
        _datadogLogsEndpoint,
        batch.map((l) => l.toJson()).toList(),
        {'Content-Type': 'application/json', 'DD-API-KEY': _datadogClientToken},
      );
    } catch (_) {
      // Swallow network errors.
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// First-party event logging
// ═══════════════════════════════════════════════════════════════════════════

/// Batch configuration for the first-party event logger.
class FirstPartyBatchConfig {
  final int scheduledDelayMillis;
  final int maxExportBatchSize;
  final int maxQueueSize;
  final bool skipAuth;
  final int maxAttempts;
  final String? path;
  final String? baseUrl;

  const FirstPartyBatchConfig({
    this.scheduledDelayMillis = 10000,
    this.maxExportBatchSize = 200,
    this.maxQueueSize = 8192,
    this.skipAuth = false,
    this.maxAttempts = 8,
    this.path,
    this.baseUrl,
  });

  factory FirstPartyBatchConfig.fromJson(Map<String, dynamic> json) {
    return FirstPartyBatchConfig(
      scheduledDelayMillis: json['scheduledDelayMillis'] as int? ?? 10000,
      maxExportBatchSize: json['maxExportBatchSize'] as int? ?? 200,
      maxQueueSize: json['maxQueueSize'] as int? ?? 8192,
      skipAuth: json['skipAuth'] as bool? ?? false,
      maxAttempts: json['maxAttempts'] as int? ?? 8,
      path: json['path'] as String?,
      baseUrl: json['baseUrl'] as String?,
    );
  }
}

/// A first-party event ready for export.
class FirstPartyEvent {
  final String eventType;
  final Map<String, Object?> eventData;

  const FirstPartyEvent({required this.eventType, required this.eventData});

  Map<String, Object?> toJson() => {
    'event_type': eventType,
    'event_data': eventData,
  };
}

/// First-party event logging service with batched export and retry.
class FirstPartyEventLogger {
  final String endpoint;
  final int maxBatchSize;
  final int maxAttempts;
  final bool skipAuth;
  final int baseBackoffDelayMs;
  final int maxBackoffDelayMs;
  final bool Function() isKilled;
  final Future<Map<String, String>> Function() getAuthHeaders;
  final Future<void> Function(
    String url,
    Object body,
    Map<String, String> headers,
  )
  httpPost;
  final String Function() getUserAgent;

  final List<FirstPartyEvent> _pendingEvents = [];
  Timer? _flushTimer;
  int _attempts = 0;
  bool _isShutdown = false;

  FirstPartyEventLogger({
    required this.endpoint,
    this.maxBatchSize = 200,
    this.maxAttempts = 8,
    this.skipAuth = false,
    this.baseBackoffDelayMs = 500,
    this.maxBackoffDelayMs = 30000,
    required this.isKilled,
    required this.getAuthHeaders,
    required this.httpPost,
    required this.getUserAgent,
  });

  /// Enqueue an event for export.
  void logEvent(FirstPartyEvent event) {
    if (_isShutdown || isKilled()) return;
    _pendingEvents.add(event);

    if (_pendingEvents.length >= maxBatchSize) {
      _flushTimer?.cancel();
      _flushTimer = null;
      unawaited(_flush());
    } else {
      _scheduleFlush();
    }
  }

  void _scheduleFlush() {
    if (_flushTimer != null) return;
    _flushTimer = Timer(const Duration(seconds: 10), () {
      _flushTimer = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    if (_pendingEvents.isEmpty) return;
    if (_attempts >= maxAttempts) {
      _pendingEvents.clear();
      _attempts = 0;
      return;
    }

    final batch = _pendingEvents.take(maxBatchSize).toList();
    _pendingEvents.removeRange(0, batch.length);

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'User-Agent': getUserAgent(),
        'x-service-name': 'neom-claw',
      };

      if (!skipAuth) {
        final authHeaders = await getAuthHeaders();
        headers.addAll(authHeaders);
      }

      await httpPost(endpoint, {
        'events': batch.map((e) => e.toJson()).toList(),
      }, headers);

      _attempts = 0;
    } catch (_) {
      // Put failed events back for retry.
      _pendingEvents.insertAll(0, batch);
      _attempts++;
      _scheduleBackoff();
    }
  }

  void _scheduleBackoff() {
    final delay = min(
      baseBackoffDelayMs * _attempts * _attempts,
      maxBackoffDelayMs,
    );
    _flushTimer?.cancel();
    _flushTimer = Timer(Duration(milliseconds: delay), () {
      _flushTimer = null;
      unawaited(_flush());
    });
  }

  /// Flush and shut down.
  Future<void> shutdown() async {
    _isShutdown = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flush();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GrowthBook feature gating (simplified port)
// ═══════════════════════════════════════════════════════════════════════════

/// GrowthBook user attributes for targeting.
class GrowthBookUserAttributes {
  final String id;
  final String sessionId;
  final String deviceId;
  final String platform;
  final String? apiBaseUrlHost;
  final String? organizationUuid;
  final String? accountUuid;
  final String? userType;
  final String? subscriptionType;
  final String? rateLimitTier;
  final int? firstTokenTime;
  final String? email;
  final String? appVersion;

  const GrowthBookUserAttributes({
    required this.id,
    required this.sessionId,
    required this.deviceId,
    required this.platform,
    this.apiBaseUrlHost,
    this.organizationUuid,
    this.accountUuid,
    this.userType,
    this.subscriptionType,
    this.rateLimitTier,
    this.firstTokenTime,
    this.email,
    this.appVersion,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'sessionId': sessionId,
    'deviceID': deviceId,
    'platform': platform,
    'apiBaseUrlHost': apiBaseUrlHost,
    'organizationUUID': organizationUuid,
    'accountUUID': accountUuid,
    'userType': userType,
    'subscriptionType': subscriptionType,
    'rateLimitTier': rateLimitTier,
    'firstTokenTime': firstTokenTime,
    'email': email,
    'appVersion': appVersion,
  };
}

/// GrowthBook experiment data for logging.
class GrowthBookExperimentData {
  final String experimentId;
  final int variationId;
  final GrowthBookUserAttributes? userAttributes;
  final Map<String, Object?>? experimentMetadata;

  const GrowthBookExperimentData({
    required this.experimentId,
    required this.variationId,
    this.userAttributes,
    this.experimentMetadata,
  });
}

/// Simplified GrowthBook feature flag service.
///
/// In the TS original this uses the GrowthBook SDK with remote eval.
/// Here we provide an interface that reads from a cached config and
/// supports disk fallback.
class GrowthBookService extends SintController {
  /// In-memory cache of feature values from remote eval.
  final _featureValues = <String, Object?>{}.obs;

  /// Disk cache of feature values (fallback).
  final _diskCache = <String, Object?>{}.obs;

  /// Local config overrides (ant-only, dev tooling).
  final _configOverrides = <String, Object?>{}.obs;

  /// Env var overrides (eval harnesses).
  final _envOverrides = <String, Object?>{};

  /// Experiment data by feature key.
  final _experimentData = <String, GrowthBookExperimentData>{};

  /// Logged exposure dedup set.
  final _loggedExposures = <String>{};

  /// Refresh listeners.
  final _refreshListeners = <void Function()>[];

  /// Check if a feature gate is enabled (cached, may be stale).
  bool checkFeatureGateCached(String featureKey) {
    final value = _getFeatureValue(featureKey);
    return value == true;
  }

  /// Get a typed feature value (cached, may be stale).
  T getFeatureValueCached<T>(String featureKey, T defaultValue) {
    final value = _getFeatureValue(featureKey);
    if (value is T) return value;
    return defaultValue;
  }

  /// Get a dynamic config value (cached, may be stale).
  T getDynamicConfigCached<T>(String configKey, T defaultValue) {
    return getFeatureValueCached<T>(configKey, defaultValue);
  }

  /// Set a feature value (for testing or remote eval results).
  void setFeatureValue(String featureKey, Object? value) {
    _featureValues[featureKey] = value;
  }

  /// Set all feature values from a remote eval payload.
  void setAllFeatureValues(Map<String, Object?> values) {
    _featureValues.clear();
    _featureValues.addAll(values);
    _syncToDisk();
    _notifyRefresh();
  }

  /// Load disk cache.
  void loadDiskCache(Map<String, Object?> cache) {
    _diskCache.clear();
    _diskCache.addAll(cache);
  }

  /// Set env var overrides (typically from NEOMCLAW_INTERNAL_FC_OVERRIDES).
  void setEnvOverrides(Map<String, Object?> overrides) {
    _envOverrides.clear();
    _envOverrides.addAll(overrides);
  }

  /// Set or clear a single config override.
  void setConfigOverride(String feature, Object? value) {
    if (value == null) {
      _configOverrides.remove(feature);
    } else {
      _configOverrides[feature] = value;
    }
    _notifyRefresh();
  }

  /// Clear all config overrides.
  void clearConfigOverrides() {
    _configOverrides.clear();
    _notifyRefresh();
  }

  /// Get all known features and their current values.
  Map<String, Object?> getAllFeatures() {
    if (_featureValues.isNotEmpty) {
      return Map<String, Object?>.from(_featureValues);
    }
    return Map<String, Object?>.from(_diskCache);
  }

  /// Register a refresh listener. Returns an unsubscribe function.
  void Function() onRefresh(void Function() listener) {
    _refreshListeners.add(listener);
    // Catch-up if we already have values.
    if (_featureValues.isNotEmpty) {
      Future.microtask(listener);
    }
    return () => _refreshListeners.remove(listener);
  }

  /// Check if a feature has an env override.
  bool hasEnvOverride(String feature) {
    return _envOverrides.containsKey(feature);
  }

  /// Get experiment data for a feature (for exposure logging).
  GrowthBookExperimentData? getExperimentData(String feature) {
    return _experimentData[feature];
  }

  /// Store experiment data for a feature.
  void setExperimentData(String feature, GrowthBookExperimentData data) {
    _experimentData[feature] = data;
  }

  /// Log exposure for a feature (deduped within session).
  void logExposure(
    String feature,
    void Function(GrowthBookExperimentData) logger,
  ) {
    if (_loggedExposures.contains(feature)) return;
    final data = _experimentData[feature];
    if (data != null) {
      _loggedExposures.add(feature);
      logger(data);
    }
  }

  // ── Private ─────────────────────────────────────────────────────────

  Object? _getFeatureValue(String featureKey) {
    // Priority: env overrides > config overrides > remote eval > disk cache.
    if (_envOverrides.containsKey(featureKey)) {
      return _envOverrides[featureKey];
    }
    if (_configOverrides.containsKey(featureKey)) {
      return _configOverrides[featureKey];
    }
    if (_featureValues.containsKey(featureKey)) {
      return _featureValues[featureKey];
    }
    if (_diskCache.containsKey(featureKey)) {
      return _diskCache[featureKey];
    }
    return null;
  }

  void _syncToDisk() {
    // Wholesale replace disk cache with current remote values.
    _diskCache.clear();
    _diskCache.addAll(_featureValues);
  }

  void _notifyRefresh() {
    for (final listener in _refreshListeners) {
      try {
        listener();
      } catch (_) {
        // Swallow listener errors.
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Main analytics controller
// ═══════════════════════════════════════════════════════════════════════════

/// Main analytics controller that queues events until a sink is attached,
/// then drains the queue and routes all future events through the sink.
class AnalyticsController extends SintController {
  /// Whether a sink has been attached.
  final _hasSink = false.obs;

  /// Event queue for events logged before sink is attached.
  final _eventQueue = <_QueuedEvent>[].obs;

  /// The attached sink.
  AnalyticsSink? _sink;

  /// Datadog gate state.
  final isDatadogGateEnabled = Rxn<bool>();

  /// Sampling config.
  EventSamplingConfig _samplingConfig = {};

  /// Sink killswitch.
  SinkKillswitch? _killswitch;

  /// Set the sampling config.
  void setSamplingConfig(EventSamplingConfig config) {
    _samplingConfig = config;
  }

  /// Set the sink killswitch.
  void setKillswitch(SinkKillswitch killswitch) {
    _killswitch = killswitch;
  }

  /// Attach the analytics sink.
  ///
  /// Queued events are drained asynchronously to avoid blocking startup.
  /// Idempotent: if a sink is already attached, this is a no-op.
  void attachSink(AnalyticsSink newSink) {
    if (_sink != null) return;
    _sink = newSink;
    _hasSink.value = true;

    if (_eventQueue.isNotEmpty) {
      final queuedEvents = List<_QueuedEvent>.from(_eventQueue);
      _eventQueue.clear();

      Future.microtask(() {
        for (final event in queuedEvents) {
          if (event.isAsync) {
            _sink!.logEventAsync(event.eventName, event.metadata);
          } else {
            _sink!.logEvent(event.eventName, event.metadata);
          }
        }
      });
    }
  }

  /// Log an event (synchronous).
  ///
  /// If no sink is attached, events are queued and drained when the sink attaches.
  void logEvent(String eventName, LogEventMetadata metadata) {
    // Check sampling.
    final sampleResult = shouldSampleEvent(eventName, _samplingConfig);
    if (sampleResult != null && sampleResult == 0) return;

    final metadataWithRate = sampleResult != null && sampleResult > 0
        ? {...metadata, 'sample_rate': sampleResult}
        : metadata;

    if (_sink == null) {
      _eventQueue.add(
        _QueuedEvent(
          eventName: eventName,
          metadata: metadataWithRate,
          isAsync: false,
        ),
      );
      return;
    }

    // Strip _PROTO_* before Datadog (general-access).
    _sink!.logEvent(eventName, metadataWithRate);
  }

  /// Log an event (asynchronous).
  Future<void> logEventAsync(
    String eventName,
    LogEventMetadata metadata,
  ) async {
    final sampleResult = shouldSampleEvent(eventName, _samplingConfig);
    if (sampleResult != null && sampleResult == 0) return;

    final metadataWithRate = sampleResult != null && sampleResult > 0
        ? {...metadata, 'sample_rate': sampleResult}
        : metadata;

    if (_sink == null) {
      _eventQueue.add(
        _QueuedEvent(
          eventName: eventName,
          metadata: metadataWithRate,
          isAsync: true,
        ),
      );
      return;
    }

    await _sink!.logEventAsync(eventName, metadataWithRate);
  }

  /// Reset analytics state (for testing).
  void resetForTesting() {
    _sink = null;
    _hasSink.value = false;
    _eventQueue.clear();
  }

  /// Whether Datadog tracking should be enabled.
  bool shouldTrackDatadog() {
    if (_killswitch?.isSinkKilled(SinkName.datadog) == true) return false;
    if (isDatadogGateEnabled.value != null) return isDatadogGateEnabled.value!;
    return false;
  }

  /// Initialize analytics gates during startup.
  void initializeGates(bool datadogGateEnabled) {
    isDatadogGateEnabled.value = datadogGateEnabled;
  }
}

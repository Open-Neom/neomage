/// Feature gating and authorization utilities.
///
/// Provides plan-based feature access control, allowing features to be
/// enabled or disabled per organization plan tier. Gates can be loaded
/// from a remote endpoint or persisted locally.
library;

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';

/// Available feature gates that can be toggled per plan or organization.
enum FeatureGate {
  betaFeatures,
  experimentalTools,
  mcpServers,
  agentMode,
  voiceInput,
  remoteSessions,
  customThemes,
  pluginSystem,
  teamSync,
  advancedAnalytics,
}

/// Subscription plan tiers.
enum Plan { free, pro, team, enterprise }

/// Result of checking access to a feature gate.
class AccessResult {
  /// Whether access is allowed.
  final bool allowed;

  /// Human-readable reason for the access decision.
  final String reason;

  /// URL to upgrade if access is denied due to plan limitations.
  final String? upgradeUrl;

  const AccessResult({
    required this.allowed,
    required this.reason,
    this.upgradeUrl,
  });

  @override
  String toString() => 'AccessResult(allowed: $allowed, reason: $reason)';
}

/// Snapshot of evaluated feature gate configuration.
class FeatureGateConfig {
  /// Map of each gate to its enabled/disabled state.
  final Map<FeatureGate, bool> gates;

  /// Organization identifier, if applicable.
  final String? organizationId;

  /// The plan tier this config was evaluated for.
  final Plan plan;

  /// When this configuration was evaluated.
  final DateTime evaluatedAt;

  const FeatureGateConfig({
    required this.gates,
    this.organizationId,
    required this.plan,
    required this.evaluatedAt,
  });

  /// Whether a specific gate is enabled in this config.
  bool isEnabled(FeatureGate gate) => gates[gate] ?? false;

  /// Returns all gates that are enabled.
  Set<FeatureGate> get enabledGates =>
      gates.entries.where((e) => e.value).map((e) => e.key).toSet();

  /// Serializes the config to a JSON-encodable map.
  Map<String, dynamic> toJson() => {
    'gates': gates.map((k, v) => MapEntry(k.name, v)),
    'organizationId': organizationId,
    'plan': plan.name,
    'evaluatedAt': evaluatedAt.toIso8601String(),
  };

  /// Deserializes a config from a JSON map.
  factory FeatureGateConfig.fromJson(Map<String, dynamic> json) {
    final gateMap = <FeatureGate, bool>{};
    final rawGates = json['gates'] as Map<String, dynamic>? ?? {};
    for (final entry in rawGates.entries) {
      final gate = FeatureGate.values.where((g) => g.name == entry.key);
      if (gate.isNotEmpty) {
        gateMap[gate.first] = entry.value as bool;
      }
    }
    return FeatureGateConfig(
      gates: gateMap,
      organizationId: json['organizationId'] as String?,
      plan: Plan.values.firstWhere(
        (p) => p.name == json['plan'],
        orElse: () => Plan.free,
      ),
      evaluatedAt: DateTime.parse(json['evaluatedAt'] as String),
    );
  }
}

/// Default gate configurations for each plan tier.
const Map<Plan, Set<FeatureGate>> _planDefaults = {
  Plan.free: {FeatureGate.mcpServers},
  Plan.pro: {
    FeatureGate.mcpServers,
    FeatureGate.betaFeatures,
    FeatureGate.agentMode,
    FeatureGate.customThemes,
    FeatureGate.voiceInput,
  },
  Plan.team: {
    FeatureGate.mcpServers,
    FeatureGate.betaFeatures,
    FeatureGate.agentMode,
    FeatureGate.customThemes,
    FeatureGate.voiceInput,
    FeatureGate.teamSync,
    FeatureGate.pluginSystem,
    FeatureGate.advancedAnalytics,
  },
  Plan.enterprise: {
    FeatureGate.betaFeatures,
    FeatureGate.experimentalTools,
    FeatureGate.mcpServers,
    FeatureGate.agentMode,
    FeatureGate.voiceInput,
    FeatureGate.remoteSessions,
    FeatureGate.customThemes,
    FeatureGate.pluginSystem,
    FeatureGate.teamSync,
    FeatureGate.advancedAnalytics,
  },
};

/// Upgrade URLs per plan tier.
const Map<Plan, String> _upgradeUrls = {
  Plan.free: 'https://neomage.ai/upgrade?plan=pro',
  Plan.pro: 'https://neomage.ai/upgrade?plan=team',
  Plan.team: 'https://neomage.ai/upgrade?plan=enterprise',
  Plan.enterprise: '',
};

/// Exception thrown when a required feature gate is not enabled.
class FeatureGateException implements Exception {
  final FeatureGate gate;
  final String message;

  const FeatureGateException(this.gate, this.message);

  @override
  String toString() => 'FeatureGateException($gate): $message';
}

/// Service for managing feature gate state and access control.
///
/// Gates can be loaded from a remote API endpoint, read from a local
/// config file, or evaluated based on the current plan tier. Local
/// overrides take precedence over plan defaults.
class FeatureGateService {
  final Map<FeatureGate, bool> _gates = {};
  final Map<FeatureGate, bool> _overrides = {};
  Plan _plan;
  String? _organizationId;
  final String? _configPath;

  final StreamController<(FeatureGate, bool)> _changeController =
      StreamController.broadcast();

  /// Creates a new feature gate service.
  ///
  /// [plan] sets the initial plan tier for default gate evaluation.
  /// [configPath] is the path to the local config file for persistence.
  /// [organizationId] is an optional organization identifier.
  FeatureGateService({
    Plan plan = Plan.free,
    String? configPath,
    String? organizationId,
  }) : _plan = plan,
       _configPath = configPath,
       _organizationId = organizationId {
    _applyPlanDefaults();
  }

  /// Stream of gate change events as (gate, newValue) tuples.
  Stream<(FeatureGate, bool)> get onGateChanged => _changeController.stream;

  /// The current plan tier.
  Plan get plan => _plan;

  /// The current organization identifier.
  String? get organizationId => _organizationId;

  /// Returns whether [gate] is currently enabled.
  bool isEnabled(FeatureGate gate) {
    if (_overrides.containsKey(gate)) return _overrides[gate]!;
    return _gates[gate] ?? false;
  }

  /// Enables [gate] as a local override.
  void enableGate(FeatureGate gate) {
    _overrides[gate] = true;
    _changeController.add((gate, true));
  }

  /// Disables [gate] as a local override.
  void disableGate(FeatureGate gate) {
    _overrides[gate] = false;
    _changeController.add((gate, false));
  }

  /// Returns the set of all currently enabled gates.
  Set<FeatureGate> getEnabledGates() {
    return FeatureGate.values.where(isEnabled).toSet();
  }

  /// Evaluates which gates should be enabled for [plan] and returns a
  /// [FeatureGateConfig] snapshot.
  FeatureGateConfig evaluateForPlan(Plan plan) {
    final defaults = _planDefaults[plan] ?? {};
    final gateMap = <FeatureGate, bool>{};
    for (final gate in FeatureGate.values) {
      gateMap[gate] = defaults.contains(gate);
    }
    return FeatureGateConfig(
      gates: gateMap,
      organizationId: _organizationId,
      plan: plan,
      evaluatedAt: DateTime.now(),
    );
  }

  /// Checks whether access to [gate] is allowed under the current config.
  ///
  /// Returns an [AccessResult] with the decision and reason.
  AccessResult checkAccess(FeatureGate gate) {
    if (isEnabled(gate)) {
      return AccessResult(
        allowed: true,
        reason: '${gate.name} is enabled for the ${_plan.name} plan.',
      );
    }
    final upgradeUrl = _upgradeUrls[_plan];
    return AccessResult(
      allowed: false,
      reason: '${gate.name} is not available on the ${_plan.name} plan.',
      upgradeUrl: (upgradeUrl != null && upgradeUrl.isNotEmpty)
          ? upgradeUrl
          : null,
    );
  }

  /// Throws a [FeatureGateException] if [gate] is not enabled.
  ///
  /// Use this to guard code paths that require a specific gate.
  void requireGate(FeatureGate gate, {String? message}) {
    if (!isEnabled(gate)) {
      throw FeatureGateException(
        gate,
        message ?? '${gate.name} is required but not enabled.',
      );
    }
  }

  /// Loads gate configuration from a remote [endpoint] via HTTP GET.
  ///
  /// Expects a JSON response matching [FeatureGateConfig.fromJson] format.
  Future<FeatureGateConfig> loadFromRemote(String endpoint) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(endpoint));
      if (_organizationId != null) {
        request.headers.set('X-Organization-Id', _organizationId!);
      }
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to load feature gates: HTTP ${response.statusCode}',
        );
      }
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final config = FeatureGateConfig.fromJson(json);
      _applyConfig(config);
      return config;
    } finally {
      client.close();
    }
  }

  /// Loads gate overrides from the local config file.
  ///
  /// Returns the loaded config, or evaluates a fresh one if no file exists.
  Future<FeatureGateConfig> loadFromLocal() async {
    if (_configPath == null) {
      return evaluateForPlan(_plan);
    }
    final file = File(_configPath);
    if (!await file.exists()) {
      return evaluateForPlan(_plan);
    }
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final config = FeatureGateConfig.fromJson(json);
    _applyConfig(config);
    return config;
  }

  /// Persists the current gate overrides to the local config file.
  Future<void> saveToLocal() async {
    if (_configPath == null) return;
    final config = FeatureGateConfig(
      gates: {for (final gate in FeatureGate.values) gate: isEnabled(gate)},
      organizationId: _organizationId,
      plan: _plan,
      evaluatedAt: DateTime.now(),
    );
    final file = File(_configPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }

  /// Disposes the service and closes the change stream.
  void dispose() {
    _changeController.close();
  }

  // -- Private helpers --

  void _applyPlanDefaults() {
    final defaults = _planDefaults[_plan] ?? {};
    for (final gate in FeatureGate.values) {
      _gates[gate] = defaults.contains(gate);
    }
  }

  void _applyConfig(FeatureGateConfig config) {
    _plan = config.plan;
    _organizationId = config.organizationId;
    for (final entry in config.gates.entries) {
      _gates[entry.key] = entry.value;
    }
  }
}

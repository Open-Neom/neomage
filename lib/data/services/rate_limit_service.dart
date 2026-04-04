// Rate limit / policy limits service — port of neom_claw/src/services/policyLimits.
// Fetches and caches organization-level policy restrictions.

import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:http/http.dart' as http;

/// A policy restriction.
class PolicyLimit {
  final String name;
  final bool allowed;
  const PolicyLimit({required this.name, required this.allowed});
}

/// Rate limit service — manages policy limits and rate tracking.
class RateLimitService {
  final String? apiKey;
  final String? oauthToken;
  final String baseUrl;
  final String cacheDir;

  Map<String, PolicyLimit>? _policies;
  DateTime? _lastFetch;

  RateLimitService({
    this.apiKey,
    this.oauthToken,
    required this.baseUrl,
    required this.cacheDir,
  });

  /// Whether a policy is allowed. Defaults to true if unknown.
  bool isPolicyAllowed(String policy) {
    final limit = _policies?[policy];
    return limit?.allowed ?? true;
  }

  /// Load policy limits (from cache first, then remote).
  Future<void> loadPolicies() async {
    // Try cache first
    final cached = await _loadFromCache();
    if (cached != null) {
      _policies = cached;
    }

    // Fetch from remote (non-blocking)
    try {
      final remote = await _fetchRemote();
      if (remote != null) {
        _policies = remote;
        _lastFetch = DateTime.now();
        await _saveToCache(remote);
      }
    } catch (_) {
      // Fail-open: use cached or allow all
    }
  }

  /// Force refresh from remote.
  Future<void> refresh() async {
    try {
      final remote = await _fetchRemote();
      if (remote != null) {
        _policies = remote;
        _lastFetch = DateTime.now();
        await _saveToCache(remote);
      }
    } catch (_) {
      // Fail-open
    }
  }

  /// Whether policies have been loaded.
  bool get isLoaded => _policies != null;

  /// Last fetch timestamp.
  DateTime? get lastFetch => _lastFetch;

  // ── Private ──

  String get _cachePath => '$cacheDir/policy-limits.json';

  Future<Map<String, PolicyLimit>?> _loadFromCache() async {
    try {
      final file = File(_cachePath);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      return _parsePolicies(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToCache(Map<String, PolicyLimit> policies) async {
    try {
      final file = File(_cachePath);
      await file.parent.create(recursive: true);
      final json = <String, dynamic>{};
      for (final entry in policies.entries) {
        json[entry.key] = {'allowed': entry.value.allowed};
      }
      await file.writeAsString(jsonEncode(json));
    } catch (_) {
      // Non-critical
    }
  }

  Future<Map<String, PolicyLimit>?> _fetchRemote() async {
    final auth = apiKey ?? oauthToken;
    if (auth == null) return null;

    final uri = Uri.parse('$baseUrl/api/neomclaw/policy_limits');
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (apiKey != null) {
      headers['x-api-key'] = apiKey!;
    } else if (oauthToken != null) {
      headers['Authorization'] = 'Bearer $oauthToken';
    }

    final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 10),
        );

    if (response.statusCode == 304) {
      return _policies; // No change
    }
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body);
    return _parsePolicies(json as Map<String, dynamic>);
  }

  Map<String, PolicyLimit> _parsePolicies(Map<String, dynamic> json) {
    final result = <String, PolicyLimit>{};
    for (final entry in json.entries) {
      if (entry.value is Map) {
        final map = entry.value as Map<String, dynamic>;
        result[entry.key] = PolicyLimit(
          name: entry.key,
          allowed: map['allowed'] as bool? ?? true,
        );
      }
    }
    return result;
  }
}

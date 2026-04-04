// Remote managed settings service — port of
// neom_claw/src/services/remoteManagedSettings/.
// Fetches, caches, and merges remote configuration with local overrides.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

// ── Enums ──────────────────────────────────────────────────────────────────

/// Where a remote setting originates.
enum RemoteSettingsSource {
  /// Default settings published by Anthropic.
  anthropic,

  /// User-specified custom endpoint.
  custom,

  /// Organisation-level settings (managed fleet).
  organization,
}

// ── Data classes ───────────────────────────────────────────────────────────

/// A single remote setting entry.
class RemoteSetting {
  final String key;
  final dynamic value;
  final RemoteSettingsSource source;
  final DateTime lastFetched;
  final DateTime? expiresAt;
  final bool overridable;

  const RemoteSetting({
    required this.key,
    required this.value,
    required this.source,
    required this.lastFetched,
    this.expiresAt,
    this.overridable = true,
  });

  /// Whether the cached value has expired.
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'source': source.name,
        'lastFetched': lastFetched.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        'overridable': overridable,
      };

  factory RemoteSetting.fromJson(Map<String, dynamic> json) {
    return RemoteSetting(
      key: json['key'] as String,
      value: json['value'],
      source: RemoteSettingsSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => RemoteSettingsSource.custom,
      ),
      lastFetched: DateTime.parse(json['lastFetched'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      overridable: json['overridable'] as bool? ?? true,
    );
  }
}

/// Resolved value with source information.
class SettingValue {
  /// The effective value after considering remote + local override.
  final dynamic value;

  /// Where the effective value came from.
  final SettingValueSource source;

  /// The remote value (may differ from [value] if locally overridden).
  final dynamic remoteValue;

  /// The local override value, if any.
  final dynamic localOverride;

  const SettingValue({
    required this.value,
    required this.source,
    this.remoteValue,
    this.localOverride,
  });
}

/// Describes where the effective setting value came from.
enum SettingValueSource {
  /// Value comes from remote settings.
  remote,

  /// Value comes from a local override.
  localOverride,

  /// Value comes from a hardcoded default (not found remotely or locally).
  defaultValue,
}

/// Result of comparing a remote setting against its local counterpart.
class RemoteVsLocal {
  final String key;
  final dynamic remoteValue;
  final dynamic localValue;
  final bool isOverridden;
  final bool isRemoteOnly;
  final bool isLocalOnly;

  const RemoteVsLocal({
    required this.key,
    this.remoteValue,
    this.localValue,
    this.isOverridden = false,
    this.isRemoteOnly = false,
    this.isLocalOnly = false,
  });
}

/// Configuration for the remote settings service.
class RemoteSettingsConfig {
  /// HTTP endpoint that returns the settings JSON payload.
  final String endpoint;

  /// How often to auto-refresh.
  final Duration refreshInterval;

  /// If `true`, fall back to locally cached settings when the endpoint is
  /// unreachable.
  final bool fallbackToLocal;

  /// Directory for the on-disk cache file.
  final String cacheDir;

  const RemoteSettingsConfig({
    required this.endpoint,
    this.refreshInterval = const Duration(minutes: 30),
    this.fallbackToLocal = true,
    required this.cacheDir,
  });
}

// ── Service ────────────────────────────────────────────────────────────────

/// Manages remote settings: fetching, caching, local overrides, and
/// change notification.
class RemoteSettingsService {
  final RemoteSettingsConfig config;

  /// In-memory cache of remote settings keyed by setting key.
  final Map<String, RemoteSetting> _remote = {};

  /// Local overrides keyed by setting key.
  final Map<String, dynamic> _overrides = {};

  /// Change stream.
  final _changesController =
      StreamController<Map<String, RemoteSetting>>.broadcast();

  Timer? _refreshTimer;
  HttpClient? _httpClient;

  RemoteSettingsService({required this.config});

  /// Stream that fires whenever the remote settings change after a fetch.
  Stream<Map<String, RemoteSetting>> get onSettingsChanged =>
      _changesController.stream;

  // ── Fetch ─────────────────────────────────────────────────────────────

  /// Fetch settings from the remote endpoint.
  ///
  /// If [force] is `true` the local cache is ignored and a fresh request is
  /// made.  Returns the full map of remote settings.
  Future<Map<String, RemoteSetting>> fetchSettings({
    bool force = false,
  }) async {
    if (!force && _remote.isNotEmpty && !_hasExpired()) {
      return Map.unmodifiable(_remote);
    }

    try {
      _httpClient ??= HttpClient();
      final request =
          await _httpClient!.getUrl(Uri.parse(config.endpoint));
      final response = await request.close();

      if (response.statusCode != 200) {
        if (config.fallbackToLocal) return _loadFromCache();
        throw RemoteSettingsException(
          'Fetch failed with status ${response.statusCode}',
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = json.decode(body) as Map<String, dynamic>;
      _applyPayload(decoded);
      await _saveToCache();
      _changesController.add(Map.unmodifiable(_remote));
      return Map.unmodifiable(_remote);
    } on SocketException {
      if (config.fallbackToLocal) return _loadFromCache();
      rethrow;
    }
  }

  // ── Getters ───────────────────────────────────────────────────────────

  /// Get a typed setting value.  Returns `null` if not found.
  T? get<T>(String key) {
    // Local override takes precedence.
    if (_overrides.containsKey(key)) {
      final v = _overrides[key];
      return v is T ? v : null;
    }
    final remote = _remote[key];
    if (remote == null) return null;
    final v = remote.value;
    return v is T ? v : null;
  }

  /// Whether [key] has a local override.
  bool isOverridden(String key) => _overrides.containsKey(key);

  /// Get the effective value with full source information.
  SettingValue getEffective(String key) {
    final remote = _remote[key];
    final localVal = _overrides[key];

    if (localVal != null) {
      return SettingValue(
        value: localVal,
        source: SettingValueSource.localOverride,
        remoteValue: remote?.value,
        localOverride: localVal,
      );
    }

    if (remote != null) {
      return SettingValue(
        value: remote.value,
        source: SettingValueSource.remote,
        remoteValue: remote.value,
      );
    }

    return const SettingValue(
      value: null,
      source: SettingValueSource.defaultValue,
    );
  }

  // ── Overrides ─────────────────────────────────────────────────────────

  /// Set a local override for [key].  The override takes precedence over the
  /// remote value until removed.
  void setLocalOverride(String key, dynamic value) {
    _overrides[key] = value;
  }

  /// Remove a local override, reverting to the remote value.
  void removeLocalOverride(String key) {
    _overrides.remove(key);
  }

  // ── Auto-refresh ──────────────────────────────────────────────────────

  /// Start periodic background refresh.
  void startAutoRefresh([Duration? interval]) {
    stopAutoRefresh();
    final dur = interval ?? config.refreshInterval;
    _refreshTimer = Timer.periodic(dur, (_) => fetchSettings(force: true));
  }

  /// Stop periodic refresh.
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  // ── Cache ─────────────────────────────────────────────────────────────

  /// Clear the in-memory and on-disk cache.
  Future<void> clearCache() async {
    _remote.clear();
    final file = File(_cachePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  // ── Apply & merge ─────────────────────────────────────────────────────

  /// Merge a map of settings into the local config (e.g. from a push
  /// notification).
  void applySettings(Map<String, RemoteSetting> settings) {
    _remote.addAll(settings);
    _changesController.add(Map.unmodifiable(_remote));
  }

  // ── Diff ──────────────────────────────────────────────────────────────

  /// Compare remote settings against local overrides.
  List<RemoteVsLocal> diff() {
    final allKeys = <String>{..._remote.keys, ..._overrides.keys};
    return allKeys.map((key) {
      final remote = _remote[key];
      final local = _overrides[key];
      return RemoteVsLocal(
        key: key,
        remoteValue: remote?.value,
        localValue: local,
        isOverridden: local != null && remote != null,
        isRemoteOnly: remote != null && local == null,
        isLocalOnly: remote == null && local != null,
      );
    }).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  // ── Export ─────────────────────────────────────────────────────────────

  /// Export all effective (resolved) settings as a flat map.
  Map<String, dynamic> exportEffective() {
    final allKeys = <String>{..._remote.keys, ..._overrides.keys};
    return {
      for (final key in allKeys) key: getEffective(key).value,
    };
  }

  // ── Cleanup ───────────────────────────────────────────────────────────

  /// Release resources.
  void dispose() {
    stopAutoRefresh();
    _httpClient?.close();
    _changesController.close();
  }

  // ── Private ───────────────────────────────────────────────────────────

  String get _cachePath => '${config.cacheDir}/remote_settings_cache.json';

  bool _hasExpired() {
    return _remote.values.any((s) => s.isExpired);
  }

  void _applyPayload(Map<String, dynamic> payload) {
    final now = DateTime.now();
    final expiry = now.add(config.refreshInterval);

    _remote.clear();
    for (final entry in payload.entries) {
      final value = entry.value;
      final overridable = value is Map && value['overridable'] == false
          ? false
          : true;
      final actualValue =
          value is Map && value.containsKey('value') ? value['value'] : value;

      _remote[entry.key] = RemoteSetting(
        key: entry.key,
        value: actualValue,
        source: RemoteSettingsSource.anthropic,
        lastFetched: now,
        expiresAt: expiry,
        overridable: overridable,
      );
    }
  }

  Future<void> _saveToCache() async {
    try {
      final dir = Directory(config.cacheDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final data = {
        for (final e in _remote.entries) e.key: e.value.toJson(),
      };
      await File(_cachePath).writeAsString(json.encode(data));
    } catch (_) {
      // Best-effort caching — do not crash if disk write fails.
    }
  }

  Future<Map<String, RemoteSetting>> _loadFromCache() async {
    try {
      final file = File(_cachePath);
      if (!await file.exists()) return {};

      final raw = await file.readAsString();
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _remote.clear();
      for (final entry in decoded.entries) {
        _remote[entry.key] = RemoteSetting.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
      return Map.unmodifiable(_remote);
    } catch (_) {
      return {};
    }
  }
}

// ── Exceptions ─────────────────────────────────────────────────────────────

/// Thrown when the remote settings endpoint returns an error.
class RemoteSettingsException implements Exception {
  final String message;
  const RemoteSettingsException(this.message);

  @override
  String toString() => 'RemoteSettingsException: $message';
}

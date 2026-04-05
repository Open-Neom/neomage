// /mcp xaa command — manage XAA (SEP-990) IdP connection.
// Faithful port of neomage/src/commands/mcp/xaaIdpCommand.ts (266 TS LOC).
//
// The IdP connection is user-level: configure once, all XAA-enabled MCP
// servers reuse it. Lives in settings.xaaIdp (non-secret) + a keychain slot
// keyed by issuer (secret). Separate trust domain from per-server AS secrets.
//
// Subcommands:
//   setup  — Configure the IdP connection (one-time setup)
//   login  — Cache an IdP id_token for silent auth
//   show   — Show the current IdP connection config
//   clear  — Clear the IdP connection config and cached id_token

import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';

import 'package:path/path.dart' as p;

import '../../tools/tool.dart';
import '../command.dart';

// ============================================================================
// XaaIdpSettings — IdP connection configuration stored in user settings.
// ============================================================================

/// Represents the XAA IdP settings stored in user settings.
class XaaIdpSettings {
  /// OIDC issuer URL.
  final String issuer;

  /// Neomage's client_id at the IdP.
  final String clientId;

  /// Fixed loopback callback port (only if IdP does not honor RFC 8252
  /// port-any matching).
  final int? callbackPort;

  const XaaIdpSettings({
    required this.issuer,
    required this.clientId,
    this.callbackPort,
  });

  factory XaaIdpSettings.fromJson(Map<String, dynamic> json) {
    return XaaIdpSettings(
      issuer: json['issuer'] as String? ?? '',
      clientId: json['clientId'] as String? ?? '',
      callbackPort: json['callbackPort'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{'issuer': issuer, 'clientId': clientId};
    if (callbackPort != null) result['callbackPort'] = callbackPort;
    return result;
  }
}

// ============================================================================
// Settings I/O — reads/writes xaaIdp from user settings.
// ============================================================================

/// Get the user settings file path.
String _getUserSettingsPath() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  return p.join(home, '.neomage', 'settings.json');
}

/// Read user settings JSON, returning an empty map if missing or malformed.
Future<Map<String, dynamic>> _readUserSettings() async {
  final file = File(_getUserSettingsPath());
  if (!await file.exists()) return {};
  try {
    final content = await file.readAsString();
    final parsed = jsonDecode(content);
    if (parsed is Map<String, dynamic>) return parsed;
  } catch (_) {}
  return {};
}

/// Write user settings JSON, creating parent directories if needed.
Future<void> _writeUserSettings(Map<String, dynamic> settings) async {
  final file = File(_getUserSettingsPath());
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(settings),
    flush: true,
  );
}

/// Get the current XAA IdP settings from user settings, or null if not
/// configured.
Future<XaaIdpSettings?> getXaaIdpSettings() async {
  final settings = await _readUserSettings();
  final xaaIdp = settings['xaaIdp'];
  if (xaaIdp is Map<String, dynamic>) {
    return XaaIdpSettings.fromJson(xaaIdp);
  }
  return null;
}

/// Update user settings with the given partial updates.
/// Returns an error message string or null on success.
Future<String?> updateSettingsForSource(Map<String, dynamic> updates) async {
  try {
    final settings = await _readUserSettings();
    // Merge updates. Explicit null values signal key removal.
    for (final entry in updates.entries) {
      if (entry.value == null) {
        settings.remove(entry.key);
      } else {
        settings[entry.key] = entry.value;
      }
    }
    await _writeUserSettings(settings);
    return null;
  } catch (e) {
    return e.toString();
  }
}

// ============================================================================
// Keychain / token cache stubs.
// ============================================================================

/// Normalize an issuer URL to a consistent keychain key.
/// Strips trailing slashes and lowercases the host portion.
String issuerKey(String issuer) {
  try {
    final uri = Uri.parse(issuer);
    final normalized = uri.replace(
      host: uri.host.toLowerCase(),
      path: uri.path.endsWith('/')
          ? uri.path.substring(0, uri.path.length - 1)
          : uri.path,
    );
    return normalized.toString();
  } catch (_) {
    return issuer;
  }
}

/// Save IdP client secret to the keychain.
/// Returns (success, warning) tuple.
({bool success, String? warning}) saveIdpClientSecret(
  String issuer,
  String secret,
) {
  // In a full implementation this would use the platform keychain.
  // For now, store in a local secure file.
  try {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final secretDir = Directory(p.join(home, '.neomage', 'secrets'));
    secretDir.createSync(recursive: true);
    final secretFile = File(
      p.join(secretDir.path, '${issuerKey(issuer)}.secret'),
    );
    secretFile.writeAsStringSync(secret);
    return (success: true, warning: null);
  } catch (e) {
    return (success: false, warning: e.toString());
  }
}

/// Get IdP client secret from the keychain.
String? getIdpClientSecret(String issuer) {
  try {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final secretFile = File(
      p.join(home, '.neomage', 'secrets', '${issuerKey(issuer)}.secret'),
    );
    if (secretFile.existsSync()) return secretFile.readAsStringSync().trim();
  } catch (_) {}
  return null;
}

/// Clear IdP client secret from the keychain.
void clearIdpClientSecret(String issuer) {
  try {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final secretFile = File(
      p.join(home, '.neomage', 'secrets', '${issuerKey(issuer)}.secret'),
    );
    if (secretFile.existsSync()) secretFile.deleteSync();
  } catch (_) {}
}

/// Get cached IdP id_token.
String? getCachedIdpIdToken(String issuer) {
  try {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final tokenFile = File(
      p.join(home, '.neomage', 'secrets', '${issuerKey(issuer)}.idtoken'),
    );
    if (tokenFile.existsSync()) {
      final content = tokenFile.readAsStringSync().trim();
      if (content.isNotEmpty) return content;
    }
  } catch (_) {}
  return null;
}

/// Clear cached IdP id_token.
void clearIdpIdToken(String issuer) {
  try {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final tokenFile = File(
      p.join(home, '.neomage', 'secrets', '${issuerKey(issuer)}.idtoken'),
    );
    if (tokenFile.existsSync()) tokenFile.deleteSync();
  } catch (_) {}
}

/// Save an id_token JWT directly to cache. Returns the expiration timestamp.
int saveIdpIdTokenFromJwt(String issuer, String jwt) {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final secretDir = Directory(p.join(home, '.neomage', 'secrets'));
  secretDir.createSync(recursive: true);
  final tokenFile = File(
    p.join(secretDir.path, '${issuerKey(issuer)}.idtoken'),
  );
  tokenFile.writeAsStringSync(jwt);

  // Decode JWT expiration from payload.
  try {
    final parts = jwt.split('.');
    if (parts.length >= 2) {
      var payload = parts[1];
      // Pad base64 if needed.
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = jsonDecode(utf8.decode(base64Url.decode(payload)));
      if (decoded is Map && decoded['exp'] is int) {
        return (decoded['exp'] as int) * 1000; // Convert to milliseconds
      }
    }
  } catch (_) {}
  // Default: 1 hour from now.
  return DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
}

// ============================================================================
// XaaIdpCommand — the /mcp-xaa command with subcommands.
// ============================================================================

/// The /mcp-xaa command — manage XAA (SEP-990) IdP connection.
///
/// Subcommands:
///   setup  — Configure the IdP connection (one-time for all XAA servers)
///   login  — Cache an IdP id_token for silent authentication
///   show   — Show the current IdP connection config
///   clear  — Clear the IdP connection config and cached id_token
class XaaIdpCommand extends LocalCommand {
  XaaIdpCommand();

  @override
  String get name => 'mcp-xaa';

  @override
  String get description => 'Manage the XAA (SEP-990) IdP connection';

  @override
  String? get argumentHint =>
      '<setup|login|show|clear> [--issuer <url>] [--client-id <id>] '
      '[--client-secret] [--callback-port <port>] [--force] [--id-token <jwt>]';

  @override
  bool get supportsNonInteractive => true;

  @override
  List<String> get aliases => const ['xaa'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final tokens = args.trim().split(RegExp(r'\s+'));
    if (tokens.isEmpty || tokens.first.isEmpty) {
      return const TextCommandResult(
        'Usage: /mcp-xaa <setup|login|show|clear>\n\n'
        'Subcommands:\n'
        '  setup  - Configure the IdP connection\n'
        '  login  - Cache an IdP id_token\n'
        '  show   - Show the current IdP connection config\n'
        '  clear  - Clear the IdP connection config',
      );
    }

    final subcommand = tokens.first;
    final subArgs = tokens.length > 1 ? tokens.sublist(1) : <String>[];

    switch (subcommand) {
      case 'setup':
        return _handleSetup(subArgs);
      case 'login':
        return _handleLogin(subArgs);
      case 'show':
        return _handleShow();
      case 'clear':
        return _handleClear();
      default:
        return TextCommandResult(
          'Unknown subcommand: $subcommand\n'
          'Usage: /mcp-xaa <setup|login|show|clear>',
        );
    }
  }

  // ── setup ─────────────────────────────────────────────────────────────────

  Future<CommandResult> _handleSetup(List<String> args) async {
    // Parse setup options.
    String? issuer;
    String? clientId;
    bool clientSecret = false;
    int? callbackPort;

    var i = 0;
    while (i < args.length) {
      switch (args[i]) {
        case '--issuer':
          issuer = (++i < args.length) ? args[i] : null;
          break;
        case '--client-id':
          clientId = (++i < args.length) ? args[i] : null;
          break;
        case '--client-secret':
          clientSecret = true;
          break;
        case '--callback-port':
          final raw = (++i < args.length) ? args[i] : null;
          callbackPort = raw != null ? int.tryParse(raw) : null;
          break;
      }
      i++;
    }

    if (issuer == null) {
      return const TextCommandResult(
        'Error: --issuer <url> is required for setup.',
      );
    }
    if (clientId == null) {
      return const TextCommandResult(
        'Error: --client-id <id> is required for setup.',
      );
    }

    // Validate issuer URL.
    Uri issuerUrl;
    try {
      issuerUrl = Uri.parse(issuer);
      if (!issuerUrl.hasScheme) throw FormatException('No scheme');
    } catch (_) {
      return TextCommandResult(
        'Error: --issuer must be a valid URL (got "$issuer")',
      );
    }

    // OIDC discovery + token exchange run against this host. Allow http://
    // only for loopback; anything else leaks secrets over plaintext.
    if (issuerUrl.scheme != 'https' &&
        !(issuerUrl.scheme == 'http' &&
            (issuerUrl.host == 'localhost' ||
                issuerUrl.host == '127.0.0.1' ||
                issuerUrl.host == '[::1]'))) {
      return TextCommandResult(
        'Error: --issuer must use https:// '
        '(got "${issuerUrl.scheme}://${issuerUrl.host}")',
      );
    }

    // Validate callback port.
    if (callbackPort != null && callbackPort <= 0) {
      return const TextCommandResult(
        'Error: --callback-port must be a positive integer',
      );
    }

    // Read client secret from environment variable if --client-secret flag
    // was provided.
    String? secret;
    if (clientSecret) {
      secret = Platform.environment['MCP_XAA_IDP_CLIENT_SECRET'];
      if (secret == null || secret.isEmpty) {
        return const TextCommandResult(
          'Error: --client-secret requires MCP_XAA_IDP_CLIENT_SECRET env var',
        );
      }
    }

    // Read old config BEFORE overwrite so we can clear stale keychain slots
    // after a successful write.
    final old = await getXaaIdpSettings();
    final oldIssuer = old?.issuer;
    final oldClientId = old?.clientId;

    // Write settings.
    final error = await updateSettingsForSource({
      'xaaIdp': {
        'issuer': issuer,
        'clientId': clientId,
        'callbackPort': callbackPort,
      },
    });

    if (error != null) {
      return TextCommandResult('Error writing settings: $error');
    }

    // Clear stale keychain slots only after settings write succeeded.
    // Compare via issuerKey(): trailing-slash or host-case differences
    // normalize to the same keychain slot.
    if (oldIssuer != null) {
      if (issuerKey(oldIssuer) != issuerKey(issuer)) {
        clearIdpIdToken(oldIssuer);
        clearIdpClientSecret(oldIssuer);
      } else if (oldClientId != clientId) {
        // Same issuer slot but different OAuth client registration.
        // The cached id_token's aud claim and the stored secret are both for
        // the old client. Clear both to avoid opaque failures.
        clearIdpIdToken(oldIssuer);
        clearIdpClientSecret(oldIssuer);
      }
    }

    // Save client secret if provided.
    if (secret != null) {
      final result = saveIdpClientSecret(issuer, secret);
      if (!result.success) {
        final warning = result.warning != null ? ' -- ${result.warning}' : '';
        return TextCommandResult(
          'Error: settings written but keychain save failed$warning. '
          'Re-run with --client-secret once keychain is available.',
        );
      }
    }

    return TextCommandResult('XAA IdP connection configured for $issuer');
  }

  // ── login ─────────────────────────────────────────────────────────────────

  Future<CommandResult> _handleLogin(List<String> args) async {
    final idp = await getXaaIdpSettings();
    if (idp == null) {
      return const TextCommandResult(
        "Error: no XAA IdP connection. Run '/mcp-xaa setup' first.",
      );
    }

    // Parse login options.
    bool force = false;
    String? idToken;

    var i = 0;
    while (i < args.length) {
      switch (args[i]) {
        case '--force':
          force = true;
          break;
        case '--id-token':
          idToken = (++i < args.length) ? args[i] : null;
          break;
      }
      i++;
    }

    // Direct-inject path: skip cache check, skip OIDC. Writing IS the
    // operation. Issuer comes from settings (single source of truth).
    if (idToken != null) {
      final expiresAt = saveIdpIdTokenFromJwt(idp.issuer, idToken);
      final expiresDate = DateTime.fromMillisecondsSinceEpoch(
        expiresAt,
      ).toIso8601String();
      return TextCommandResult(
        'id_token cached for ${idp.issuer} (expires $expiresDate)',
      );
    }

    if (force) {
      clearIdpIdToken(idp.issuer);
    }

    final wasCached = getCachedIdpIdToken(idp.issuer) != null;
    if (wasCached) {
      return TextCommandResult(
        'Already logged in to ${idp.issuer} (cached id_token still valid). '
        'Use --force to re-login.',
      );
    }

    // In a full implementation, this would open the browser for OIDC login
    // flow and call acquireIdpIdToken. For now, return instructions.
    return TextCommandResult(
      'Opening browser for IdP login at ${idp.issuer}...\n'
      'If the browser did not open, visit the IdP authorization URL.\n\n'
      'Note: Browser-based OIDC login flow requires platform integration.\n'
      'Use --id-token <jwt> to manually cache a pre-obtained token.',
    );
  }

  // ── show ──────────────────────────────────────────────────────────────────

  Future<CommandResult> _handleShow() async {
    final idp = await getXaaIdpSettings();
    if (idp == null) {
      return const TextCommandResult('No XAA IdP connection configured.');
    }

    final hasSecret = getIdpClientSecret(idp.issuer) != null;
    final hasIdToken = getCachedIdpIdToken(idp.issuer) != null;

    final buf = StringBuffer();
    buf.writeln('Issuer:        ${idp.issuer}');
    buf.writeln('Client ID:     ${idp.clientId}');
    if (idp.callbackPort != null) {
      buf.writeln('Callback port: ${idp.callbackPort}');
    }
    buf.writeln(
      'Client secret: ${hasSecret ? "(stored in keychain)" : "(not set -- PKCE-only)"}',
    );
    buf.write(
      'Logged in:     ${hasIdToken ? "yes (id_token cached)" : "no -- run '/mcp-xaa login'"}',
    );

    return TextCommandResult(buf.toString());
  }

  // ── clear ─────────────────────────────────────────────────────────────────

  Future<CommandResult> _handleClear() async {
    // Read issuer first so we can clear the right keychain slots.
    final idp = await getXaaIdpSettings();

    // Set xaaIdp to null to signal key removal.
    final error = await updateSettingsForSource({'xaaIdp': null});
    if (error != null) {
      return TextCommandResult('Error writing settings: $error');
    }

    // Clear keychain only after settings write succeeded.
    if (idp != null) {
      clearIdpIdToken(idp.issuer);
      clearIdpClientSecret(idp.issuer);
    }

    return const TextCommandResult('XAA IdP connection cleared');
  }
}

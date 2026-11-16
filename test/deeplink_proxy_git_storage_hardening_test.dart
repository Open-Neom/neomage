import 'package:flutter_test/flutter_test.dart';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/data/commands/builtin/terminal_setup_command.dart';
import 'package:neomage/domain/models/permissions.dart';
import 'package:neomage/data/services/git_service.dart';
import 'package:neomage/data/services/remote_settings_service.dart';
import 'package:neomage/data/services/search_service.dart';
import 'package:neomage/data/tools/js_sandbox_tool.dart';
import 'package:neomage/utils/deep_link/deep_link_handler.dart';
import 'package:neomage/utils/file_history/file_history.dart';
import 'package:neomage/utils/input/process_user_input.dart';
import 'package:neomage/utils/process/process_manager.dart';
import 'package:neomage/utils/proxy/proxy_utils.dart';
import 'package:neomage/utils/ripgrep/ripgrep_utils.dart' as rg_utils;
import 'package:neomage/utils/tool_result/tool_result_storage.dart';

const bool _isWebRuntime = identical(0, 0.0);

void main() {
  group('JsSandboxTool multiplatform & ReadOnlyToolMixin hardening', () {
    test('declares ReadOnlyToolMixin and allows default permission check', () async {
      final tool = JsSandboxTool();
      expect(tool.isReadOnly, isTrue);
      expect(tool.isConcurrencySafe, isTrue);
      expect(tool.isDestructive, isFalse);

      const permCtx = ToolPermissionContext(
        mode: PermissionMode.defaultMode,
        rulesBySource: {},
        workingDirectory: '/tmp/workspace',
      );
      final decision = await tool.checkPermissions({'code': '2 + 2'}, permCtx);
      expect(decision, isA<AllowDecision>());
    });

    test('validateInput rejects empty, NUL, and oversized JS code', () {
      final tool = JsSandboxTool();
      expect(tool.validateInput({'code': '   '}).isValid, isFalse);
      expect(tool.validateInput({'code': '1 + 1\x00'}).isValid, isFalse);
      expect(
        tool.validateInput({'code': 'a' * (JsSandboxTool.maxCodeChars + 1)}).isValid,
        isFalse,
      );
      expect(tool.validateInput({'code': '2 + 2'}).isValid, isTrue);
    });
  });

  group('DeepLinkParser & DeepLinkHandler osascript argv hardening', () {
    test('parseDeepLink rejects UNC shares, protected dirs, BiDi chars, and CLI-flag repos', () {
      expect(
        () => parseDeepLink('neomage-cli://open?cwd=//attacker.evil/share'),
        throwsFormatException,
      );
      expect(
        () => parseDeepLink(r'neomage-cli://open?cwd=\\attacker.evil\share'),
        throwsFormatException,
      );
      expect(
        () => parseDeepLink('neomage-cli://open?cwd=/etc'),
        throwsFormatException,
      );
      expect(
        () => parseDeepLink('neomage-cli://open?cwd=/Users/alice/.ssh'),
        throwsFormatException,
      );
      expect(
        () => parseDeepLink('neomage-cli://open?cwd=/Users/alice/\u202Erepo'),
        throwsFormatException,
      );
      expect(
        () => parseDeepLink('neomage-cli://open?repo=-oProxyCommand/repo'),
        throwsFormatException,
      );
      expect(
        () => parseDeepLink('neomage-cli://open?repo=owner/..'),
        throwsFormatException,
      );

      final ok = parseDeepLink(
        'neomage-cli://open?cwd=/Users/alice/projects/app&repo=owner/repo&q=hello',
      );
      expect(ok.cwd, '/Users/alice/projects/app');
      expect(ok.repo, 'owner/repo');
      expect(ok.query, 'hello');
    });

    test('buildMacOsTerminalAppleScriptArgs passes command via argv without interpolation', () {
      const payload = 'echo "pwn" & do shell script "touch /tmp/pwn"';
      final termArgs = buildMacOsTerminalAppleScriptArgs('Terminal', payload);
      expect(termArgs[0], '-e');
      expect(termArgs[1], contains('on run argv'));
      expect(termArgs[1], isNot(contains('touch /tmp/pwn')));
      expect(termArgs[2], '--');
      expect(termArgs[3], payload);

      final itermArgs = buildMacOsTerminalAppleScriptArgs('iTerm', payload);
      expect(itermArgs[1], contains('on run argv'));
      expect(itermArgs[1], isNot(contains('touch /tmp/pwn')));
      expect(itermArgs[2], '--');
      expect(itermArgs[3], payload);
    });
  });

  group('RemoteSettingsService non-overridable managed policy enforcement', () {
    test('overridable=false blocks setLocalOverride and wins over pre-existing overrides', () {
      final service = RemoteSettingsService(
        config: const RemoteSettingsConfig(
          endpoint: 'https://config.example.com/settings.json',
          cacheDir: '/tmp/neomage-remote-settings-test',
        ),
      );

      // Local override set before fleet policy arrives:
      service.setLocalOverride('allow_bypass', true);
      expect(service.get<bool>('allow_bypass'), isTrue);

      // Managed fleet policy marks allow_bypass as non-overridable false:
      service.applySettings({
        'allow_bypass': RemoteSetting(
          key: 'allow_bypass',
          value: false,
          source: RemoteSettingsSource.organization,
          lastFetched: DateTime.utc(2026, 11, 8),
          overridable: false,
        ),
      });

      expect(service.get<bool>('allow_bypass'), isFalse);
      expect(service.isOverridden('allow_bypass'), isFalse);
      expect(service.getEffective('allow_bypass').value, isFalse);
      expect(
        service.getEffective('allow_bypass').source,
        SettingValueSource.remote,
      );
      expect(
        () => service.setLocalOverride('allow_bypass', true),
        throwsStateError,
      );
      expect(
        () => service.setLocalOverride('__proto__', {'admin': true}),
        throwsArgumentError,
      );
    });
  });

  group('ProxyUtils PAC injection & CRLF User-Agent hardening', () {
    test('parseProxyUrl rejects PAC semicolon injection, non-HTTP schemes, and brackets IPv6', () {
      expect(parseProxyUrl('http://proxy.corp:8080; DIRECT'), isNull);
      expect(isValidProxyUrl('file:///etc/passwd'), isFalse);
      expect(isValidProxyUrl('socks5://proxy.corp:1080'), isFalse);
      expect(isValidProxyUrl('http://proxy.corp:99999'), isFalse);

      final v4 = parseProxyUrl('http://proxy.corp:8080');
      expect(v4, isNotNull);
      expect(v4!.pacHostPort, 'proxy.corp:8080');

      final v6 = parseProxyUrl('http://[::1]:3128');
      expect(v6, isNotNull);
      expect(v6!.pacHostPort, '[::1]:3128');
    });

    test('getUserAgent & getAuthHeaders strip CRLF header injection', () {
      final ua = getUserAgent(
        version: '1.0.0\r\nX-Injected: evil',
        clientApp: 'itzli\nEvil: 1',
      );
      expect(ua.contains('\r'), isFalse);
      expect(ua.contains('\n'), isFalse);

      final auth = getAuthHeaders(
        isSubscriber: true,
        getOAuthAccessToken: () => 'tok_123\r\nX-Evil: 1',
        oauthBetaHeader: 'beta\r\nX-Beta: 2',
      );
      expect(auth.headers['Authorization']!.contains('\r'), isFalse);
      expect(auth.headers['Authorization']!.contains('\n'), isFalse);
      expect(auth.headers['anthropic-beta']!.contains('\r'), isFalse);
    });
  });

  group('Ripgrep, GitService, TerminalSetup & Input safety hardening', () {
    test('sanitizeRipgrepArgs strips --pre and --pre-glob RCE flags', () {
      final filtered1 = SearchService.sanitizeRipgrepArgs([
        '--hidden',
        '--pre',
        '/bin/sh',
        '--pre=/usr/bin/id',
        '--pre-glob=*.txt',
        '--pre-glob',
        '*.md',
        '-i',
      ]);
      expect(filtered1, equals(['--hidden', '-i']));

      final filtered2 = rg_utils.sanitizeRipgrepArgs([
        '--files',
        '--PRE=/bin/sh',
        '--pre',
        'sh',
      ]);
      expect(filtered2, equals(['--files']));
    });

    test('GitService blocks leading-hyphen option injection and ext:: / SSRF remotes', () {
      expect(
        () => GitService.validateGitRefOrName('--upload-pack=/tmp/pwn'),
        throwsArgumentError,
      );
      expect(
        () => GitService.validateGitRefOrName(
          'origin..evil',
          disallowRangeDots: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => GitService.validateRemoteUrl('ext::sh -c touch% /tmp/pwn'),
        throwsArgumentError,
      );
      expect(
        () => GitService.validateRemoteUrl('file:///etc/passwd'),
        throwsArgumentError,
      );
      expect(
        () => GitService.validateRemoteUrl('https://169.254.169.254/repo.git'),
        throwsArgumentError,
      );
      expect(
        () => GitService.validateRemoteUrl('git@127.0.0.1:owner/repo.git'),
        throwsArgumentError,
      );

      expect(
        () => GitService.validateRemoteUrl('https://github.com/owner/repo.git'),
        returnsNormally,
      );
      expect(
        () => GitService.validateRemoteUrl('git@github.com:owner/repo.git'),
        returnsNormally,
      );
    });

    test('validatePlistProfileName blocks PlistBuddy quote and colon injection', () {
      expect(
        () => validatePlistProfileName("Basic':Bell bool true; Print :"),
        throwsArgumentError,
      );
      expect(() => validatePlistProfileName('Basic:Sub'), throwsArgumentError);
      expect(() => validatePlistProfileName('Basic'), returnsNormally);
      expect(() => validatePlistProfileName('Pro Solarized'), returnsNormally);
    });

    test('checkInputSafety detects Trojan Source BiDi override & Shell.quoteArg strips NUL', () {
      final warnings = checkInputSafety('normal \u202E reversed');
      expect(
        warnings.any((w) => w.contains('bidirectional')),
        isTrue,
      );
      expect(Shell.quoteArg('abc\x00def'), 'abcdef');
    });
  });

  group('ToolResultStorage & FileHistoryManager path traversal hardening', () {
    test('ToolResultStorage.sanitizeStorageIdentifier neutralizes ../ traversal', () {
      expect(
        ToolResultStorage.sanitizeStorageIdentifier('toolu_01AbCdEf_99'),
        'toolu_01AbCdEf_99',
      );
      final sanitized = ToolResultStorage.sanitizeStorageIdentifier(
        '../../../settings.local',
      );
      expect(sanitized.contains('/'), isFalse);
      expect(sanitized.contains('..'), isFalse);
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(sanitized), isTrue);

      final storage = ToolResultStorage(
        projectDir: '/tmp/neomage_proj',
        sessionId: '../../escape_session',
        originalCwd: '/tmp/neomage_proj',
      );
      final resultPath = storage.getToolResultPath(
        '../../../settings.local',
        isJson: true,
      );
      expect(resultPath.startsWith('/tmp/neomage_proj/'), isTrue);
      expect(resultPath.contains('..'), isFalse);
    });

    test('FileHistoryManager validates backup names, session IDs, and /repo_evil boundary', () async {
      expect(
        FileHistoryManager.isSafeBackupFileName('0123456789abcdef@v1'),
        isTrue,
      );
      expect(
        FileHistoryManager.isSafeBackupFileName('../../.bashrc@v1'),
        isFalse,
      );
      expect(FileHistoryManager.isSafeSessionId('../escape'), isFalse);
      expect(FileHistoryManager.isSafeSessionId('session_2026_11'), isTrue);

      if (!_isWebRuntime) {
        final tempRoot = await Directory.systemTemp.createTemp(
          'neomage_fh_hardening_',
        );
        try {
          final repoDir = Directory('${tempRoot.path}/repo')..createSync();
          final evilDir = Directory('${tempRoot.path}/repo_evil')..createSync();
          final insideFile = File('${repoDir.path}/main.dart')
            ..writeAsStringSync('void main() {}\n');
          final siblingFile = File('${evilDir.path}/secret.dart')
            ..writeAsStringSync('const s = 1;\n');

          final mgr = FileHistoryManager(
            configHomeDir: '${tempRoot.path}/cfg',
            sessionId: 'sess_ok',
            originalCwd: repoDir.path,
          );
          await mgr.fileHistoryMakeSnapshot('m1');
          await mgr.fileHistoryTrackEdit(insideFile.path, 'm1');
          await mgr.fileHistoryTrackEdit(siblingFile.path, 'm1');

          expect(mgr.state.value.trackedFiles.contains('main.dart'), isTrue);
          // Sibling /repo_evil/secret.dart must NOT be shortened as '_evil/secret.dart'!
          expect(
            mgr.state.value.trackedFiles.contains(siblingFile.path),
            isTrue,
          );
          expect(
            mgr.state.value.trackedFiles.any((p) => p.startsWith('_evil')),
            isFalse,
          );
        } finally {
          await tempRoot.delete(recursive: true);
        }
      }
    });
  });
}

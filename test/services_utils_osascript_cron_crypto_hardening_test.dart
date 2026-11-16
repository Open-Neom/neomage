import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/data/platform/native_bridge.dart';
import 'package:neomage/data/services/auto_dream_service.dart';
import 'package:neomage/data/services/notification_service_full.dart';
import 'package:neomage/data/services/plugin_service.dart';
import 'package:neomage/data/services/voice_service.dart';
import 'package:neomage/utils/auth/feature_gates.dart';
import 'package:neomage/utils/cron/cron_manager.dart';
import 'package:neomage/utils/crypto/crypto_utils.dart' as crypto;
import 'package:neomage/utils/handle_prompt/handle_prompt_submit.dart';
import 'package:neomage/utils/ide/ide_utils.dart';
import 'package:neomage/utils/image/image_utils.dart';
import 'package:neomage/utils/neomagemd/neomagemd_parser.dart';
import 'package:neomage/utils/release/release_utils.dart';
import 'package:neomage/utils/security/neomage_network_guard.dart';
import 'package:neomage/utils/worktree/worktree_manager.dart';
import 'package:path/path.dart' as p;

const bool _isWeb = identical(0, 0.0);

void main() {
  group('T-096 NeomageMdParser @include & Path Containment Hardening', () {
    test('blocks .env, .env.*, private keys, SSH keys, UNC, and protected system paths', () {
      expect(isForbiddenMemoryIncludePath('/repo/.env'), isTrue);
      expect(isForbiddenMemoryIncludePath('/repo/.env.production'), isTrue);
      expect(isForbiddenMemoryIncludePath('/repo/certs/server.pem'), isTrue);
      expect(isForbiddenMemoryIncludePath('/repo/certs/tls.key'), isTrue);
      expect(isForbiddenMemoryIncludePath('/Users/alice/.ssh/id_ed25519'), isTrue);
      expect(isForbiddenMemoryIncludePath('//evil.example/share/NEOMAGE.md'), isTrue);
      expect(isForbiddenMemoryIncludePath('/etc/passwd'), isTrue);

      // Top-level managed memory is allowed in /etc/neomage, but @include into /etc/neomage is blocked.
      expect(
        isForbiddenMemoryIncludePath(
          '/etc/neomage/NEOMAGE.md',
          type: MemoryType.managed,
          isInclude: false,
        ),
        isFalse,
      );
      expect(
        isForbiddenMemoryIncludePath(
          '/etc/neomage/NEOMAGE.md',
          type: MemoryType.project,
          isInclude: true,
        ),
        isTrue,
      );
      expect(isForbiddenMemoryIncludePath('/repo/docs/guide.md'), isFalse);
    });

    test('parseMemoryFileContent strips forbidden @include targets while keeping legitimate docs', () {
      final parsed = NeomageMdParser.parseMemoryFileContent(
        'Follow @./docs/arch.md and never load @./.env or @/etc/passwd or @./secrets/api.key',
        '/repo/NEOMAGE.md',
        MemoryType.project,
        includeBasePath: '/repo/NEOMAGE.md',
      );
      expect(parsed.info, isNotNull);
      expect(parsed.includePaths, equals(['/repo/docs/arch.md']));

      final envParsed = NeomageMdParser.parseMemoryFileContent(
        'OPENAI_API_KEY=sk-secret',
        '/repo/.env',
        MemoryType.project,
      );
      expect(envParsed.info, isNull);
    });

    test('defaultPathInWorkingPath enforces segment boundaries and normalizes .. traversal', () {
      expect(defaultPathInWorkingPath('/repo/sub/NEOMAGE.md', '/repo'), isTrue);
      expect(defaultPathInWorkingPath('/repo', '/repo/'), isTrue);
      expect(
        defaultPathInWorkingPath('/repo_evil/NEOMAGE.md', '/repo'),
        isFalse,
      );
      expect(
        defaultPathInWorkingPath('/repo/sub/../../etc/passwd', '/repo'),
        isFalse,
      );
      expect(
        defaultPathInWorkingPath('//attacker/share/file.md', '/repo'),
        isFalse,
      );
    });
  });

  group('T-096 WorktreeManager Slug & Hook Hardening', () {
    test('validateWorktreeSlug rejects git option injection (-flag), .. traversal, backslashes, and NUL', () {
      expect(
        () => WorktreeManager.validateWorktreeSlug('feat/safe-branch_01'),
        returnsNormally,
      );
      expect(
        () => WorktreeManager.validateWorktreeSlug('-u'),
        throwsArgumentError,
      );
      expect(
        () => WorktreeManager.validateWorktreeSlug('feat/-evil-option'),
        throwsArgumentError,
      );
      expect(
        () => WorktreeManager.validateWorktreeSlug('../escape'),
        throwsArgumentError,
      );
      expect(
        () => WorktreeManager.validateWorktreeSlug(r'feat\win'),
        throwsArgumentError,
      );
      expect(
        () => WorktreeManager.validateWorktreeSlug('feat\x00null'),
        throwsArgumentError,
      );
    });
  });

  group('T-096 Pure-Dart CryptoUtils & Keychain Identifier Guards', () {
    test('sha256, sha256Sync, md5, hmacSha256, and constantTimeEquals compute exact vectors without shells', () async {
      expect(
        crypto.sha256Sync('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        await crypto.sha256('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        await crypto.md5('abc'),
        '900150983cd24fb0d6963f7d28e17f72',
      );
      expect(
        await crypto.hmacSha256('key', 'The quick brown fox jumps over the lazy dog'),
        'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
      );
      expect(crypto.constantTimeEquals('tok_12345', 'tok_12345'), isTrue);
      expect(crypto.constantTimeEquals('tok_12345', 'tok_12346'), isFalse);
      expect(crypto.constantTimeEquals('short', 'much_longer_secret'), isFalse);
      expect(crypto.constantTimeEquals('', ''), isTrue);
    });

    test('SecureStorage.validateKeychainIdentifier rejects option injection and control chars', () {
      expect(
        () => crypto.SecureStorage.validateKeychainIdentifier('api_token_v1'),
        returnsNormally,
      );
      expect(
        () => crypto.SecureStorage.validateKeychainIdentifier('-w'),
        throwsArgumentError,
      );
      expect(
        () => crypto.SecureStorage.validateKeychainIdentifier('bad\nkey'),
        throwsArgumentError,
      );
      expect(
        () => crypto.SecureStorage.validateKeychainIdentifier(''),
        throwsArgumentError,
      );
    });

    test(
      'hashFile and hashDirectory stream regular files and reject symlinks and protected paths',
      () async {
        final tmp = await Directory.systemTemp.createTemp('neomage_crypto_t096_');
        try {
          final f1 = File(p.join(tmp.path, 'a.txt'));
          await f1.writeAsString('abc');
          expect(
            await crypto.hashFile(f1.path),
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          );

          final link = Link(p.join(tmp.path, 'evil_link.txt'));
          await link.create(f1.path);
          await expectLater(
            crypto.hashFile(link.path),
            throwsA(isA<FileSystemException>()),
          );

          // hashDirectory ignores symlink entries (followLinks: false) without crashing or escaping.
          final dirDigest = await crypto.hashDirectory(tmp.path);
          expect(dirDigest, hasLength(64));

          await expectLater(
            crypto.hashFile('/etc/passwd'),
            throwsA(isA<FileSystemException>()),
          );
        } finally {
          if (await tmp.exists()) await tmp.delete(recursive: true);
        }
      },
      skip: _isWeb ? 'VM filesystem test' : false,
    );
  });

  group('T-096 Cron Scheduler Lock O_EXCL & Safe Liveness Probe', () {
    test(
      'tryAcquireSchedulerLock acquires atomically with O_EXCL, re-enters idempotently without SIGUSR1 self-kill, and blocks rival PIDs',
      () async {
        final tmp = await Directory.systemTemp.createTemp('neomage_cron_t096_');
        try {
          final optsA = SchedulerLockOptions(
            dir: tmp.path,
            lockIdentity: 'session_alpha',
          );
          expect(await tryAcquireSchedulerLock(opts: optsA), isTrue);
          // Re-acquire by same session must succeed without sending SIGUSR1!
          expect(await tryAcquireSchedulerLock(opts: optsA), isTrue);

          // Rival session in the same live process sees live PID via kill -0 and is blocked!
          final optsB = SchedulerLockOptions(
            dir: tmp.path,
            lockIdentity: 'session_beta',
          );
          expect(await tryAcquireSchedulerLock(opts: optsB), isFalse);

          await releaseSchedulerLock(opts: optsA);
          expect(await tryAcquireSchedulerLock(opts: optsB), isTrue);
          await releaseSchedulerLock(opts: optsB);
        } finally {
          if (await tmp.exists()) await tmp.delete(recursive: true);
        }
      },
      skip: _isWeb ? 'VM filesystem/process test' : false,
    );
  });

  group('T-096 Parameterized AppleScript / Notify / Browser URL / Editor / TTS Guards', () {
    test('NotificationServiceFull and DesktopNativeBridge parameterize osascript via on run argv', () {
      const payload = 'pwn" & (do shell script "touch /tmp/pwn") & "';
      final notifArgs = NotificationServiceFull.buildMacOsNotificationArgs(
        payload,
        payload,
      );
      expect(notifArgs[0], '-e');
      expect(notifArgs[1], contains('on run argv'));
      expect(notifArgs[1], isNot(contains('touch /tmp/pwn')));
      expect(notifArgs[2], '--');
      expect(notifArgs[3], payload);
      expect(notifArgs[4], payload);

      final linuxArgs = NotificationServiceFull.buildLinuxNotifySendArgs(
        '--icon=/etc/passwd',
        '-u',
      );
      expect(linuxArgs, equals(['--', '--icon=/etc/passwd', '-u']));

      final saveArgs = DesktopNativeBridge.buildMacOsSaveDialogArgs(
        title: payload,
        defaultName: '../evil/secret.txt',
      );
      expect(saveArgs[1], contains('on run argv'));
      expect(saveArgs[1], isNot(contains('do shell script')));
      expect(saveArgs[2], '--');
      expect(saveArgs.last, '..evilsecret.txt');

      final openArgs = DesktopNativeBridge.buildMacOsFileDialogArgs(
        title: payload,
        filters: ['png', 'pdf" & (do shell script "id") & "', 'json'],
        multiple: true,
      );
      expect(openArgs[1], contains('of type {"png", "json"}'));
      expect(openArgs[1], isNot(contains('do shell script')));
    });

    test('DesktopNativeBridge.isAllowedBrowserUrl allows https/http/mailto and blocks file/javascript/CLI flags', () {
      expect(
        DesktopNativeBridge.isAllowedBrowserUrl('https://itzli.mx/docs'),
        isTrue,
      );
      expect(
        DesktopNativeBridge.isAllowedBrowserUrl('mailto:soporte@itzli.mx'),
        isTrue,
      );
      expect(
        DesktopNativeBridge.isAllowedBrowserUrl('file:///System/Applications/Calculator.app'),
        isFalse,
      );
      expect(
        DesktopNativeBridge.isAllowedBrowserUrl('javascript:alert(1)'),
        isFalse,
      );
      expect(
        DesktopNativeBridge.isAllowedBrowserUrl('-a Calculator'),
        isFalse,
      );
      expect(
        DesktopNativeBridge.isAllowedBrowserUrl('//attacker/share/payload'),
        isFalse,
      );
    });

    test('parseSafeEditorCommand blocks shell metacharacters and option-prefixed binaries', () {
      final codeCmd = parseSafeEditorCommand('code');
      expect(codeCmd?.executable, 'code');
      expect(codeCmd?.args, equals(['-w']));

      expect(parseSafeEditorCommand('vim; touch /tmp/pwn'), isNull);
      expect(parseSafeEditorCommand('nano \$(whoami)'), isNull);
      expect(parseSafeEditorCommand('`id`'), isNull);
      expect(parseSafeEditorCommand('-e'), isNull);
      expect(parseSafeEditorCommand('//evil/share/ed'), isNull);
    });

    test('SystemTtsEngine passes -- before spoken text so leading -f/-o cannot read or write files', () {
      final macArgs = SystemTtsEngine.buildMacOsSayArgs(
        '-f /etc/passwd -o /tmp/clobber.aiff',
        speed: 999.0, // Clamped to 4.0x
      );
      expect(macArgs, equals(['-r', '700', '--', '-f /etc/passwd -o /tmp/clobber.aiff']));

      final linuxArgs = SystemTtsEngine.buildLinuxEspeakArgs(
        '-f /etc/passwd',
        speed: double.nan,
      );
      expect(linuxArgs, equals(['-s', '175', '--', '-f /etc/passwd']));
    });

    test('WhisperSttEngine and OpenAiTtsEngine reject SSRF cloud metadata endpoints', () async {
      final whisper = WhisperSttEngine();
      await expectLater(
        whisper.transcribe(
          Uint8List.fromList([1, 2, 3, 4]),
          const VoiceConfig(
            apiKey: 'sk-test-1234567890123456',
            baseUrl: 'http://169.254.169.254/latest/meta-data',
          ),
        ),
        throwsArgumentError,
      );

      final tts = OpenAiTtsEngine();
      await expectLater(
        tts.synthesize(
          'Hola',
          const VoiceConfig(
            apiKey: 'sk-test-1234567890123456',
            baseUrl: 'http://metadata.google.internal/v1',
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('T-096 IdeUtils, FeatureGates, ReleaseUtils, AutoDream & PluginService Hardening', () {
    test('IdeUtils.isSafeIdeHost allows loopback/WSL RFC1918 and blocks IMDS/public WAN', () {
      expect(IdeUtils.isSafeIdeHost('127.0.0.1'), isTrue);
      expect(IdeUtils.isSafeIdeHost('localhost'), isTrue);
      expect(IdeUtils.isSafeIdeHost('172.24.16.1'), isTrue);
      expect(IdeUtils.isSafeIdeHost('169.254.169.254'), isFalse);
      expect(IdeUtils.isSafeIdeHost('0.0.0.0'), isFalse);
      expect(IdeUtils.isSafeIdeHost('evil.example.com'), isFalse);
    });

    test(
      'IdeUtils.readIdeLockfile rejects out-of-range ports and symlinks; ImageUtils blocks /etc/passwd',
      () async {
        final tmp = await Directory.systemTemp.createTemp('neomage_ide_t096_');
        try {
          final ide = IdeUtils();
          final badPortFile = File(p.join(tmp.path, '99999.lock'));
          await badPortFile.writeAsString('{"pid": 1234}');
          expect(await ide.readIdeLockfile(badPortFile.path), isNull);

          final validLock = File(p.join(tmp.path, '45123.lock'));
          await validLock.writeAsString('{"pid": 1234, "ideName": "VS Code"}');
          final parsed = await ide.readIdeLockfile(validLock.path);
          expect(parsed?.port, 45123);

          final linkLock = Link(p.join(tmp.path, '45124.lock'));
          await linkLock.create(validLock.path);
          expect(await ide.readIdeLockfile(linkLock.path), isNull);

          final img = ImageUtils();
          expect(await img.tryReadImageFromPath('/etc/passwd.png'), isNull);
        } finally {
          if (await tmp.exists()) await tmp.delete(recursive: true);
        }
      },
      skip: _isWeb ? 'VM filesystem test' : false,
    );

    test('FeatureGateService blocks SSRF endpoints and PluginOperationsService blocks __proto__ & traversal', () async {
      final gates = FeatureGateService();
      await expectLater(
        gates.loadFromRemote('http://169.254.169.254/latest/meta-data/gates'),
        throwsArgumentError,
      );
      await expectLater(
        gates.loadFromRemote('http://api.neomage.ai/gates'),
        throwsArgumentError,
      );
      gates.dispose();

      expect(isValidPluginIdentifier('formatter@official'), isTrue);
      expect(isValidPluginIdentifier('builtin:git'), isTrue);
      expect(isValidPluginIdentifier('__proto__'), isFalse);
      expect(isValidPluginIdentifier('plugin@__proto__'), isFalse);
      expect(isValidPluginIdentifier('../escape@official'), isFalse);
      expect(isValidPluginIdentifier('bad/slash@official'), isFalse);

      final prompt = buildConsolidationPrompt(
        '/tmp/mem`whoami`',
        '/tmp/trans\$(id)',
        '',
      );
      expect(prompt, isNot(contains('`whoami`')));
      expect(prompt, isNot(contains(r'$(id)')));
    });

    test(
      'AutoUpdaterController enforces atomic O_EXCL lock and rejects unsafe version/package specs',
      () async {
        final tmp = await Directory.systemTemp.createTemp('neomage_upd_t096_');
        try {
          final updater = AutoUpdaterController(
            appVersion: '1.0.0',
            packageUrl: '@neom/neomage',
            configHomeDir: tmp.path,
            execCommand: (exe, args, {workingDirectory}) async =>
                ProcessResult(0, 0, tmp.path, ''),
          );
          expect(await updater.acquireLock(), isTrue);
          expect(await updater.acquireLock(), isFalse);
          await updater.releaseLock();

          final badStatus = await updater.installGlobalPackage(
            specificVersion: '--registry=https://evil.example',
          );
          expect(badStatus, AutoUpdateInstallStatus.installFailed);
        } finally {
          if (await tmp.exists()) await tmp.delete(recursive: true);
        }
      },
      skip: _isWeb ? 'VM filesystem test' : false,
    );

    test('NeomageNetworkGuard.sanitizeSubprocessEnv strips DYLD/LD/NODE/PYTHON hooks while preserving PATH', () {
      final cleaned = NeomageNetworkGuard.sanitizeSubprocessEnv({
        'PATH': '/usr/bin:/bin',
        'DYLD_INSERT_LIBRARIES': '/tmp/evil.dylib',
        'LD_PRELOAD': '/tmp/evil.so',
        'BASH_ENV': '/tmp/rc.sh',
        'NODE_OPTIONS': '--require /tmp/pwn.js',
        'BASH_FUNC_myfn%%': '() { :; }; id',
      });
      expect(cleaned['PATH'], '/usr/bin:/bin');
      expect(cleaned.containsKey('DYLD_INSERT_LIBRARIES'), isFalse);
      expect(cleaned.containsKey('LD_PRELOAD'), isFalse);
      expect(cleaned.containsKey('BASH_ENV'), isFalse);
      expect(cleaned.containsKey('NODE_OPTIONS'), isFalse);
      expect(cleaned.containsKey('BASH_FUNC_myfn%%'), isFalse);
    });
  });
}

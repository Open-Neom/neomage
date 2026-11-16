import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/utils/context/context_builder.dart';
import 'package:neomage/utils/doctor/doctor_diagnostic.dart';
import 'package:neomage/utils/env/env_manager.dart';
import 'package:neomage/utils/image/image_utils.dart';
import 'package:neomage/utils/security/neomage_network_guard.dart';

void main() {
  group('Lote 50 — NeomageNetworkGuard JS-safe IPv4/IPv6 & SSRF hardening', () {
    test(
      'overflow numeric & high-bit IPv4 hosts never throw ArgumentError on JS/Web',
      () {
        expect(NeomageNetworkGuard.isPrivateOrReservedHost('999.1.1.1'), isTrue);
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('99999999999'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('0x100000000'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('169.254.99999'),
          isTrue,
        );
        // Decimal / hex / octal / shorthand IMDS & RFC1918 (>= 128 first octet)
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('2852039166'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('0xa9fea9fe'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('0251.0376.0251.0376'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('169.254.43518'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('172.16.0.1'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('192.168.1.25'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('1.1.1.1'),
          isFalse,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('api.anthropic.com'),
          isFalse,
        );
      },
    );

    test(
      'blocks NAT64, 6to4, single-label intranet, backslashes, BiDi, and zone IDs',
      () {
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('[64:ff9b::a9fe:a9fe]'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('[2002:a9fe:a9fe::1]'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('corp-vault'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('git.internal.corp'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost(r'ok.com\127.0.0.1'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('api\u202E.example.com'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isPrivateOrReservedHost('[fe80::1%eth0]'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.validateProviderBaseUri(
            r'https://api.example.com\169.254.169.254/v1',
            allowLocalHttp: false,
          ),
          isNull,
        );
        expect(
          NeomageNetworkGuard.isSafeEndpointUri(
            Uri.https('api.example.com', r'/v1\admin'),
          ),
          isFalse,
        );
      },
    );
  });

  group('Lote 50 — ImageUtils.readUint32BE unsigned 32-bit JS safety', () {
    test('reads high-bit big-endian uint32 as positive unsigned integer', () {
      final hiBit = Uint8List.fromList(<int>[0x80, 0x00, 0x00, 0x01]);
      expect(ImageUtils.readUint32BE(hiBit, 0), equals(0x80000001));
      expect(ImageUtils.readUint32BE(hiBit, 0) > 0, isTrue);

      final maxU32 = Uint8List.fromList(<int>[0xFF, 0xFF, 0xFF, 0xFF]);
      expect(ImageUtils.readUint32BE(maxU32, 0), equals(0xFFFFFFFF));

      expect(
        () => ImageUtils.readUint32BE(Uint8List(3), 0),
        throwsRangeError,
      );
    });
  });

  group('Lote 50 — SettingsController, ContextBuilder, Doctor & Env guards', () {
    test(
      'validateProviderBaseUri enforces HTTPS for cloud API keys and safe model IDs',
      () {
        expect(
          NeomageNetworkGuard.validateProviderBaseUri(
            'https://generativelanguage.googleapis.com/v1beta/',
            allowLocalHttp: false,
            hasApiKey: true,
          )?.toString(),
          equals('https://generativelanguage.googleapis.com/v1beta'),
        );
        expect(
          NeomageNetworkGuard.validateProviderBaseUri(
            'http://api.anthropic.com',
            allowLocalHttp: false,
            hasApiKey: true,
          ),
          isNull,
        );
        expect(
          NeomageNetworkGuard.validateProviderBaseUri(
            'http://127.0.0.1:8080',
            allowLocalHttp: false,
            hasApiKey: true,
          ),
          isNull,
        );
        expect(
          NeomageNetworkGuard.validateProviderBaseUri(
            'http://127.0.0.1:11434',
            allowLocalHttp: true,
            hasApiKey: false,
          ),
          isNotNull,
        );
        expect(
          NeomageNetworkGuard.validateProviderBaseUri(
            'http://192.168.1.50:8000',
            allowLocalHttp: true,
            hasApiKey: true,
          ),
          isNull,
        );
        expect(
          NeomageNetworkGuard.validateProviderBaseUri(
            'http://169.254.169.254/latest',
            allowLocalHttp: true,
            hasApiKey: false,
          ),
          isNull,
        );

        expect(
          NeomageNetworkGuard.isSafeModelIdentifier(
            'claude-sonnet-4-20250514',
          ),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isSafeModelIdentifier('qwen2.5-coder:7b'),
          isTrue,
        );
        expect(
          NeomageNetworkGuard.isSafeModelIdentifier('../../v1/admin?x=1'),
          isFalse,
        );
      },
    );

    test(
      'ContextBuilder, DiagnosticLog & EnvManager block flag injection & system paths',
      () async {
        expect(ContextBuilder.isSafeGitRef('HEAD~1'), isTrue);
        expect(ContextBuilder.isSafeGitRef('origin/main'), isTrue);
        expect(ContextBuilder.isSafeGitRef('--output=/tmp/pwn'), isFalse);
        expect(ContextBuilder.isSafeGitRef('--ext-diff'), isFalse);
        expect(ContextBuilder.isSafeGitRef('HEAD.lock'), isFalse);

        expect(ContextBuilder.isAllowedContextFilePath('/etc/passwd'), isFalse);
        expect(
          ContextBuilder.isAllowedContextFilePath('/Users/dev/.ssh/id_rsa'),
          isFalse,
        );
        expect(
          ContextBuilder.isAllowedContextFilePath(r'\\evil\share\secret.txt'),
          isFalse,
        );
        expect(
          ContextBuilder.isAllowedContextFilePath('/Users/dev/app/lib/main.dart'),
          isTrue,
        );

        expect(isSafeDiagnosticLogFilePath('/etc/shadow'), isFalse);
        expect(isSafeDiagnosticLogFilePath('/tmp/../etc/passwd'), isFalse);
        expect(isSafeDiagnosticLogFilePath('-flag.log'), isFalse);
        expect(isSafeDiagnosticLogFilePath('/tmp/neomage_diag.jsonl'), isTrue);

        expect(isSafeConfigHomeDirOverride('/etc'), isFalse);
        expect(isSafeConfigHomeDirOverride('/Users/dev/.aws'), isFalse);
        expect(isSafeConfigHomeDirOverride('/Users/dev/.neomage'), isTrue);

        final ctx = ContextBuilder();
        expect(await ctx.addGitDiff(ref: '--output=/tmp/exploit'), isFalse);
        expect(await ctx.addFile('/etc/passwd'), isFalse);

        if (!kIsWeb) {
          final tmp = await Directory.systemTemp.createTemp('neomage_ctx_t50_');
          try {
            final normalFile = File('${tmp.path}/ok.txt')
              ..writeAsStringSync('hello world');
            expect(await ctx.addFile(normalFile.path), isTrue);
          } finally {
            await tmp.delete(recursive: true);
          }
        }
      },
    );
  });
}

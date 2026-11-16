import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/core/platform/web_platform.dart';
import 'package:neomage/data/services/autocomplete_service.dart';
import 'package:neomage/data/services/project_service.dart';
import 'package:neomage/data/tools/file_read_tool.dart';

void main() {
  group('Lote 53 — FileReadTool JS-safe dimensions & credential path guard', () {
    test(
      'parseImageDimensions decodes PNG (including high-MSB unsigned) and top-down negative-height BMP identically on Web and VM',
      () {
        // PNG header: width = 0x80000001 (2147483649), height = 1080 (0x00000438)
        final png = Uint8List(24);
        png.setRange(0, 8, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
        png[16] = 0x80;
        png[17] = 0x00;
        png[18] = 0x00;
        png[19] = 0x01;
        png[20] = 0x00;
        png[21] = 0x00;
        png[22] = 0x04;
        png[23] = 0x38;
        final pngDims = FileReadTool.parseImageDimensions(png, 'image/png');
        expect(pngDims, equals((2147483649, 1080)));

        // Top-down BMP header: width = 200, height = -100 (0xFFFFFF9C little-endian)
        final bmp = Uint8List(26);
        bmp[0] = 0x42;
        bmp[1] = 0x4D;
        bmp[18] = 200;
        bmp[19] = 0;
        bmp[20] = 0;
        bmp[21] = 0;
        bmp[22] = 0x9C;
        bmp[23] = 0xFF;
        bmp[24] = 0xFF;
        bmp[25] = 0xFF;
        final bmpDims = FileReadTool.parseImageDimensions(bmp, 'image/bmp');
        expect(bmpDims, equals((200, 100)));

        // GIF header: 320x240
        final gif = Uint8List.fromList([
          0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
          0x40, 0x01, // 320
          0xF0, 0x00, // 240
        ]);
        expect(
          FileReadTool.parseImageDimensions(gif, 'image/gif'),
          equals((320, 240)),
        );
      },
    );

    test(
      'FileReadInput & FileReadTool block protected system/credential paths, UNC paths, and symlink targets',
      () async {
        expect(
          const FileReadInput(filePath: '/etc/passwd').validate(),
          isNotEmpty,
        );
        expect(
          const FileReadInput(filePath: '/Users/alice/.ssh/id_rsa').validate(),
          isNotEmpty,
        );
        expect(
          const FileReadInput(
            filePath: '/Users/alice/.aws/credentials',
          ).validate(),
          isNotEmpty,
        );
        expect(
          const FileReadInput(
            filePath: '//attacker.example/share/secret.txt',
          ).validate(),
          isNotEmpty,
        );

        if (!kIsWeb) {
          final tmp = await Directory.systemTemp.createTemp('lote53_read_');
          addTearDown(() async {
            if (await tmp.exists()) {
              await tmp.delete(recursive: true);
            }
          });
          final linkPath = '${tmp.path}/escaped_passwd';
          await Link(linkPath).create('/etc/hosts');
          final tool = FileReadTool();
          final result = await tool.execute({'file_path': linkPath});
          expect(result.isError, isTrue);
          expect(result.content, contains('Cannot read protected'));
        }
      },
    );
  });

  group('Lote 53 — WebPlatformService SSRF, redirect, size & path guards', () {
    test('validateBackendBaseUri rejects IMDS, public cleartext HTTP, userinfo, and traversal', () {
      expect(
        WebPlatformService.validateBackendBaseUri('http://localhost:3219'),
        isNotNull,
      );
      expect(
        WebPlatformService.validateBackendBaseUri('https://agent.itzli.mx'),
        isNotNull,
      );
      expect(
        WebPlatformService.validateBackendBaseUri('http://169.254.169.254'),
        isNull,
      );
      expect(
        WebPlatformService.validateBackendBaseUri('http://2852039166'),
        isNull,
      );
      expect(
        WebPlatformService.validateBackendBaseUri('http://evil.example.com'),
        isNull,
      );
      expect(
        WebPlatformService.validateBackendBaseUri(
          'https://user:pass@agent.itzli.mx',
        ),
        isNull,
      );
      expect(
        () => WebPlatformService(baseUrl: 'http://169.254.169.254'),
        throwsArgumentError,
      );
    });

    test('WebPlatformService disables HTTP redirects, blocks protected paths, and blocks proxy SSRF', () async {
      bool? observedFollowRedirects;
      final mockClient = MockClient.streaming((request, bodyStream) async {
        observedFollowRedirects = request.followRedirects;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode('redirecting')),
          302,
          headers: const {'location': 'http://169.254.169.254/latest/meta-data/'},
        );
      });

      final svc = WebPlatformService(
        baseUrl: 'http://localhost:3219/',
        client: mockClient,
      );

      // Protected credential & system paths blocked before network call.
      await expectLater(
        svc.readFile('/Users/alice/.ssh/id_rsa'),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        svc.writeFile('/etc/passwd', 'x'),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        svc.readFile('//attacker.example/share/a.txt'),
        throwsArgumentError,
      );

      // Proxy HTTP/WS SSRF blocked before network call.
      await expectLater(
        svc.httpRequest(
          'GET',
          Uri.parse('http://169.254.169.254/latest/meta-data/'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        svc.connectWebSocket(Uri.parse('ws://169.254.169.254/ws')),
        throwsArgumentError,
      );

      // Normal file path sends request with followRedirects = false and rejects 302.
      await expectLater(
        svc.readFile('/workspace/app/lib/main.dart'),
        throwsA(isA<PlatformException>()),
      );
      expect(observedFollowRedirects, isFalse);
    });
  });

  group('Lote 53 — ProjectService & AutocompleteService hardening', () {
    test('ProjectService.validateProjectCommand trims whitespace and blocks flag/shell/path injection', () {
      final (exe, args) = ProjectService.validateProjectCommand(
        '  dart   test --platform chrome  ',
      );
      expect(exe, equals('dart'));
      expect(args, equals(['test', '--platform', 'chrome']));

      expect(
        () => ProjectService.validateProjectCommand('   '),
        throwsArgumentError,
      );
      expect(
        () => ProjectService.validateProjectCommand('--upload-pack=id'),
        throwsArgumentError,
      );
      expect(
        () => ProjectService.validateProjectCommand('sh;id'),
        throwsArgumentError,
      );
      expect(
        () => ProjectService.validateProjectCommand('../evil/bin'),
        throwsArgumentError,
      );
      expect(
        () => ProjectService.validateProjectCommand(
          'dart test',
          workDir: '/Users/alice/.ssh',
        ),
        throwsArgumentError,
      );
    });

    test('AutocompleteService clamps out-of-bounds cursor and blocks protected/@~/ RangeError', () async {
      final svc = AutocompleteService();
      addTearDown(svc.dispose);

      // Out-of-bounds cursors (-10 and 999) never throw RangeError.
      final neg = await svc.getCompletions(
        const SuggestionContext(currentInput: '/he', cursorPosition: -10),
      );
      expect(neg, isEmpty);

      final pastEnd = await svc.getCompletions(
        const SuggestionContext(
          currentInput: '/he',
          cursorPosition: 999,
          availableCommands: ['help', 'clear'],
        ),
      );
      expect(pastEnd.any((s) => s.value == '/help'), isTrue);

      // @~/foo previously crashed with RangeError on '~'.substring(2).
      final tilde = await svc.getCompletions(
        const SuggestionContext(currentInput: '@~/nonexistent_xyz', cursorPosition: 18),
      );
      expect(tilde, isA<List<CompletionSuggestion>>());

      // Protected credential directories return empty completions.
      final ssh = await svc.getCompletions(
        const SuggestionContext(currentInput: '@/etc/pass', cursorPosition: 10),
      );
      expect(ssh, isEmpty);
    });
  });
}

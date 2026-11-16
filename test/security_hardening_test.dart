import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/data/auth/oauth_service.dart';
import 'package:neomage/data/bridge/ide_bridge.dart';
import 'package:neomage/data/mcp/mcp_transport.dart';
import 'package:neomage/data/platform/remote_bridge.dart';
import 'package:neomage/data/proxy/upstream_proxy.dart';
import 'package:neomage/data/server/direct_server.dart';
import 'package:neomage/data/tools/web_fetch_tool.dart';
import 'package:neomage/utils/deep_link/deep_link_parser.dart';
import 'package:neomage/utils/proxy/proxy_utils.dart';
import 'package:neomage/utils/security/neomage_network_guard.dart';

void main() {
  group('NeomageNetworkGuard pure-Dart security primitives', () {
    test('constantTimeEquals resists mismatch, null, and empty tokens', () {
      expect(NeomageNetworkGuard.constantTimeEquals('s3cr3t', 's3cr3t'), isTrue);
      expect(NeomageNetworkGuard.constantTimeEquals('s3cr3t', 's3cr3x'), isFalse);
      expect(NeomageNetworkGuard.constantTimeEquals('short', 'shorter'), isFalse);
      expect(NeomageNetworkGuard.constantTimeEquals('', ''), isFalse);
      expect(NeomageNetworkGuard.constantTimeEquals(null, 'a'), isFalse);
    });

    test('isPrivateOrReservedHost blocks loopback, RFC1918, IMDS, CGNAT, and IP obfuscations', () {
      expect(NeomageNetworkGuard.isPrivateOrReservedHost('127.0.0.1'), isTrue);
      expect(
        NeomageNetworkGuard.isPrivateOrReservedHost(
          '127.0.0.1',
          allowLoopback: true,
        ),
        isFalse,
      );
      expect(NeomageNetworkGuard.isPrivateOrReservedHost('169.254.169.254'), isTrue);
      expect(NeomageNetworkGuard.isPrivateOrReservedHost('100.100.100.200'), isTrue);
      expect(NeomageNetworkGuard.isPrivateOrReservedHost('metadata.google.internal'), isTrue);
      expect(NeomageNetworkGuard.isPrivateOrReservedHost('2130706433'), isTrue); // 127.0.0.1 int
      expect(NeomageNetworkGuard.isPrivateOrReservedHost('0x7f000001'), isTrue); // 127.0.0.1 hex
      expect(NeomageNetworkGuard.isPrivateOrReservedHost('0177.0.0.1'), isTrue); // octal
      expect(NeomageNetworkGuard.isPrivateOrReservedHost('[fd00::1]'), isTrue);
      expect(NeomageNetworkGuard.isPrivateOrReservedHost('docs.flutter.dev'), isFalse);
    });

    test('isAllowedLocalServerOrigin blocks CSWSH cross-site and null origins', () {
      expect(NeomageNetworkGuard.isAllowedLocalServerOrigin(null), isTrue);
      expect(NeomageNetworkGuard.isAllowedLocalServerOrigin('null'), isFalse);
      expect(
        NeomageNetworkGuard.isAllowedLocalServerOrigin(
          'https://evil.example',
          allowedOrigins: const ['*'],
        ),
        isFalse,
      );
      expect(
        NeomageNetworkGuard.isAllowedLocalServerOrigin('http://localhost:3000'),
        isTrue,
      );
      expect(
        NeomageNetworkGuard.isAllowedLocalServerOrigin(
          'vscode-webview://panel-id',
          allowIdeSchemes: true,
        ),
        isTrue,
      );
      expect(
        NeomageNetworkGuard.isAllowedLocalServerOrigin(
          'vscode-webview://panel-id',
          allowIdeSchemes: false,
        ),
        isFalse,
      );
    });

    test('redactUrlCredentials and sanitizeOAuthErrorBody strip secrets', () {
      final redacted = NeomageNetworkGuard.redactUrlCredentials(
        'https://alice:superSecret@proxy.example.com:8443/path?access_token=sk-1234567890abcdef&ok=1',
      );
      expect(redacted, isNot(contains('superSecret')));
      expect(redacted, isNot(contains('sk-1234567890abcdef')));
      expect(redacted, contains('ok=1'));

      final htmlLeak = NeomageNetworkGuard.sanitizeOAuthErrorBody(
        '<html><body>Bearer eyJhbGciOiJIUzI1NiJ9.secret</body></html>',
      );
      expect(htmlLeak, equals('upstream error payload redacted'));

      final jsonErr = NeomageNetworkGuard.sanitizeOAuthErrorBody(
        jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'Token sk-abcdefghijklmnop expired',
        }),
      );
      expect(jsonErr, contains('invalid_grant'));
      expect(jsonErr, isNot(contains('sk-abcdefghijklmnop')));
    });
  });

  group('WebFetchTool, MCP transports, OAuth, Proxy & DeepLink hardening', () {
    test('validateUrl and isPermittedRedirect block SSRF and cross-host redirects', () {
      expect(validateUrl('http://169.254.169.254/latest/meta-data'), isA<InvalidUrl>());
      expect(validateUrl('http://2130706433/admin'), isA<InvalidUrl>());
      expect(validateUrl('https://user:pass@docs.flutter.dev/'), isA<InvalidUrl>());
      expect(validateUrl('https://docs.flutter.dev/get-started'), isA<ValidUrl>());

      final orig = Uri.parse('https://example.com/start');
      expect(
        isPermittedRedirect(orig, Uri.parse('https://www.example.com/next')),
        isTrue,
      );
      expect(
        isPermittedRedirect(orig, Uri.parse('https://169.254.169.254/latest')),
        isFalse,
      );
      expect(
        isPermittedRedirect(orig, Uri.parse('http://example.com/downgrade')),
        isFalse,
      );
    });

    test('ContentLengthCodec rejects negative and oversized Content-Length frames', () {
      final codec = ContentLengthCodec();
      expect(
        () => codec.decode(utf8.encode('Content-Length: -10\r\n\r\n{}')).toList(),
        throwsA(isA<McpTransportException>()),
      );
      expect(
        () => codec
            .decode(utf8.encode('Content-Length: 999999999\r\n\r\n{}'))
            .toList(),
        throwsA(isA<McpTransportException>()),
      );

      final valid = codec.encode(
        const JsonRpcNotification(method: 'notifications/initialized'),
      );
      final decoded = codec.decode(valid).toList();
      expect(decoded, hasLength(1));
    });

    test('SseTransport.resolvePostEndpoint blocks cross-origin second-order SSRF', () {
      final sse = SseTransport(
        endpoint: Uri.parse('https://mcp.example.com:8443/sse'),
        headers: const {'Authorization': 'Bearer secret-token'},
      );
      expect(
        sse.resolvePostEndpoint('/messages?session=123'),
        equals('https://mcp.example.com:8443/messages?session=123'),
      );
      expect(
        sse.resolvePostEndpoint('http://169.254.169.254/latest/meta-data'),
        isNull,
      );
      expect(
        sse.resolvePostEndpoint('https://attacker.example.com:8443/collect'),
        isNull,
      );
      expect(
        sse.resolvePostEndpoint('https://mcp.example.com:9443/messages'),
        isNull,
      );
    });

    test('OAuthClient redacts upstream error bodies and preserves fallback refresh token', () async {
      final mockHttp = MockClient((req) async {
        final body = req.body;
        if (body.contains('grant_type=refresh_token')) {
          return http.Response(
            jsonEncode({
              'access_token': 'new_access_123',
              'expires_in': 3600,
              'scope': 'user:profile',
            }),
            200,
          );
        }
        return http.Response(
          '<html>Debug dump: client_secret=super-secret-leak</html>',
          500,
        );
      });

      final oauth = OAuthClient(
        config: OAuthConfig.neomageAi,
        httpClient: mockHttp,
      );

      final refreshed = await oauth.refreshToken(
        refreshToken: 'original_refresh_tok',
      );
      expect(refreshed.accessToken, equals('new_access_123'));
      expect(refreshed.refreshToken, equals('original_refresh_tok'));

      await expectLater(
        oauth.exchangeCode(
          code: 'bad',
          codeVerifier: 'verifier',
          state: 'state1',
        ),
        throwsA(
          predicate<Object>(
            (e) =>
                e is OAuthException &&
                !e.toString().contains('super-secret-leak'),
          ),
        ),
      );
    });

    test('BridgeMessage short IDs, UpstreamProxy SHA-256 key, ProxyConfiguration & DeepLink guards', () {
      final msg = BridgeMessage(id: '1', type: BridgeMessageType.ping);
      expect(msg.toString(), contains('1'));

      final reqA = ProxyRequest(method: 'POST', path: '/v1/messages', body: '{"a":1}');
      final reqB = ProxyRequest(method: 'POST', path: '/v1/messages', body: '{"a":2}');
      expect(reqA.cacheKey.length, equals(64));
      expect(reqA.cacheKey, isNot(equals(reqB.cacheKey)));

      final proxyCfg = ProxyConfiguration(
        httpsProxy: 'https://corpUser:corpPass@proxy.internal.example:8443',
      );
      expect(proxyCfg.describe(), isNot(contains('corpPass')));

      expect(
        () => parseDeepLink('neomage-cli://open?cwd=/Users/dev/../../etc'),
        throwsFormatException,
      );
      final safeLink = parseDeepLink(
        'neomage-cli://open?cwd=/Users/dev/project&repo=Open-Neom/neomage',
      );
      expect(safeLink.cwd, equals('/Users/dev/project'));
    });

    test('Live DirectServer, RemoteServer & IdeBridgeServer block cross-site Origin (CSWSH) and enforce constant-time auth', () async {
      if (kIsWeb) return;

      final direct = DirectServer();
      await direct.start(
        const ServerConfig(
          host: '127.0.0.1',
          port: 0,
          authToken: 'top-secret-token',
          corsOrigins: ['*'],
        ),
      );

      final remote = RemoteServer(
        host: '127.0.0.1',
        port: 0,
        authToken: 'remote-secret',
      );
      await remote.start();

      final ide = IdeBridgeServer(
        host: '127.0.0.1',
        port: 0,
        authToken: 'ide-secret',
      );
      await ide.start();

      final client = HttpClient();
      try {
        // 1. DirectServer rejects cross-site browser Origin even with corsOrigins: ['*']
        final evilReq = await client.getUrl(
          Uri.parse('http://127.0.0.1:${direct.boundPort}/api/status'),
        );
        evilReq.headers.set('Origin', 'https://attacker.example');
        evilReq.headers.set('Authorization', 'Bearer top-secret-token');
        final evilResp = await evilReq.close();
        await evilResp.drain<void>();
        expect(evilResp.statusCode, equals(HttpStatus.forbidden));

        // 2. DirectServer rejects wrong token with 401 and accepts valid token with 200
        final unauthReq = await client.getUrl(
          Uri.parse('http://127.0.0.1:${direct.boundPort}/api/sessions'),
        );
        unauthReq.headers.set('Authorization', 'Bearer wrong-token');
        final unauthResp = await unauthReq.close();
        await unauthResp.drain<void>();
        expect(unauthResp.statusCode, equals(HttpStatus.unauthorized));

        final okReq = await client.getUrl(
          Uri.parse('http://127.0.0.1:${direct.boundPort}/api/sessions'),
        );
        okReq.headers.set('Origin', 'http://localhost:5173');
        okReq.headers.set('Authorization', 'Bearer top-secret-token');
        final okResp = await okReq.close();
        await okResp.drain<void>();
        expect(okResp.statusCode, equals(HttpStatus.ok));

        // 3. RemoteServer rejects cross-site Origin with 403
        final remoteEvil = await client.getUrl(
          Uri.parse('http://127.0.0.1:${remote.boundPort}/health'),
        );
        remoteEvil.headers.set('Origin', 'https://evil.example');
        final remoteEvilResp = await remoteEvil.close();
        await remoteEvilResp.drain<void>();
        expect(remoteEvilResp.statusCode, equals(HttpStatus.forbidden));

        // 4. IdeBridgeServer rejects cross-site Origin with 403 and wrong token with 401
        final ideEvil = await client.getUrl(
          Uri.parse('http://127.0.0.1:${ide.boundPort}/'),
        );
        ideEvil.headers.set('Origin', 'https://evil.example');
        final ideEvilResp = await ideEvil.close();
        await ideEvilResp.drain<void>();
        expect(ideEvilResp.statusCode, equals(HttpStatus.forbidden));

        final ideUnauth = await client.getUrl(
          Uri.parse('http://127.0.0.1:${ide.boundPort}/'),
        );
        ideUnauth.headers.set('Origin', 'vscode-webview://extension-panel');
        ideUnauth.headers.set('x-ide-token', 'wrong');
        final ideUnauthResp = await ideUnauth.close();
        await ideUnauthResp.drain<void>();
        expect(ideUnauthResp.statusCode, equals(HttpStatus.unauthorized));
      } finally {
        client.close(force: true);
        await direct.stop();
        await remote.stop();
        await ide.stop();
      }
    });
  });
}

import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'platform_interface.dart';

/// Non-web fallback adapter used when `web_platform.dart` is imported in VM tests.
class BrowserWebSocketAdapter implements PlatformWebSocket {
  final WebSocketChannel _channel;
  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  bool _isClosed = false;

  BrowserWebSocketAdapter._(this._channel) {
    _subscription = _channel.stream.listen(
      (data) {
        if (!_controller.isClosed) {
          _controller.add(data);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_controller.isClosed) {
          _controller.addError(error, stackTrace);
        }
      },
      onDone: () {
        _isClosed = true;
        if (!_controller.isClosed) {
          unawaited(_controller.close());
        }
      },
    );
  }

  static Future<BrowserWebSocketAdapter> connect(Uri url) async {
    if (url.scheme != 'ws' && url.scheme != 'wss') {
      throw ArgumentError.value(
        url.toString(),
        'url',
        'WebSocket URL must use ws:// or wss:// scheme',
      );
    }
    final channel = WebSocketChannel.connect(url);
    await channel.ready;
    return BrowserWebSocketAdapter._(channel);
  }

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void add(dynamic data) {
    if (_isClosed) {
      throw StateError('Cannot send data: WebSocket is closed.');
    }
    _channel.sink.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_isClosed) return;
    _isClosed = true;
    await _subscription?.cancel();
    await _channel.sink.close(code, reason);
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  @override
  int? get closeCode => _channel.closeCode;
}

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'platform_interface.dart';

/// Browser `WebSocket` adapter backed by `package:web`.
class BrowserWebSocketAdapter implements PlatformWebSocket {
  static const Duration _connectTimeout = Duration(seconds: 15);

  final web.WebSocket _socket;
  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast();
  int? _closeCode;
  bool _isClosed = false;

  BrowserWebSocketAdapter._(this._socket);

  /// Connects to [url] over browser `ws:` or `wss:` WebSocket transport.
  static Future<BrowserWebSocketAdapter> connect(Uri url) async {
    if (url.scheme != 'ws' && url.scheme != 'wss') {
      throw ArgumentError.value(
        url.toString(),
        'url',
        'WebSocket URL must use ws:// or wss:// scheme',
      );
    }

    final socket = web.WebSocket(url.toString())..binaryType = 'arraybuffer';
    final adapter = BrowserWebSocketAdapter._(socket);
    final openCompleter = Completer<BrowserWebSocketAdapter>();

    socket.onopen = ((web.Event _) {
      if (!openCompleter.isCompleted) {
        openCompleter.complete(adapter);
      }
    }).toJS;

    socket.onmessage = ((web.MessageEvent event) {
      adapter._handleMessage(event.data);
    }).toJS;

    socket.onerror = ((web.Event _) {
      final error = StateError('WebSocket error on $url');
      if (!openCompleter.isCompleted) {
        openCompleter.completeError(error);
      } else if (!adapter._isClosed && !adapter._controller.isClosed) {
        adapter._controller.addError(error);
      }
    }).toJS;

    socket.onclose = ((web.CloseEvent event) {
      adapter._closeCode = event.code;
      adapter._isClosed = true;
      if (!openCompleter.isCompleted) {
        openCompleter.completeError(
          StateError(
            'WebSocket closed before open (code=${event.code}, reason=${event.reason})',
          ),
        );
      }
      if (!adapter._controller.isClosed) {
        unawaited(adapter._controller.close());
      }
    }).toJS;

    return openCompleter.future.timeout(
      _connectTimeout,
      onTimeout: () {
        adapter._isClosed = true;
        try {
          socket.close(1000, 'Connection timeout');
        } catch (_) {}
        if (!adapter._controller.isClosed) {
          unawaited(adapter._controller.close());
        }
        throw TimeoutException('Timed out connecting WebSocket to $url');
      },
    );
  }

  void _handleMessage(JSAny? raw) {
    if (_isClosed || _controller.isClosed) return;
    if (raw == null) return;

    if (raw.isA<JSString>()) {
      _controller.add((raw as JSString).toDart);
      return;
    }
    if (raw.isA<JSArrayBuffer>()) {
      _controller.add((raw as JSArrayBuffer).toDart.asUint8List());
      return;
    }
    if (raw.isA<web.Blob>()) {
      unawaited(
        (raw as web.Blob).arrayBuffer().toDart.then((buffer) {
          if (!_isClosed && !_controller.isClosed) {
            _controller.add(buffer.toDart.asUint8List());
          }
        }).catchError((Object e, StackTrace st) {
          if (!_isClosed && !_controller.isClosed) {
            _controller.addError(e, st);
          }
        }),
      );
      return;
    }

    _controller.add(raw.dartify());
  }

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void add(dynamic data) {
    if (_isClosed || _socket.readyState != web.WebSocket.OPEN) {
      throw StateError('Cannot send data: WebSocket is not open.');
    }
    if (data is String) {
      _socket.send(data.toJS);
    } else if (data is Uint8List) {
      _socket.send(data.toJS);
    } else if (data is ByteBuffer) {
      _socket.send(data.toJS);
    } else if (data is List<int>) {
      _socket.send(Uint8List.fromList(data).toJS);
    } else if (data != null) {
      _socket.send(data.toString().toJS);
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_isClosed) return;
    _isClosed = true;
    try {
      if (_socket.readyState == web.WebSocket.OPEN ||
          _socket.readyState == web.WebSocket.CONNECTING) {
        if (code != null && reason != null) {
          _socket.close(code, reason);
        } else if (code != null) {
          _socket.close(code);
        } else {
          _socket.close();
        }
      }
    } finally {
      if (!_controller.isClosed) {
        await _controller.close();
      }
    }
  }

  @override
  int? get closeCode => _closeCode;
}

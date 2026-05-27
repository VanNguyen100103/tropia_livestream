// Realtime channel cho 1 live session. Backend push 2 loại event:
//
//   {"type":"chat","message":{...}}    — new chat / bot reply
//   {"type":"stats","viewer_count":..} — counter snapshot + status
//
// Thay thế hoàn toàn `_chatTimer` 3s + `_statsTimer` 5s. Khi WS rớt,
// tự reconnect với exponential backoff (1s → 2s → 4s … cap 30s). Mỗi
// reconnect refetch một lần `/chat` để bù tin nhắn miss giữa
// disconnect + reconnect — đây là lý do vẫn cần endpoint REST cũ.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:tropia/core/config/app_config.dart';
import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

const _tag = 'LiveSocket';

class LiveEvent {
  final String type;
  final Map<String, dynamic> raw;
  LiveEvent(this.type, this.raw);
}

class LiveSocket {
  final String sessionId;
  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _sub;
  final _events = StreamController<LiveEvent>.broadcast();
  bool _closed = false;
  int _retryCount = 0;
  Timer? _reconnectTimer;

  LiveSocket(this.sessionId);

  Stream<LiveEvent> get events => _events.stream;

  /// True khi WS đã connect và đang nhận data. Provider có thể đọc để
  /// quyết định có cần fallback polling không (hiện tại không cần vì WS
  /// tự reconnect, nhưng giữ làm escape hatch).
  bool get isConnected => _ch != null && !_closed;

  void connect() {
    if (_closed) return;
    final base = AppConfig.backendUrl
        .replaceFirst(RegExp(r'^http'), 'ws'); // http→ws, https→wss
    final token = AuthService.instance.accessToken ?? '';
    final url = Uri.parse(
        '$base/api/live/streams/$sessionId/ws/chat?token=$token');
    try {
      final ch = WebSocketChannel.connect(url);
      _ch = ch;
      _sub = ch.stream.listen(
        _onMessage,
        onDone: _onDisconnect,
        onError: (e) {
          AppLogger.logError(_tag, 'ws error', e, null);
          _onDisconnect();
        },
        cancelOnError: true,
      );
      _retryCount = 0;
      AppLogger.logInfo(_tag, 'connected $sessionId');
    } catch (e) {
      AppLogger.logError(_tag, 'connect failed', e, null);
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    try {
      final m = jsonDecode(data) as Map<String, dynamic>;
      final type = m['type'] as String? ?? '';
      if (type.isEmpty) return;
      _events.add(LiveEvent(type, m));
    } catch (e) {
      AppLogger.logError(_tag, 'decode failed', e, null);
    }
  }

  void _onDisconnect() {
    _ch = null;
    _sub?.cancel();
    _sub = null;
    if (_closed) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnectTimer?.cancel();
    // Exponential backoff capped at 30s — same shape Shopee Live's
    // client uses. After ~5 retries we're at the cap, so a flaky
    // network doesn't burn CPU.
    final delay = Duration(
      seconds: (1 << _retryCount).clamp(1, 30),
    );
    _retryCount = (_retryCount + 1).clamp(0, 6);
    AppLogger.logInfo(_tag, 'reconnect in ${delay.inSeconds}s');
    _reconnectTimer = Timer(delay, connect);
  }

  void close() {
    _closed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    try {
      _ch?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _ch = null;
    _events.close();
  }
}

/// Platform-wide WS subscription. Backend pushes a tiny
/// `{"type":"list_change"}` envelope whenever a host creates/ends/edits
/// a session — client refetches `/streams` once on each event. Replaces
/// the 15s `_listTimer` polling.
///
/// Auto-reconnect with the same exponential-backoff shape as LiveSocket.
class LiveListSocket {
  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _sub;
  bool _closed = false;
  int _retryCount = 0;
  Timer? _reconnectTimer;
  VoidCallback? onChange;

  void connect() {
    if (_closed) return;
    final base = AppConfig.backendUrl.replaceFirst(RegExp(r'^http'), 'ws');
    final url = Uri.parse('$base/api/live/ws/list');
    try {
      final ch = WebSocketChannel.connect(url);
      _ch = ch;
      _sub = ch.stream.listen(
        (data) {
          if (data is! String) return;
          try {
            final m = jsonDecode(data) as Map<String, dynamic>;
            if (m['type'] == 'list_change') {
              onChange?.call();
            }
          } catch (_) {}
        },
        onDone: _onDisconnect,
        onError: (e) {
          AppLogger.logError(_tag, 'list ws error', e, null);
          _onDisconnect();
        },
        cancelOnError: true,
      );
      _retryCount = 0;
      AppLogger.logInfo(_tag, 'list ws connected');
    } catch (e) {
      AppLogger.logError(_tag, 'list ws connect failed', e, null);
      _scheduleReconnect();
    }
  }

  void _onDisconnect() {
    _ch = null;
    _sub?.cancel();
    _sub = null;
    if (_closed) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: (1 << _retryCount).clamp(1, 30));
    _retryCount = (_retryCount + 1).clamp(0, 6);
    _reconnectTimer = Timer(delay, connect);
  }

  void close() {
    _closed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    try {
      _ch?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _ch = null;
  }
}

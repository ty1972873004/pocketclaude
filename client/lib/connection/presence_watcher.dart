import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Lightweight relay connection that only watches for presence events.
/// Used by the device list to show online/offline status.
class PresenceWatcher {
  final String relayUrl;
  final String clientId;

  WebSocketChannel? _channel;
  final _onlineController = StreamController<PresenceEvent>.broadcast();
  bool _disposed = false;

  PresenceWatcher({required this.relayUrl, required this.clientId});

  Stream<PresenceEvent> get events => _onlineController.stream;

  Future<void> connect() async {
    if (_disposed) return;

    try {
      final uri = Uri.parse('$relayUrl/ws');
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      // Register
      _channel!.sink.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': 'reg',
        'method': 'device.register',
        'params': {
          'device_id': clientId,
          'device_type': 'client_watcher',
          'public_key': '',
        },
      }));

      _channel!.stream.listen(
        _onData,
        onError: (_) => _reconnect(),
        onDone: () => _reconnect(),
      );

      // Request current online list
      _channel!.sink.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': 'list',
        'method': 'device.list_online',
        'params': {},
      }));
    } catch (_) {
      _reconnect();
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    try {
      final msg = jsonDecode(data) as Map<String, dynamic>;
      final method = msg['method'] as String?;

      if (method == 'presence.online') {
        final params = msg['params'] as Map<String, dynamic>?;
        final deviceId = params?['device_id'] as String? ?? '';
        if (deviceId.isNotEmpty) {
          _onlineController.add(PresenceEvent.online(deviceId));
        }
      } else if (method == 'presence.offline') {
        final params = msg['params'] as Map<String, dynamic>?;
        final deviceId = params?['device_id'] as String? ?? '';
        if (deviceId.isNotEmpty) {
          _onlineController.add(PresenceEvent.offline(deviceId));
        }
      } else if (msg['id'] == 'list') {
        final result = msg['result'] as Map<String, dynamic>?;
        final devices = result?['devices'] as List? ?? [];
        for (final d in devices) {
          final map = d as Map<String, dynamic>;
          final deviceId = map['device_id'] as String? ?? '';
          if (deviceId.isNotEmpty && map['device_type'] != 'client_watcher') {
            _onlineController.add(PresenceEvent.online(deviceId));
          }
        }
      }
    } catch (_) {}
  }

  void _reconnect() {
    if (_disposed) return;
    Future.delayed(const Duration(seconds: 5), () {
      if (!_disposed) connect();
    });
  }

  void dispose() {
    _disposed = true;
    _channel?.sink.close();
    _onlineController.close();
  }
}

class PresenceEvent {
  final String deviceId;
  final bool online;

  const PresenceEvent._({required this.deviceId, required this.online});

  factory PresenceEvent.online(String id) =>
      PresenceEvent._(deviceId: id, online: true);
  factory PresenceEvent.offline(String id) =>
      PresenceEvent._(deviceId: id, online: false);
}

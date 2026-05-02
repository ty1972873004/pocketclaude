import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../crypto/encryption.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class JsonRpcMessage {
  final String? id;
  final String? method;
  final Map<String, dynamic>? params;
  final dynamic result;
  final dynamic error;

  JsonRpcMessage({
    this.id,
    this.method,
    this.params,
    this.result,
    this.error,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'jsonrpc': '2.0'};
    if (id != null) map['id'] = id;
    if (method != null) map['method'] = method;
    if (params != null) map['params'] = params;
    if (result != null) map['result'] = result;
    if (error != null) map['error'] = error;
    return map;
  }

  factory JsonRpcMessage.fromJson(Map<String, dynamic> json) {
    return JsonRpcMessage(
      id: json['id']?.toString(),
      method: json['method'],
      params: json['params'] != null
          ? Map<String, dynamic>.from(json['params'])
          : null,
      result: json['result'],
      error: json['error'],
    );
  }

  bool get isNotification => method != null && id == null;
  bool get isResponse => id != null && (result != null || error != null);
}

/// Decrypted inner message from the agent.
class DecryptedMessage {
  final String method;
  final Map<String, dynamic>? params;
  final dynamic result;
  final dynamic error;
  final String? id;

  DecryptedMessage({
    required this.method,
    this.params,
    this.result,
    this.error,
    this.id,
  });
}

/// Abstract base for connections to an agent (relay or direct).
/// Subclasses handle the transport layer; this class provides
/// encryption, decryption, heartbeat, and JSON-RPC framing.
abstract class ConnectionBase {
  final EncryptionService? encryption;

  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _messageController = StreamController<JsonRpcMessage>.broadcast();
  final _decryptedController = StreamController<DecryptedMessage>.broadcast();
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int _rpcId = 1;

  static const _maxReconnectAttempts = 10;

  ConnectionBase({this.encryption});

  // Public API
  ConnectionStatus get status => _status;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<JsonRpcMessage> get messageStream => _messageController.stream;
  Stream<DecryptedMessage> get decryptedStream => _decryptedController.stream;

  /// The URI to connect to. Subclasses provide this.
  Uri get wsUri;

  /// Optional registration message to send after connect. Null if not needed.
  Map<String, dynamic>? registrationMessage() => null;

  /// Whether to auto-reconnect on disconnect.
  bool get autoReconnect => true;

  /// Whether to decrypt relay-wrapped messages (relay mode).
  /// Direct connections get plaintext JSON-RPC directly.
  bool get decryptRelayMessages => true;

  void _setStatus(ConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  Future<void> connect() async {
    if (_status == ConnectionStatus.connected) return;

    _setStatus(ConnectionStatus.connecting);

    try {
      _channel = WebSocketChannel.connect(wsUri);
      await _channel!.ready;

      final reg = registrationMessage();
      if (reg != null) {
        _channel!.sink.add(jsonEncode(reg));
      }

      _setStatus(ConnectionStatus.connected);
      _reconnectAttempts = 0;

      _channel!.stream.listen(_onData, onError: _onError, onDone: _onDone);
      _startHeartbeat();
    } catch (e) {
      _setStatus(ConnectionStatus.error);
      if (autoReconnect) _scheduleReconnect();
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return;

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      _messageController.add(JsonRpcMessage.fromJson(json));

      if (decryptRelayMessages) {
        _handleRelayDecryption(json);
      } else {
        // Direct connection: messages ARE the inner JSON-RPC
        _decryptedController.add(DecryptedMessage(
          method: json['method'] as String? ?? '',
          params: json['params'] as Map<String, dynamic>?,
          result: json['result'],
          error: json['error'],
          id: json['id']?.toString(),
        ));
      }
    } catch (_) {}
  }

  void _handleRelayDecryption(Map<String, dynamic> msg) {
    final method = msg['method'] as String?;
    if (method != 'message.forward' && method != 'message.relay') return;
    if (encryption == null) return;

    final params = msg['params'] as Map<String, dynamic>?;
    if (params == null) return;

    final payload = params['encrypted_payload'];
    if (payload == null) return;

    try {
      Uint8List cipherBytes;
      if (payload is String) {
        cipherBytes = Uint8List.fromList(base64Decode(payload));
      } else if (payload is List) {
        cipherBytes = Uint8List.fromList(List<int>.from(payload));
      } else {
        return;
      }

      final decrypted = encryption!.decrypt(cipherBytes);
      final decryptedStr = utf8.decode(decrypted, allowMalformed: true);
      final innerMsg = jsonDecode(decryptedStr) as Map<String, dynamic>;

      _decryptedController.add(DecryptedMessage(
        method: innerMsg['method'] as String? ?? '',
        params: innerMsg['params'] as Map<String, dynamic>?,
        result: innerMsg['result'],
        error: innerMsg['error'],
        id: innerMsg['id']?.toString(),
      ));
    } catch (_) {}
  }

  void _onError(dynamic error) {
    _setStatus(ConnectionStatus.error);
    if (autoReconnect) _scheduleReconnect();
  }

  void _onDone() {
    _setStatus(ConnectionStatus.disconnected);
    if (autoReconnect) _scheduleReconnect();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => send(JsonRpcMessage(method: 'presence.heartbeat')),
    );
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _setStatus(ConnectionStatus.error);
      return;
    }

    _reconnectTimer?.cancel();
    final delay = Duration(seconds: 1 << _reconnectAttempts.clamp(0, 5));
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      connect();
    });
  }

  void send(JsonRpcMessage message) {
    if (_status != ConnectionStatus.connected || _channel == null) return;
    _channel!.sink.add(jsonEncode(message.toJson()));
  }

  /// Sends an encrypted JSON-RPC request to the agent.
  /// For relay: wraps in message.send with target_id.
  /// For direct: sends encrypted payload directly (agent decrypts).
  void sendEncrypted(Map<String, dynamic> request, String targetId) {
    if (_channel == null) return;

    if (!decryptRelayMessages && encryption != null) {
      // Direct mode: send encrypted payload directly
      final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(request)));
      final encrypted = encryption!.encrypt(plaintext);
      _channel!.sink.add(base64Encode(encrypted));
      return;
    }

    // Relay mode: encrypt and wrap in message.send
    if (encryption == null) return;

    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(request)));
    final encrypted = encryption!.encrypt(plaintext);

    _channel!.sink.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': '${_rpcId++}',
      'method': 'message.send',
      'params': {
        'target_id': targetId,
        'encrypted_payload': base64Encode(encrypted),
      },
    }));
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _setStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _messageController.close();
    _decryptedController.close();
  }
}

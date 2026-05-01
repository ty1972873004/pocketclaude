import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class RelayConnection {
  final String relayUrl;
  final String deviceId;
  final String deviceType;
  final EncryptionService? encryption;

  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _messageController = StreamController<JsonRpcMessage>.broadcast();
  final _rawDataController = StreamController<Uint8List>.broadcast();
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 10;

  RelayConnection({
    required this.relayUrl,
    required this.deviceId,
    this.deviceType = 'client',
    this.encryption,
  });

  ConnectionStatus get status => _status;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<JsonRpcMessage> get messageStream => _messageController.stream;
  Stream<Uint8List> get rawDataStream => _rawDataController.stream;

  void _setStatus(ConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  Future<void> connect() async {
    if (_status == ConnectionStatus.connected) return;

    _setStatus(ConnectionStatus.connecting);

    try {
      final uri = Uri.parse('$relayUrl/ws?device_id=$deviceId&type=$deviceType');
      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready;

      _setStatus(ConnectionStatus.connected);
      _reconnectAttempts = 0;

      _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );

      _startHeartbeat();
    } catch (e) {
      _setStatus(ConnectionStatus.error);
      _scheduleReconnect();
    }
  }

  void _onData(dynamic data) {
    if (data is String) {
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        _messageController.add(JsonRpcMessage.fromJson(json));
      } catch (_) {
        // Not JSON, ignore
      }
    } else if (data is List<int>) {
      _rawDataController.add(Uint8List.fromList(data));
    }
  }

  void _onError(dynamic error) {
    _setStatus(ConnectionStatus.error);
    _scheduleReconnect();
  }

  void _onDone() {
    _setStatus(ConnectionStatus.disconnected);
    _scheduleReconnect();
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

  void sendEncrypted(Uint8List plaintext, String targetId) {
    if (encryption == null) return;
    final encrypted = encryption!.encrypt(plaintext);
    send(JsonRpcMessage(
      method: 'message.send',
      params: {
        'target_id': targetId,
        'encrypted_payload': encrypted,
      },
    ));
  }

  Future<JsonRpcMessage> sendRequest(JsonRpcMessage message, {Duration timeout = const Duration(seconds: 30)}) async {
    final id = message.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final completer = Completer<JsonRpcMessage>();

    final sub = _messageController.stream
        .where((m) => m.id == id)
        .first
        .then(completer.complete);

    send(JsonRpcMessage(
      id: id,
      method: message.method,
      params: message.params,
    ));

    return completer.future.timeout(timeout, onTimeout: () {
      throw TimeoutException('Request $id timed out');
    });
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
    _rawDataController.close();
  }
}

final relayConnectionProvider = StateNotifierProvider<RelayConnectionNotifier, ConnectionStatus>((ref) {
  return RelayConnectionNotifier();
});

class RelayConnectionNotifier extends StateNotifier<ConnectionStatus> {
  RelayConnection? _connection;

  RelayConnectionNotifier() : super(ConnectionStatus.disconnected);

  Future<void> connect({
    required String relayUrl,
    required String deviceId,
    EncryptionService? encryption,
  }) async {
    _connection?.dispose();
    _connection = RelayConnection(
      relayUrl: relayUrl,
      deviceId: deviceId,
      encryption: encryption,
    );

    _connection!.statusStream.listen((status) {
      if (mounted) state = status;
    });

    await _connection!.connect();
  }

  RelayConnection? get connection => _connection;

  @override
  void dispose() {
    _connection?.dispose();
    super.dispose();
  }
}

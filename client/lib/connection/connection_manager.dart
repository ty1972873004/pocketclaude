import 'dart:async';

import 'connection_base.dart';
import 'direct_connection.dart';
import 'relay_connection.dart';
import '../crypto/encryption.dart';

/// Manages the connection strategy: try direct first, fall back to relay.
/// Exposes a single ConnectionBase that consumers use.
class ConnectionManager {
  final String relayUrl;
  final String deviceId;
  final String? directHost;
  final int directPort;
  final EncryptionService? encryption;

  ConnectionBase? _connection;
  ConnectionMode _mode = ConnectionMode.none;

  ConnectionManager({
    required this.relayUrl,
    required this.deviceId,
    this.directHost,
    this.directPort = 9090,
    this.encryption,
  });

  ConnectionBase? get connection => _connection;
  ConnectionMode get mode => _mode;

  /// Connects using the best available strategy.
  /// 1. If directHost is provided, try direct connection first.
  /// 2. Fall back to relay.
  Future<ConnectionBase> connect() async {
    // Try direct if we have a host
    if (directHost != null && directHost!.isNotEmpty) {
      try {
        final direct = DirectConnection(
          host: directHost!,
          port: directPort,
          encryption: encryption,
        );
        await direct.connect().timeout(const Duration(seconds: 5));
        if (direct.status == ConnectionStatus.connected) {
          _connection = direct;
          _mode = ConnectionMode.direct;
          return direct;
        }
      } catch (_) {
        // Direct failed, fall through to relay
      }
    }

    // Relay
    final relay = RelayConnection(
      relayUrl: relayUrl,
      deviceId: deviceId,
      encryption: encryption,
    );
    await relay.connect();
    _connection = relay;
    _mode = ConnectionMode.relay;
    return relay;
  }

  void dispose() {
    _connection?.dispose();
    _connection = null;
    _mode = ConnectionMode.none;
  }
}

enum ConnectionMode { none, direct, relay }

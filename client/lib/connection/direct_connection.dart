import 'connection_base.dart';
import '../crypto/encryption.dart';

/// Direct connection to the agent's local WebSocket API.
/// No relay registration needed. Messages are encrypted end-to-end
/// but sent directly (no message.send wrapper).
class DirectConnection extends ConnectionBase {
  final String host;
  final int port;

  DirectConnection({
    required this.host,
    required this.port,
    EncryptionService? encryption,
  }) : super(encryption: encryption);

  @override
  Uri get wsUri => Uri.parse('ws://$host:$port/ws');

  @override
  bool get decryptRelayMessages => false;

  @override
  Map<String, dynamic>? registrationMessage() => null;

  @override
  bool get autoReconnect => true;
}

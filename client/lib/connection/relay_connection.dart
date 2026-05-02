import 'connection_base.dart';
import '../crypto/encryption.dart';

/// Connection via relay server. Registers with relay, wraps messages
/// in message.send/message.forward, decrypts relayed payloads.
class RelayConnection extends ConnectionBase {
  final String relayUrl;
  final String deviceId;
  final String deviceType;

  RelayConnection({
    required this.relayUrl,
    required this.deviceId,
    this.deviceType = 'client',
    EncryptionService? encryption,
  }) : super(encryption: encryption);

  @override
  Uri get wsUri => Uri.parse('$relayUrl/ws');

  @override
  bool get decryptRelayMessages => true;

  @override
  Map<String, dynamic>? registrationMessage() => {
        'jsonrpc': '2.0',
        'id': 'register',
        'method': 'device.register',
        'params': {
          'device_id': deviceId,
          'device_type': deviceType,
          'public_key': '',
        },
      };
}

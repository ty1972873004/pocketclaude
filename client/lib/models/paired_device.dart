import 'dart:convert';

class PairedDevice {
  final String agentId;
  final String agentIP;
  final String relayUrl;
  final String agentX25519PubKey;
  final String agentEd25519PubKey;
  final String clientX25519PubKey;
  final String clientX25519PrivKey;
  final String sharedKeyBase64;
  final String deviceName;
  final int pairedAt;

  PairedDevice({
    required this.agentId,
    this.agentIP = '',
    required this.relayUrl,
    required this.agentX25519PubKey,
    this.agentEd25519PubKey = '',
    required this.clientX25519PubKey,
    required this.clientX25519PrivKey,
    required this.sharedKeyBase64,
    this.deviceName = 'Development Machine',
    required this.pairedAt,
  });

  Map<String, dynamic> toJson() => {
        'agent_id': agentId,
        'agent_ip': agentIP,
        'relay_url': relayUrl,
        'agent_x25519_pub_key': agentX25519PubKey,
        'agent_ed25519_pub_key': agentEd25519PubKey,
        'client_x25519_pub_key': clientX25519PubKey,
        'client_x25519_priv_key': clientX25519PrivKey,
        'shared_key_base64': sharedKeyBase64,
        'device_name': deviceName,
        'paired_at': pairedAt,
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        agentId: json['agent_id'] as String,
        agentIP: json['agent_ip'] as String? ?? '',
        relayUrl: json['relay_url'] as String,
        agentX25519PubKey: json['agent_x25519_pub_key'] as String,
        agentEd25519PubKey: json['agent_ed25519_pub_key'] as String? ?? '',
        clientX25519PubKey: json['client_x25519_pub_key'] as String,
        clientX25519PrivKey: json['client_x25519_priv_key'] as String,
        sharedKeyBase64: json['shared_key_base64'] as String,
        deviceName: json['device_name'] as String? ?? 'Development Machine',
        pairedAt: json['paired_at'] as int,
      );

  String toJsonString() => jsonEncode(toJson());

  static PairedDevice fromJsonString(String s) =>
      PairedDevice.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

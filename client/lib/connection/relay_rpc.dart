import 'dart:async';

import 'connection_base.dart';

/// Helper for services that send encrypted RPC and receive decrypted responses.
class RelayRpc {
  int _rpcId = 0;

  /// Sends an encrypted request and waits for the decrypted response matching the ID.
  Future<Map<String, dynamic>> call(
    ConnectionBase connection,
    String targetId,
    String method,
    Map<String, dynamic> params,
  ) async {
    _rpcId++;
    final id = 'rpc_$_rpcId';

    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final responseFuture = connection.decryptedStream
        .where((m) => m.id == id)
        .first
        .timeout(const Duration(seconds: 30));

    connection.sendEncrypted(request, targetId);

    final response = await responseFuture;

    if (response.error != null) {
      throw Exception('RPC error: ${response.error}');
    }

    return {'result': response.result};
  }
}

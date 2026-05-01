import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../connection/relay_connection.dart';
import '../../crypto/encryption.dart';
import '../../models/paired_device.dart';
import '../../storage/device_storage.dart';
import '../widgets/device_card.dart';

class DeviceListPage extends ConsumerStatefulWidget {
  const DeviceListPage({super.key});

  @override
  ConsumerState<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends ConsumerState<DeviceListPage> {
  List<PairedDevice> _devices = [];
  bool _loading = true;
  String? _connectError;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final devices = await DeviceStorage.loadDevices();
    if (mounted) {
      setState(() {
        _devices = devices;
        _loading = false;
      });
    }
  }

  Future<void> _connectToDevice(PairedDevice device) async {
    setState(() => _connectError = null);

    try {
      final sharedKey = base64Decode(device.sharedKeyBase64);
      final encryption = EncryptionService(
        Uint8List.fromList(sharedKey),
      );

      // Connect to relay
      final relayUrl = device.relayUrl;
      if (relayUrl.isEmpty) {
        throw Exception('设备未配置 Relay 地址，请到设置页配置');
      }

      final clientId = 'client-${DateTime.now().millisecondsSinceEpoch}';
      final uri = Uri.parse('$relayUrl/ws');
      final wsChannel = WebSocketChannel.connect(uri);
      await wsChannel.ready;

      // Register with relay
      final registerMsg = {
        'jsonrpc': '2.0',
        'id': 'register',
        'method': 'device.register',
        'params': {
          'device_id': clientId,
          'device_type': 'client',
          'public_key': device.clientX25519PubKey,
        },
      };
      wsChannel.sink.add(jsonEncode(registerMsg));

      // Wait for registration ack
      await wsChannel.stream.first
          .timeout(const Duration(seconds: 5));

      if (mounted) {
        // Pass connection details to session page via query params
        context.push('/session/${device.agentId}'
            '?relay_url=${Uri.encodeComponent(relayUrl)}'
            '&client_id=${Uri.encodeComponent(clientId)}'
            '&shared_key=${Uri.encodeComponent(device.sharedKeyBase64)}'
            '&device_name=${Uri.encodeComponent(device.deviceName)}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _connectError = '连接失败: $e');
      }
    }
  }

  Future<void> _removeDevice(PairedDevice device) async {
    await DeviceStorage.removeDevice(device.agentId);
    _loadDevices();
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus = ref.watch(relayConnectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PocketClaude'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await context.push('/settings');
              _loadDevices(); // reload in case relay URL changed
            },
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/pair');
          _loadDevices(); // reload after pairing
        },
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('添加设备'),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadDevices,
      child: CustomScrollView(
        slivers: [
          // Error banner
          if (_connectError != null)
            SliverToBoxAdapter(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.red.withOpacity(0.1),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_connectError!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 13)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () =>
                          setState(() => _connectError = null),
                    ),
                  ],
                ),
              ),
            ),

          // Devices section
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                '我的设备',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          if (_devices.isEmpty)
            SliverList(
              delegate: SliverChildListDelegate([
                _EmptyDevicePlaceholder(),
              ]),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final device = _devices[index];
                  return Dismissible(
                    key: Key(device.agentId),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => _removeDevice(device),
                    child: DeviceCard(
                      name: device.deviceName,
                      deviceId: device.agentId,
                      isOnline: false,
                      onTap: () => _connectToDevice(device),
                    ),
                  );
                },
                childCount: _devices.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyDevicePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => context.push('/pair'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.add_circle_outline,
                  size: 48,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withOpacity(0.5)),
              const SizedBox(height: 12),
              const Text('扫描 QR 码添加你的第一台开发机',
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

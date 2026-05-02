import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../connection/presence_watcher.dart';
import '../../models/paired_device.dart';
import '../../storage/device_storage.dart';
import '../widgets/device_card.dart';

class DeviceListPage extends StatefulWidget {
  const DeviceListPage({super.key});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> {
  List<PairedDevice> _devices = [];
  final Set<String> _onlineDeviceIds = {};
  bool _loading = true;
  String? _connectError;
  PresenceWatcher? _presenceWatcher;
  StreamSubscription<PresenceEvent>? _presenceSub;

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
      _startPresenceWatcher();
    }
  }

  void _startPresenceWatcher() {
    _presenceWatcher?.dispose();

    // Find a relay URL from any device
    final relayUrl = _devices
        .where((d) => d.relayUrl.isNotEmpty)
        .map((d) => d.relayUrl)
        .firstOrNull;
    if (relayUrl == null) return;

    _presenceWatcher = PresenceWatcher(
      relayUrl: relayUrl,
      clientId: 'watcher-${DateTime.now().millisecondsSinceEpoch}',
    );

    _presenceSub?.cancel();
    _presenceSub = _presenceWatcher!.events.listen((event) {
      if (!mounted) return;
      setState(() {
        if (event.online) {
          _onlineDeviceIds.add(event.deviceId);
        } else {
          _onlineDeviceIds.remove(event.deviceId);
        }
      });
    });

    _presenceWatcher!.connect();
  }

  Future<void> _connectToDevice(PairedDevice device) async {
    setState(() => _connectError = null);

    final relayUrl = device.relayUrl;
    if (relayUrl.isEmpty) {
      setState(() => _connectError = 'Device has no relay URL configured');
      return;
    }

    final clientId = 'client-${DateTime.now().millisecondsSinceEpoch}';

    if (mounted) {
      final directHost = device.tailscaleIP.isNotEmpty
          ? device.tailscaleIP
          : device.agentIP;

      context.push('/session/${device.agentId}'
          '?relay_url=${Uri.encodeComponent(relayUrl)}'
          '&client_id=${Uri.encodeComponent(clientId)}'
          '&shared_key=${Uri.encodeComponent(device.sharedKeyBase64)}'
          '&device_name=${Uri.encodeComponent(device.deviceName)}'
          '&direct_host=${Uri.encodeComponent(directHost)}'
          '&direct_port=${device.directPort}');
    }
  }

  Future<void> _removeDevice(PairedDevice device) async {
    await DeviceStorage.removeDevice(device.agentId);
    _loadDevices();
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    _presenceWatcher?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PocketClaude'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await context.push('/settings');
              _loadDevices();
            },
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/pair');
          _loadDevices();
        },
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Add Device'),
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
          if (_connectError != null)
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.red.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_connectError!,
                          style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _connectError = null),
                    ),
                  ],
                ),
              ),
            ),

          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                'My Devices',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          if (_devices.isEmpty)
            SliverList(
              delegate: SliverChildListDelegate([_EmptyDevicePlaceholder()]),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final device = _devices[index];
                  final isOnline = _onlineDeviceIds.contains(device.agentId);
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
                      isOnline: isOnline,
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
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              const Text('Scan QR code or paste pairing URL to add your first device',
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

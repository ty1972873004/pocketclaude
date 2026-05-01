import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _relayUrlKey = 'relay_url';
const _defaultRelayUrl = 'ws://relay.pocketclaude.dev:8080';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _relayUrl = _defaultRelayUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _relayUrl = prefs.getString(_relayUrlKey) ?? _defaultRelayUrl;
        _loading = false;
      });
    }
  }

  Future<void> _editRelayUrl() async {
    final controller = TextEditingController(text: _relayUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Relay 服务器地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'ws://host:port',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result != null && result.isNotEmpty && result != _relayUrl) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_relayUrlKey, result);
      if (mounted) {
        setState(() => _relayUrl = result);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relay 地址已保存，重新连接后生效')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _SectionHeader(title: '连接'),
          ListTile(
            leading: const Icon(Icons.cloud),
            title: const Text('Relay 服务器'),
            subtitle: _loading ? null : Text(_relayUrl),
            onTap: _editRelayUrl,
          ),
          ListTile(
            leading: const Icon(Icons.vpn_lock),
            title: const Text('直连模式'),
            subtitle: const Text('通过 Tailscale/ZeroTier 直连'),
            trailing: Switch(value: false, onChanged: (v) {}),
          ),

          _SectionHeader(title: '安全'),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('密钥管理'),
            subtitle: const Text('查看和管理加密密钥'),
            onTap: null,
          ),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('设备指纹'),
            subtitle: const Text('当前设备公钥指纹'),
            onTap: null,
          ),

          _SectionHeader(title: '已配对设备'),
          const ListTile(
            leading: Icon(Icons.devices),
            title: Text('暂无配对设备'),
            subtitle: Text('扫描 QR 码添加设备'),
          ),

          _SectionHeader(title: '关于'),
          const ListTile(
            leading: Icon(Icons.info),
            title: Text('PocketClaude'),
            subtitle: Text('v0.1.0'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

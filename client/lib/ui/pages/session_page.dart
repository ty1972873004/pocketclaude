import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../crypto/encryption.dart';

class SessionPage extends StatefulWidget {
  final String deviceId;

  const SessionPage({super.key, required this.deviceId});

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _outputLines = <String>[];

  WebSocketChannel? _channel;
  EncryptionService? _encryption;
  String? _clientId;
  String? _sessionId;
  bool _connecting = true;
  bool _isSending = false;
  String? _error;
  int _rpcId = 1;

  @override
  void initState() {
    super.initState();
    _initFromRoute();
  }

  void _initFromRoute() {
    // Extract query params passed from device list
    final state = GoRouterState.of(context);
    final relayUrl = state.uri.queryParameters['relay_url'] ?? '';
    final clientId = state.uri.queryParameters['client_id'] ?? '';
    final sharedKeyB64 = state.uri.queryParameters['shared_key'] ?? '';
    final deviceName = state.uri.queryParameters['device_name'] ?? widget.deviceId;

    if (relayUrl.isEmpty || sharedKeyB64.isEmpty) {
      setState(() {
        _connecting = false;
        _error = '缺少连接参数，请从设备列表重新进入';
      });
      return;
    }

    _clientId = clientId.isEmpty
        ? 'client-${DateTime.now().millisecondsSinceEpoch}'
        : clientId;

    _connectToRelay(relayUrl, sharedKeyB64);
  }

  Future<void> _connectToRelay(String relayUrl, String sharedKeyB64) async {
    try {
      final sharedKey = base64Decode(sharedKeyB64);
      _encryption = EncryptionService(Uint8List.fromList(sharedKey));

      final uri = Uri.parse('$relayUrl/ws');
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      // Register with relay
      _channel!.sink.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': 'register',
        'method': 'device.register',
        'params': {
          'device_id': _clientId,
          'device_type': 'client',
          'public_key': '',
        },
      }));

      // Listen for messages
      _channel!.stream.listen(
        _onData,
        onError: (e) => setState(() {
          _connecting = false;
          _error = '连接断开: $e';
        }),
        onDone: () {
          if (mounted) {
            setState(() {
              _connecting = false;
              _error = '连接已关闭';
            });
          }
        },
      );

      // Wait for registration ack then create session
      await Future.delayed(const Duration(seconds: 1));
      await _createSession();
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = '连接失败: $e';
        });
      }
    }
  }

  Future<void> _createSession() async {
    _sessionId = const Uuid().v4();
    final request = {
      'jsonrpc': '2.0',
      'id': '${_rpcId++}',
      'method': 'session.create',
      'params': {
        'session_id': _sessionId,
        'project_dir': '',
        'command': 'claude',
      },
    };

    _sendEncrypted(request);
    setState(() => _connecting = false);
  }

  void _sendEncrypted(Map<String, dynamic> request) {
    if (_encryption == null || _channel == null) return;

    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(request)));
    final encrypted = _encryption!.encrypt(plaintext);

    _channel!.sink.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': '${_rpcId++}',
      'method': 'message.send',
      'params': {
        'target_id': widget.deviceId,
        'encrypted_payload': base64Encode(encrypted),
      },
    }));
  }

  void _onData(dynamic data) {
    if (data is! String) return;

    try {
      final msg = jsonDecode(data) as Map<String, dynamic>;
      final method = msg['method'] as String?;

      if (method == 'message.forward' || method == 'message.relay') {
        final params = msg['params'] as Map<String, dynamic>?;
        if (params == null) return;

        final payload = params['encrypted_payload'];
        if (payload == null || _encryption == null) return;

        Uint8List cipherBytes;
        if (payload is String) {
          cipherBytes = Uint8List.fromList(base64Decode(payload));
        } else if (payload is List) {
          cipherBytes = Uint8List.fromList(List<int>.from(payload));
        } else {
          return;
        }

        final decrypted = _encryption!.decrypt(cipherBytes);
        final decryptedStr = utf8decode(decrypted);

        final innerMsg =
            jsonDecode(decryptedStr) as Map<String, dynamic>;
        final innerMethod = innerMsg['method'] as String?;

        if (innerMethod == 'session.on_output') {
          final p = innerMsg['params'] as Map<String, dynamic>?;
          final outputData = p?['data'] as String? ?? '';
          if (outputData.isNotEmpty && mounted) {
            setState(() {
              _outputLines.add(outputData);
            });
            _scrollToBottom();
          }
        }
      }
    } catch (e) {
      debugPrint('Message parse error: $e');
    }
  }

  String utf8decode(Uint8List bytes) {
    return utf8.decode(bytes, allowMalformed: true);
  }

  void _sendMessage() {
    final input = _inputController.text.trim();
    if (input.isEmpty || _sessionId == null) return;

    setState(() => _isSending = true);
    _inputController.clear();

    final request = {
      'jsonrpc': '2.0',
      'id': '${_rpcId++}',
      'method': 'session.send_input',
      'params': {
        'session_id': _sessionId,
        'input': input,
      },
    };

    _sendEncrypted(request);

    setState(() {
      _isSending = false;
      _outputLines.add('> $input');
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Claude Code', style: TextStyle(fontSize: 16)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _StatusBar(deviceId: widget.deviceId, connected: !_connecting && _error == null),
          Expanded(child: _buildOutput()),
          const _QuickActionBar(),
          _InputArea(
            controller: _inputController,
            isSending: _isSending,
            onSend: _sendMessage,
            enabled: !_connecting && _error == null,
          ),
        ],
      ),
    );
  }

  Widget _buildOutput() {
    if (_connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('返回设备列表'),
              ),
            ],
          ),
        ),
      );
    }

    if (_outputLines.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('输入 prompt 开始 coding',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _outputLines.length,
      itemBuilder: (context, index) {
        final line = _outputLines[index];
        final isInput = line.startsWith('> ');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: SelectableText(
            line,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.5,
              color: isInput ? const Color(0xFF6C63FF) : null,
            ),
          ),
        );
      },
    );
  }
}

class _StatusBar extends StatelessWidget {
  final String deviceId;
  final bool connected;

  const _StatusBar({required this.deviceId, required this.connected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: connected ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            deviceId.length > 12
                ? '${deviceId.substring(0, 12)}...'
                : deviceId,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const Spacer(),
          Text(
            connected ? '已连接' : '未连接',
            style: TextStyle(
              fontSize: 12,
              color: connected ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionBar extends StatelessWidget {
  const _QuickActionBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _QuickAction(icon: Icons.stop, label: 'Ctrl+C', onTap: () {}),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _InputArea extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final bool enabled;

  const _InputArea({
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
              color: Theme.of(context).dividerColor.withOpacity(0.3)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                    fontFamily: 'JetBrainsMono', fontSize: 14),
                decoration: InputDecoration(
                  hintText: '输入 prompt...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: enabled && !isSending ? onSend : null,
              icon: isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

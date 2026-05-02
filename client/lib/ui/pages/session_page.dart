import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../connection/connection_base.dart';
import '../../connection/connection_manager.dart';
import '../../crypto/encryption.dart';
import '../../session/session_context.dart';
import '../../session/session_service.dart';
import '../../terminal/markdown_renderer.dart';
import '../widgets/session_tab_bar.dart';

class SessionPage extends StatefulWidget {
  final String deviceId;

  const SessionPage({super.key, required this.deviceId});

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  ConnectionManager? _connectionManager;
  ConnectionBase? _connection;
  SessionService? _sessionService;
  final Map<String, ClaudeSession> _sessions = {};
  String? _activeSessionId;
  bool _connecting = true;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initFromRoute();
  }

  void _initFromRoute() {
    final state = GoRouterState.of(context);
    final relayUrl = state.uri.queryParameters['relay_url'] ?? '';
    final clientId = state.uri.queryParameters['client_id'] ?? '';
    final sharedKeyB64 = state.uri.queryParameters['shared_key'] ?? '';

    if (relayUrl.isEmpty || sharedKeyB64.isEmpty) {
      setState(() {
        _connecting = false;
        _error = 'Missing connection parameters, please re-enter from device list';
      });
      return;
    }

    final effectiveClientId = clientId.isEmpty
        ? 'client-${DateTime.now().millisecondsSinceEpoch}'
        : clientId;

    final directHost = state.uri.queryParameters['direct_host'] ?? '';
    final directPort = int.tryParse(state.uri.queryParameters['direct_port'] ?? '') ?? 9090;

    _connect(relayUrl, sharedKeyB64, effectiveClientId, directHost, directPort);
  }

  Future<void> _connect(
    String relayUrl,
    String sharedKeyB64,
    String clientId,
    String directHost,
    int directPort,
  ) async {
    try {
      final sharedKey = base64Decode(sharedKeyB64);
      final encryption = EncryptionService(Uint8List.fromList(sharedKey));

      _connectionManager = ConnectionManager(
        relayUrl: relayUrl,
        deviceId: clientId,
        directHost: directHost.isNotEmpty ? directHost : null,
        directPort: directPort,
        encryption: encryption,
      );

      _connection = await _connectionManager!.connect();

      _connection!.statusStream.listen((status) {
        if (!mounted) return;
        if (status == ConnectionStatus.error) {
          setState(() {
            _connecting = false;
            _error = 'Connection error';
          });
        }
      });

      _sessionService = SessionService(_connection!);

      await _createNewSession();

      if (!mounted) return;
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Connection failed: $e';
        });
      }
    }
  }

  void _sendMessage() {
    final input = _inputController.text.trim();
    final session = _activeSession != null ? _sessions[_activeSessionId] : null;
    if (input.isEmpty || _sessionService == null || _activeSessionId == null) return;

    setState(() => _isSending = true);
    _inputController.clear();

    _sessionService!.sendInput(_activeSessionId!, input);

    setState(() => _isSending = false);
    _scrollToBottom();
  }

  ClaudeSession? get _activeSession =>
      _activeSessionId != null ? _sessions[_activeSessionId] : null;

  Future<void> _createNewSession() async {
    if (_sessionService == null) return;

    final session = await _sessionService!.createSession(
      deviceId: widget.deviceId,
      command: 'claude',
    );

    if (!mounted) return;

    setState(() {
      _sessions[session.id] = session;
      _activeSessionId = session.id;
      _connecting = false;
    });

    session.outputBuffer.changeNotifier.addListener(_scrollToBottom);
  }

  void _switchSession(String sessionId) {
    if (!_sessions.containsKey(sessionId)) return;
    setState(() => _activeSessionId = sessionId);
    _scrollToBottom();
  }

  void _closeSession(String sessionId) {
    final session = _sessions[sessionId];
    session?.outputBuffer.changeNotifier.removeListener(_scrollToBottom);
    _sessionService?.destroySession(sessionId);

    setState(() {
      _sessions.remove(sessionId);
      if (_activeSessionId == sessionId) {
        _activeSessionId = _sessions.keys.isNotEmpty ? _sessions.keys.first : null;
      }
    });
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
    for (final s in _sessions.values) {
      s.outputBuffer.changeNotifier.removeListener(_scrollToBottom);
    }
    _connectionManager?.dispose();
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
          _StatusBar(
            deviceId: widget.deviceId,
            connected: !_connecting && _error == null,
          ),
          if (_sessions.length > 1)
            SessionTabBar(
              tabs: _sessions.entries.map((e) => SessionTab(
                sessionId: e.key,
                label: 'Session ${_sessionIndex(e.key)}',
              )).toList(),
              activeSessionId: _activeSessionId ?? '',
              onTabSelected: _switchSession,
              onNewSession: _createNewSession,
              onCloseSession: _closeSession,
            ),
          Expanded(child: _buildOutput()),
          _QuickActionBar(
            sessionContext: _connection != null
                ? SessionContext(connection: _connection!, targetDeviceId: widget.deviceId)
                : null,
            projectDir: _activeSession?.projectDir ?? '',
          ),
          _InputArea(
            controller: _inputController,
            isSending: _isSending,
            onSend: _sendMessage,
            enabled: !_connecting && _error == null && _activeSessionId != null,
          ),
        ],
      ),
    );
  }

  int _sessionIndex(String id) {
    final keys = _sessions.keys.toList();
    return keys.indexOf(id) + 1;
  }

  Widget _buildOutput() {
    if (_connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connecting...', style: TextStyle(color: Colors.grey)),
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
                child: const Text('Return to Device List'),
              ),
            ],
          ),
        ),
      );
    }

    final session = _activeSession;
    if (session == null) {
      return const SizedBox.shrink();
    }

    return MarkdownRenderer(
      buffer: session.outputBuffer,
      scrollController: _scrollController,
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
            connected ? 'Connected' : 'Disconnected',
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
  final SessionContext? sessionContext;
  final String projectDir;

  const _QuickActionBar({this.sessionContext, this.projectDir = ''});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _QuickAction(
            icon: Icons.folder_open,
            label: 'Files',
            onTap: sessionContext != null
                ? () => context.push(
                      '/session/${sessionContext!.targetDeviceId}/files',
                      extra: sessionContext,
                    )
                : () {},
          ),
          _QuickAction(
            icon: Icons.call_split,
            label: 'Git',
            onTap: sessionContext != null
                ? () => context.push(
                      '/session/${sessionContext!.targetDeviceId}/git',
                      extra: GitRouteArgs(
                        sessionContext: sessionContext!,
                        projectDir: projectDir,
                      ),
                    )
                : () {},
          ),
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
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter):
            const _SendIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.enter):
            const _SendIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SendIntent: _SendAction(onSend),
        },
        child: Container(
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
                      hintText: 'Enter prompt...',
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
        ),
      ),
    );
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}

class _SendAction extends Action<_SendIntent> {
  final VoidCallback onSend;

  _SendAction(this.onSend);

  @override
  Object? invoke(_SendIntent intent) {
    onSend();
    return null;
  }
}

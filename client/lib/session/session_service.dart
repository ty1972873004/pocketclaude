import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../connection/relay_connection.dart';

enum SessionStatus { idle, running, waitingInput, error }

class ClaudeSession {
  final String id;
  final String deviceId;
  final String? projectDir;
  SessionStatus status;
  final StreamController<String> _outputController = StreamController<String>.broadcast();
  final List<String> _outputBuffer = [];

  ClaudeSession({
    required this.id,
    required this.deviceId,
    this.projectDir,
    this.status = SessionStatus.idle,
  });

  Stream<String> get outputStream => _outputController.stream;
  List<String> get outputBuffer => List.unmodifiable(_outputBuffer);

  void appendOutput(String data) {
    _outputBuffer.add(data);
    _outputController.add(data);
  }

  void clearBuffer() {
    _outputBuffer.clear();
  }

  void dispose() {
    _outputController.close();
  }
}

class SessionService {
  final RelayConnection _connection;
  final Map<String, ClaudeSession> _sessions = {};

  SessionService(this._connection);

  List<ClaudeSession> get sessions => _sessions.values.toList();
  ClaudeSession? getSession(String id) => _sessions[id];

  Future<ClaudeSession> createSession({
    required String deviceId,
    String? projectDir,
    String command = 'claude',
  }) async {
    final sessionId = const Uuid().v4();

    final response = await _connection.sendRequest(JsonRpcMessage(
      method: 'session.create',
      params: {
        'session_id': sessionId,
        'device_id': deviceId,
        'project_dir': projectDir,
        'command': command,
      },
    ));

    if (response.error != null) {
      throw Exception('Failed to create session: ${response.error}');
    }

    final session = ClaudeSession(
      id: sessionId,
      deviceId: deviceId,
      projectDir: projectDir,
      status: SessionStatus.running,
    );

    _sessions[sessionId] = session;

    // Listen for output from this session
    _connection.messageStream
        .where((m) => m.method == 'session.on_output' && m.params?['session_id'] == sessionId)
        .listen((m) {
      final data = m.params?['data'] as String? ?? '';
      final type = m.params?['type'] as String? ?? 'stream';
      session.appendOutput(data);

      if (type == 'error') {
        session.status = SessionStatus.error;
      }
    });

    return session;
  }

  Future<void> sendInput(String sessionId, String input) async {
    final session = _sessions[sessionId];
    if (session == null) throw Exception('Session not found: $sessionId');

    _connection.send(JsonRpcMessage(
      method: 'session.send_input',
      params: {
        'session_id': sessionId,
        'input': input,
      },
    ));
  }

  Future<void> destroySession(String sessionId) async {
    _connection.send(JsonRpcMessage(
      method: 'session.destroy',
      params: {'session_id': sessionId},
    ));

    _sessions[sessionId]?.dispose();
    _sessions.remove(sessionId);
  }

  Future<List<ClaudeSession>> listSessions() async {
    final response = await _connection.sendRequest(JsonRpcMessage(
      method: 'session.list',
      params: {},
    ));

    if (response.result != null) {
      final list = response.result as List;
      for (final s in list) {
        final map = s as Map<String, dynamic>;
        if (!_sessions.containsKey(map['session_id'])) {
          _sessions[map['session_id']] = ClaudeSession(
            id: map['session_id'],
            deviceId: map['device_id'] ?? '',
            projectDir: map['project_dir'],
            status: _parseStatus(map['status']),
          );
        }
      }
    }

    return sessions;
  }

  SessionStatus _parseStatus(String? status) {
    switch (status) {
      case 'running': return SessionStatus.running;
      case 'waiting_input': return SessionStatus.waitingInput;
      case 'error': return SessionStatus.error;
      default: return SessionStatus.idle;
    }
  }

  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }
}

final sessionServiceProvider = Provider<SessionService?>((ref) {
  final connectionStatus = ref.watch(relayConnectionProvider);
  if (connectionStatus != ConnectionStatus.connected) return null;

  final connectionNotifier = ref.read(relayConnectionProvider.notifier);
  return SessionService(connectionNotifier.connection!);
});

final sessionsProvider = StateNotifierProvider<SessionsNotifier, AsyncValue<List<ClaudeSession>>>((ref) {
  return SessionsNotifier(ref);
});

class SessionsNotifier extends StateNotifier<AsyncValue<List<ClaudeSession>>> {
  final Ref _ref;

  SessionsNotifier(this._ref) : super(const AsyncValue.data([]));

  Future<void> createSession(String deviceId, {String? projectDir}) async {
    try {
      final service = _ref.read(sessionServiceProvider);
      if (service == null) return;

      final session = await service.createSession(
        deviceId: deviceId,
        projectDir: projectDir,
      );

      state = AsyncValue.data([...?state.value, session]);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> sendInput(String sessionId, String input) async {
    final service = _ref.read(sessionServiceProvider);
    await service?.sendInput(sessionId, input);
  }

  Future<void> destroySession(String sessionId) async {
    final service = _ref.read(sessionServiceProvider);
    await service?.destroySession(sessionId);

    state = AsyncValue.data(
      state.value?.where((s) => s.id != sessionId).toList() ?? [],
    );
  }
}

import 'dart:async';

import 'package:uuid/uuid.dart';

import '../connection/connection_base.dart';
import '../terminal/output_buffer.dart';
import '../terminal/output_parser.dart';

enum SessionStatus { idle, running, waitingInput, error }

class ClaudeSession {
  final String id;
  final String deviceId;
  final String? projectDir;
  SessionStatus status;
  final OutputBuffer outputBuffer;
  final OutputParser outputParser;
  StreamSubscription<DecryptedMessage>? _subscription;

  ClaudeSession({
    required this.id,
    required this.deviceId,
    this.projectDir,
    this.status = SessionStatus.idle,
  }) : outputBuffer = OutputBuffer(),
       outputParser = OutputParser();

  void bindOutput(Stream<DecryptedMessage> decryptedStream) {
    _subscription?.cancel();
    _subscription = decryptedStream
        .where((m) => m.method == 'session.on_output')
        .where((m) => m.params != null)
        .listen((m) {
      final data = m.params?['data'] as String? ?? '';
      if (data.isEmpty) return;
      final chunks = outputParser.feed(data);
      outputBuffer.appendAll(chunks);

      final type = m.params?['type'] as String? ?? 'stream';
      if (type == 'error') {
        status = SessionStatus.error;
      }
    });
  }

  void appendUserInput(String input) {
    final chunks = outputParser.feed('> $input\n');
    outputBuffer.appendAll(chunks);
  }

  void dispose() {
    _subscription?.cancel();
    outputBuffer.dispose();
  }
}

class SessionService {
  final ConnectionBase _connection;
  final Map<String, ClaudeSession> _sessions = {};
  int _rpcId = 1;

  SessionService(this._connection);

  List<ClaudeSession> get sessions => _sessions.values.toList();
  ClaudeSession? getSession(String id) => _sessions[id];

  Future<ClaudeSession> createSession({
    required String deviceId,
    String? projectDir,
    String command = 'claude',
  }) async {
    final sessionId = const Uuid().v4();

    final request = {
      'jsonrpc': '2.0',
      'id': 'session_create_${_rpcId++}',
      'method': 'session.create',
      'params': {
        'session_id': sessionId,
        'project_dir': projectDir ?? '',
        'command': command,
      },
    };

    _connection.sendEncrypted(request, deviceId);

    final session = ClaudeSession(
      id: sessionId,
      deviceId: deviceId,
      projectDir: projectDir,
      status: SessionStatus.running,
    );

    session.bindOutput(_connection.decryptedStream);
    _sessions[sessionId] = session;

    return session;
  }

  Future<void> sendInput(String sessionId, String input) async {
    final session = _sessions[sessionId];
    if (session == null) throw Exception('Session not found: $sessionId');

    final request = {
      'jsonrpc': '2.0',
      'id': 'input_${_rpcId++}',
      'method': 'session.send_input',
      'params': {
        'session_id': sessionId,
        'input': input,
      },
    };

    _connection.sendEncrypted(request, session.deviceId);
    session.appendUserInput(input);
  }

  Future<void> destroySession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return;

    final request = {
      'jsonrpc': '2.0',
      'id': 'destroy_${_rpcId++}',
      'method': 'session.destroy',
      'params': {
        'session_id': sessionId,
      },
    };

    _connection.sendEncrypted(request, session.deviceId);
    session.dispose();
    _sessions.remove(sessionId);
  }

  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }
}

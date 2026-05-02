import '../connection/connection_base.dart';
import '../connection/relay_rpc.dart';
import 'git_models.dart';

class GitService {
  final ConnectionBase _connection;
  final String _targetId;
  final _rpc = RelayRpc();

  GitService(this._connection, this._targetId);

  Future<GitStatusResult> status(String dir) async {
    final resp = await _rpc.call(_connection, _targetId, 'git.status', {
      'dir': dir,
    });
    return GitStatusResult.fromJson(resp['result'] as Map<String, dynamic>);
  }

  Future<GitDiffResult> diff(String dir, {bool cached = false}) async {
    final resp = await _rpc.call(_connection, _targetId, 'git.diff', {
      'dir': dir,
      'cached': cached,
    });
    return GitDiffResult.fromJson(resp['result'] as Map<String, dynamic>);
  }

  Future<GitLogResult> log(String dir) async {
    final resp = await _rpc.call(_connection, _targetId, 'git.log', {
      'dir': dir,
    });
    return GitLogResult.fromJson(resp['result'] as Map<String, dynamic>);
  }
}

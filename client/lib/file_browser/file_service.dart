import '../connection/connection_base.dart';
import '../connection/relay_rpc.dart';
import 'file_models.dart';

class FileService {
  final ConnectionBase _connection;
  final String _targetId;
  final _rpc = RelayRpc();

  FileService(this._connection, this._targetId);

  Future<ReadDirResult> readDir([String path = '']) async {
    final resp = await _rpc.call(_connection, _targetId, 'fs.read_dir', {
      'path': path,
    });
    return ReadDirResult.fromJson(resp['result'] as Map<String, dynamic>);
  }

  Future<FileContent> readFile(String path) async {
    final resp = await _rpc.call(_connection, _targetId, 'fs.read_file', {
      'path': path,
    });
    return FileContent.fromJson(resp['result'] as Map<String, dynamic>);
  }

  Future<bool> writeFile(String path, String content) async {
    final resp = await _rpc.call(_connection, _targetId, 'fs.write_file', {
      'path': path,
      'content': content,
    });
    return resp['result']?['success'] == true;
  }
}

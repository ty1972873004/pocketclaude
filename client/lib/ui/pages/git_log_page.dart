import 'package:flutter/material.dart';

import '../../git_view/git_models.dart';
import '../../git_view/git_service.dart';
import '../../session/session_context.dart';

class GitLogPage extends StatefulWidget {
  final SessionContext sessionContext;
  final String projectDir;

  const GitLogPage({
    super.key,
    required this.sessionContext,
    required this.projectDir,
  });

  @override
  State<GitLogPage> createState() => _GitLogPageState();
}

class _GitLogPageState extends State<GitLogPage> {
  late final GitService _gitService;
  GitLogResult? _log;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gitService = GitService(
      widget.sessionContext.connection,
      widget.sessionContext.targetDeviceId,
    );
    _loadLog();
  }

  Future<void> _loadLog() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final log = await _gitService.log(widget.projectDir);
      if (!mounted) return;
      setState(() {
        _log = log;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load log: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Git Log', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadLog),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadLog, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_log == null || _log!.entries.isEmpty) {
      return const Center(
        child: Text('No commits', style: TextStyle(color: Colors.grey)),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLog,
      child: ListView.builder(
        itemCount: _log!.entries.length,
        itemBuilder: (context, index) {
          final entry = _log!.entries[index];
          return _buildLogEntry(entry);
        },
      ),
    );
  }

  Widget _buildLogEntry(GitLogEntry entry) {
    return ListTile(
      dense: true,
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          entry.hash,
          style: const TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
      ),
      title: Text(
        entry.message,
        style: const TextStyle(fontSize: 14),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: entry.author.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${entry.author} · ${entry.date}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            )
          : null,
    );
  }
}

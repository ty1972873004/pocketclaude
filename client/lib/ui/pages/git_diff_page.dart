import 'package:flutter/material.dart';

import '../../git_view/git_models.dart';
import '../../git_view/git_service.dart';
import '../../session/session_context.dart';

class GitDiffPage extends StatefulWidget {
  final SessionContext sessionContext;
  final String projectDir;

  const GitDiffPage({
    super.key,
    required this.sessionContext,
    required this.projectDir,
  });

  @override
  State<GitDiffPage> createState() => _GitDiffPageState();
}

class _GitDiffPageState extends State<GitDiffPage> {
  late final GitService _gitService;
  GitDiffResult? _diff;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gitService = GitService(
      widget.sessionContext.connection,
      widget.sessionContext.targetDeviceId,
    );
    _loadDiff();
  }

  Future<void> _loadDiff() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final diff = await _gitService.diff(widget.projectDir);
      if (!mounted) return;
      setState(() {
        _diff = diff;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load diff: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Git Diff', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDiff),
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
            ElevatedButton(onPressed: _loadDiff, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_diff == null || !_diff!.hasChanges) {
      return const Center(
        child: Text('No changes', style: TextStyle(color: Colors.grey)),
      );
    }

    final lines = _diff!.diff.split('\n');

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        return _buildDiffLine(line);
      },
    );
  }

  Widget _buildDiffLine(String line) {
    Color? bgColor;
    Color textColor = Colors.grey;

    if (line.startsWith('diff ') || line.startsWith('---') || line.startsWith('+++')) {
      bgColor = Theme.of(context).colorScheme.surfaceContainerHighest;
      textColor = Colors.white;
    } else if (line.startsWith('@@')) {
      bgColor = Colors.blue.withValues(alpha: 0.1);
      textColor = Colors.blue;
    } else if (line.startsWith('+')) {
      bgColor = Colors.green.withValues(alpha: 0.1);
      textColor = Colors.green;
    } else if (line.startsWith('-')) {
      bgColor = Colors.red.withValues(alpha: 0.1);
      textColor = Colors.red;
    }

    return Container(
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Text(
        line,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 12,
          height: 1.4,
          color: textColor,
        ),
      ),
    );
  }
}

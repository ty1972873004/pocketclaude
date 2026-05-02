import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../git_view/git_models.dart';
import '../../git_view/git_service.dart';
import '../../session/session_context.dart';

class GitStatusPage extends StatefulWidget {
  final SessionContext sessionContext;
  final String projectDir;

  const GitStatusPage({
    super.key,
    required this.sessionContext,
    required this.projectDir,
  });

  @override
  State<GitStatusPage> createState() => _GitStatusPageState();
}

class _GitStatusPageState extends State<GitStatusPage> {
  late final GitService _gitService;
  GitStatusResult? _status;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gitService = GitService(
      widget.sessionContext.connection,
      widget.sessionContext.targetDeviceId,
    );
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final status = await _gitService.status(widget.projectDir);
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load git status: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Git Status', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadStatus),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'diff':
                  context.push(
                    '/session/${widget.sessionContext.targetDeviceId}/git-diff',
                    extra: GitRouteArgs(
                      sessionContext: widget.sessionContext,
                      projectDir: widget.projectDir,
                    ),
                  );
                case 'log':
                  context.push(
                    '/session/${widget.sessionContext.targetDeviceId}/git-log',
                    extra: GitRouteArgs(
                      sessionContext: widget.sessionContext,
                      projectDir: widget.projectDir,
                    ),
                  );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'diff', child: Text('View Diff')),
              const PopupMenuItem(value: 'log', child: Text('View Log')),
            ],
          ),
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
            ElevatedButton(onPressed: _loadStatus, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_status == null) return const SizedBox.shrink();

    return RefreshIndicator(
      onRefresh: _loadStatus,
      child: CustomScrollView(
        slivers: [
          // Branch header
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  const Icon(Icons.call_split, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _status!.branch.isEmpty ? 'No branch' : _status!.branch,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_status!.clean)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Clean',
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),

          if (_status!.files.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text('No changes', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final file = _status!.files[index];
                  final code = GitStatusResult.parseStatusCode(file);
                  final name = GitStatusResult.parseFileName(file);
                  return ListTile(
                    dense: true,
                    leading: _statusBadge(code),
                    title: Text(name, style: const TextStyle(fontSize: 14, fontFamily: 'JetBrainsMono')),
                  );
                },
                childCount: _status!.files.length,
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(String code) {
    Color color;
    switch (code) {
      case 'M' || 'MM' || 'AM':
        color = Colors.orange;
      case 'A':
        color = Colors.green;
      case 'D':
        color = Colors.red;
      case 'R':
        color = Colors.blue;
      case 'C':
        color = Colors.purple;
      case '?':
        color = Colors.grey;
      default:
        color = Colors.grey;
    }

    return Container(
      width: 28,
      height: 20,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        code.isEmpty ? '?' : code,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../connection/connection_base.dart';
import '../../file_browser/file_service.dart';
import '../../file_browser/file_models.dart';
import '../../file_browser/language_detector.dart';
import '../../session/session_context.dart';

class FileBrowserPage extends StatefulWidget {
  final SessionContext sessionContext;

  const FileBrowserPage({super.key, required this.sessionContext});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  late final FileService _fileService;
  List<DirEntry> _entries = [];
  String _currentPath = '';
  final List<String> _pathStack = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fileService = FileService(
      widget.sessionContext.connection,
      widget.sessionContext.targetDeviceId,
    );
    _loadDir('');
  }

  Future<void> _loadDir(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _fileService.readDir(path);
      if (!mounted) return;

      // Sort: directories first, then files, alphabetically
      final entries = result.entries.toList()
        ..sort((a, b) {
          if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

      setState(() {
        _currentPath = result.path;
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load: $e';
          _loading = false;
        });
      }
    }
  }

  void _navigateInto(DirEntry entry) {
    if (!entry.isDir) {
      context.push(
        '/session/${widget.sessionContext.targetDeviceId}/file-preview',
        extra: FilePreviewArgs(
          sessionContext: widget.sessionContext,
          filePath: entry.path,
          fileName: entry.name,
        ),
      );
      return;
    }

    _pathStack.add(_currentPath);
    _loadDir(entry.path);
  }

  bool _navigateUp() {
    if (_pathStack.isEmpty) return false;
    final parent = _pathStack.removeLast();
    _loadDir(parent);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _pathStack.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _navigateUp();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Files', style: TextStyle(fontSize: 16)),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (!_navigateUp()) context.pop();
            },
          ),
        ),
        body: Column(
          children: [
            _buildBreadcrumb(),
            Expanded(child: _buildFileList()),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final segments = _currentPath.split('/').where((s) => s.isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _breadcrumbChip('/', () => _loadDir('')),
            for (int i = 0; i < segments.length; i++) ...[
              const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
              _breadcrumbChip(
                segments[i],
                () => _loadDir('/${segments.sublist(0, i + 1).join('/')}'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _breadcrumbChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildFileList() {
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
            ElevatedButton(onPressed: () => _loadDir(_currentPath), child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_entries.isEmpty) {
      return const Center(
        child: Text('Empty directory', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return ListTile(
          dense: true,
          leading: Icon(
            entry.isDir ? Icons.folder : _fileIcon(entry.name),
            size: 20,
            color: entry.isDir ? Colors.amber : Colors.grey,
          ),
          title: Text(entry.name, style: const TextStyle(fontSize: 14)),
          subtitle: _currentPath.isEmpty ? null : null,
          trailing: entry.isDir
              ? const Icon(Icons.chevron_right, size: 16)
              : Text(
                  _formatSize(entry.size),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
          onTap: () => _navigateInto(entry),
        );
      },
    );
  }

  IconData _fileIcon(String name) {
    final lang = detectLanguage(name);
    switch (lang) {
      case 'json':
      case 'yaml':
        return Icons.settings;
      case 'markdown':
        return Icons.description;
      case 'dart':
      case 'go':
      case 'python':
      case 'javascript':
      case 'typescript':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class FilePreviewPage extends StatefulWidget {
  final SessionContext sessionContext;
  final String filePath;
  final String fileName;

  const FilePreviewPage({
    super.key,
    required this.sessionContext,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  late final FileService _fileService;
  String _content = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fileService = FileService(
      widget.sessionContext.connection,
      widget.sessionContext.targetDeviceId,
    );
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final result = await _fileService.readFile(widget.filePath);
      if (!mounted) return;
      setState(() {
        _content = result.content;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load file: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName, style: const TextStyle(fontSize: 14)),
        centerTitle: true,
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
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadFile, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        _content,
        style: const TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}

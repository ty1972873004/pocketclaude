class DirEntry {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final String mode;

  const DirEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
    this.mode = '',
  });

  factory DirEntry.fromJson(Map<String, dynamic> json) {
    return DirEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      isDir: json['is_dir'] as bool? ?? false,
      size: json['size'] as int? ?? 0,
      mode: json['mode'] as String? ?? '',
    );
  }
}

class ReadDirResult {
  final String path;
  final List<DirEntry> entries;

  const ReadDirResult({required this.path, required this.entries});

  factory ReadDirResult.fromJson(Map<String, dynamic> json) {
    final list = (json['entries'] as List?) ?? [];
    return ReadDirResult(
      path: json['path'] as String? ?? '/',
      entries: list.map((e) => DirEntry.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class FileContent {
  final String path;
  final String content;
  final int size;

  const FileContent({required this.path, required this.content, this.size = 0});

  factory FileContent.fromJson(Map<String, dynamic> json) {
    return FileContent(
      path: json['path'] as String? ?? '',
      content: json['content'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}

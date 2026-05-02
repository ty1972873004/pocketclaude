class GitStatusResult {
  final String dir;
  final String branch;
  final List<String> files;
  final bool clean;
  final String raw;

  const GitStatusResult({
    required this.dir,
    this.branch = '',
    this.files = const [],
    this.clean = true,
    this.raw = '',
  });

  factory GitStatusResult.fromJson(Map<String, dynamic> json) {
    return GitStatusResult(
      dir: json['dir'] as String? ?? '',
      branch: json['branch'] as String? ?? '',
      files: (json['files'] as List?)?.cast<String>() ?? [],
      clean: json['clean'] as bool? ?? true,
      raw: json['raw'] as String? ?? '',
    );
  }

  /// Parses status code from a porcelain line (e.g. "M file.dart" → "M").
  static String parseStatusCode(String line) {
    if (line.isEmpty) return '';
    return line.substring(0, line.indexOf(' ') > 0 ? line.indexOf(' ') : 2).trim();
  }

  /// Parses filename from a porcelain line.
  static String parseFileName(String line) {
    final idx = line.indexOf(' ');
    if (idx < 0) return line;
    return line.substring(idx).trim();
  }
}

class GitDiffResult {
  final String dir;
  final String diff;
  final bool hasChanges;

  const GitDiffResult({
    required this.dir,
    this.diff = '',
    this.hasChanges = false,
  });

  factory GitDiffResult.fromJson(Map<String, dynamic> json) {
    return GitDiffResult(
      dir: json['dir'] as String? ?? '',
      diff: json['diff'] as String? ?? '',
      hasChanges: json['has_changes'] as bool? ?? false,
    );
  }
}

class GitLogEntry {
  final String hash;
  final String message;
  final String author;
  final String date;

  const GitLogEntry({
    required this.hash,
    this.message = '',
    this.author = '',
    this.date = '',
  });

  factory GitLogEntry.fromJson(Map<String, dynamic> json) {
    return GitLogEntry(
      hash: json['hash'] as String? ?? '',
      message: json['message'] as String? ?? '',
      author: json['author'] as String? ?? '',
      date: json['date'] as String? ?? '',
    );
  }
}

class GitLogResult {
  final String dir;
  final List<GitLogEntry> entries;
  final int count;

  const GitLogResult({
    required this.dir,
    this.entries = const [],
    this.count = 0,
  });

  factory GitLogResult.fromJson(Map<String, dynamic> json) {
    final list = (json['entries'] as List?) ?? [];
    return GitLogResult(
      dir: json['dir'] as String? ?? '',
      entries: list.map((e) => GitLogEntry.fromJson(e as Map<String, dynamic>)).toList(),
      count: json['count'] as int? ?? 0,
    );
  }
}

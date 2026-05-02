/// Maps file extensions to syntax highlight language identifiers.
String detectLanguage(String fileName) {
  const extMap = <String, String>{
    'dart': 'dart',
    'go': 'go',
    'rs': 'rust',
    'py': 'python',
    'js': 'javascript',
    'jsx': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'java': 'java',
    'kt': 'kotlin',
    'swift': 'swift',
    'c': 'cpp',
    'cpp': 'cpp',
    'h': 'cpp',
    'hpp': 'cpp',
    'cs': 'cs',
    'rb': 'ruby',
    'php': 'php',
    'sh': 'bash',
    'bash': 'bash',
    'zsh': 'bash',
    'sql': 'sql',
    'html': 'xml',
    'htm': 'xml',
    'xml': 'xml',
    'svg': 'xml',
    'css': 'css',
    'scss': 'css',
    'json': 'json',
    'yaml': 'yaml',
    'yml': 'yaml',
    'toml': 'ini',
    'ini': 'ini',
    'cfg': 'ini',
    'md': 'markdown',
    'dockerfile': 'dockerfile',
    'makefile': 'makefile',
    'cmake': 'cmake',
    'lua': 'lua',
    'r': 'r',
    'ex': 'elixir',
    'exs': 'elixir',
    'erl': 'erlang',
    'hs': 'haskell',
    'scala': 'scala',
    'clj': 'clojure',
    'vim': 'vim',
  };

  // Check exact filename first (e.g. Dockerfile, Makefile)
  final lower = fileName.toLowerCase();
  if (extMap.containsKey(lower)) return extMap[lower]!;

  // Extract extension
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex < 0) return 'plaintext';
  final ext = fileName.substring(dotIndex + 1).toLowerCase();
  return extMap[ext] ?? 'plaintext';
}

/// Returns a human-friendly icon name for the file type.
String fileIcon(String fileName, bool isDir) {
  if (isDir) return 'folder';
  final lang = detectLanguage(fileName);
  const iconMap = <String, String>{
    'dart': 'code',
    'go': 'code',
    'python': 'code',
    'javascript': 'code',
    'typescript': 'code',
    'json': 'data_object',
    'yaml': 'settings',
    'markdown': 'description',
  };
  return iconMap[lang] ?? 'insert_drive_file';
}

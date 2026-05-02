import 'dart:typed_data';

/// Strips ANSI escape sequences from raw PTY output and converts them
/// to structured style information.
class AnsiProcessor {
  static final _ansiRegex = RegExp(r'\x1B\[[0-9;]*m');
  static final _otherAnsiRegex = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

  /// Strips all ANSI escape sequences from input, returning plain text.
  static String stripAnsi(String input) {
    var result = input;
    result = _otherAnsiRegex.allMatches(result).fold<String>(result,
        (acc, match) => acc.replaceAll(match.group(0)!, ''));
    result = _ansiRegex.allMatches(result).fold<String>(result,
        (acc, match) => acc.replaceAll(match.group(0)!, ''));
    return result;
  }

  /// Processes a chunk of raw bytes, stripping ANSI sequences.
  String processBytes(Uint8List bytes) {
    return stripAnsi(String.fromCharCodes(bytes));
  }
}

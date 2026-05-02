import 'dart:math';

import 'ansi_processor.dart';

/// Types of output chunks produced by the parser.
enum OutputChunkType { text, markdown, codeBlock }

/// A parsed chunk of terminal output.
class OutputChunk {
  final OutputChunkType type;
  final String content;
  final String? language; // only for codeBlock

  const OutputChunk({
    required this.type,
    required this.content,
    this.language,
  });
}

/// Streaming parser that consumes raw PTY output and emits typed chunks.
///
/// Detects Markdown boundaries (code fences, headers, lists, bold/italic)
/// and separates them from plain text for appropriate rendering.
class OutputParser {
  final _buffer = StringBuffer();
  bool _inCodeFence = false;
  String? _codeLanguage;
  int _codeFenceBacktickCount = 0;

  /// Feed raw bytes into the parser. Returns newly parsed chunks.
  List<OutputChunk> feed(String raw) {
    final clean = AnsiProcessor.stripAnsi(raw);
    _buffer.write(clean);
    return _parse();
  }

  /// Force-parse whatever is left in the buffer (call on stream end).
  List<OutputChunk> flush() {
    if (_buffer.isEmpty) return [];
    final remaining = _buffer.toString();
    _buffer.clear();
    _inCodeFence = false;
    return [OutputChunk(type: OutputChunkType.text, content: remaining)];
  }

  List<OutputChunk> _parse() {
    final chunks = <OutputChunk>[];
    var text = _buffer.toString();
    _buffer.clear();

    int pos = 0;
    while (pos < text.length) {
      if (_inCodeFence) {
        // Look for closing fence
        final closeIdx = _findCodeFenceClose(text, pos);
        if (closeIdx >= 0) {
          final codeContent = text.substring(pos, closeIdx);
          chunks.add(OutputChunk(
            type: OutputChunkType.codeBlock,
            content: codeContent,
            language: _codeLanguage,
          ));
          _inCodeFence = false;
          _codeLanguage = null;
          // Skip past the closing fence line
          final afterFence = text.indexOf('\n', closeIdx);
          pos = afterFence >= 0 ? afterFence + 1 : text.length;
        } else {
          // No close found — keep in buffer for next feed
          _buffer.write(text.substring(pos));
          break;
        }
      } else {
        // Look for opening code fence
        final fenceIdx = _findCodeFenceOpen(text, pos);
        if (fenceIdx >= 0) {
          // Emit text before fence as plain text
          if (fenceIdx > pos) {
            chunks.add(OutputChunk(
              type: OutputChunkType.text,
              content: text.substring(pos, fenceIdx),
            ));
          }
          // Parse fence header
          final lineEnd = text.indexOf('\n', fenceIdx);
          if (lineEnd < 0) {
            // Incomplete fence line — buffer it
            _buffer.write(text.substring(fenceIdx));
            break;
          }
          final fenceLine = text.substring(fenceIdx, lineEnd);
          _inCodeFence = true;
          _codeFenceBacktickCount = _countBackticks(fenceLine);
          _codeLanguage = _extractLanguage(fenceLine);
          pos = lineEnd + 1;
        } else {
          // No fence found. Check if tail might be partial fence.
          final tailStart = max(0, text.length - 3);
          final tail = text.substring(tailStart);
          if (tail.startsWith('`') && _couldBePartialFence(tail)) {
            // Emit everything before potential fence, buffer the rest
            chunks.add(OutputChunk(
              type: OutputChunkType.text,
              content: text.substring(pos, tailStart),
            ));
            _buffer.write(tail);
            break;
          }
          // No fence at all — emit as text
          if (pos < text.length) {
            chunks.add(OutputChunk(
              type: OutputChunkType.text,
              content: text.substring(pos),
            ));
          }
          break;
        }
      }
    }

    return chunks;
  }

  int _findCodeFenceOpen(String text, int start) {
    final idx = text.indexOf('```', start);
    if (idx < 0) return -1;
    // Must be at start of line
    if (idx > 0 && text[idx - 1] != '\n') return -1;
    return idx;
  }

  int _findCodeFenceClose(String text, int start) {
    var pos = start;
    while (pos < text.length) {
      final idx = text.indexOf('```', pos);
      if (idx < 0) return -1;
      // Must be at start of line
      if (idx > 0 && text[idx - 1] != '\n') {
        pos = idx + 3;
        continue;
      }
      // Check that closing fence has same or more backticks
      final lineEnd = text.indexOf('\n', idx);
      final fenceLine = lineEnd >= 0
          ? text.substring(idx, lineEnd)
          : text.substring(idx);
      final count = _countBackticks(fenceLine);
      if (count >= _codeFenceBacktickCount && count == fenceLine.trim().length) {
        return idx;
      }
      pos = idx + 3;
    }
    return -1;
  }

  int _countBackticks(String fenceLine) {
    var count = 0;
    for (var i = 0; i < fenceLine.length; i++) {
      if (fenceLine[i] == '`') {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  String? _extractLanguage(String fenceLine) {
    final trimmed = fenceLine.trim();
    final lang = trimmed.substring(_countBackticks(trimmed)).trim();
    return lang.isEmpty ? null : lang;
  }

  bool _couldBePartialFence(String tail) {
    return tail.codeUnits.every((c) => c == 0x60); // all backticks
  }
}

import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'output_parser.dart';

/// Efficient append-only buffer for parsed output chunks.
/// Exposes a ValueNotifier so widgets only rebuild on new data.
class OutputBuffer {
  final _chunks = ListQueue<OutputChunk>();
  final _controller = ValueNotifier<int>(0);
  String _plainText = StringBuffer().toString(); // cache for search

  /// Listen to changes (counter increments on each append).
  ValueNotifier<int> get changeNotifier => _controller;

  /// All chunks accumulated so far.
  List<OutputChunk> get chunks => List.unmodifiable(_chunks);

  /// Current chunk count.
  int get length => _chunks.length;

  /// Append a parsed chunk.
  void append(OutputChunk chunk) {
    _chunks.add(chunk);
    _controller.value++;
  }

  /// Append multiple chunks at once.
  void appendAll(List<OutputChunk> newChunks) {
    for (final c in newChunks) {
      _chunks.add(c);
    }
    _controller.value++;
  }

  /// Get the full text content (for copy/export).
  String get fullText {
    final buf = StringBuffer();
    for (final c in _chunks) {
      buf.write(c.content);
    }
    return buf.toString();
  }

  void clear() {
    _chunks.clear();
    _controller.value++;
  }

  void dispose() {
    _controller.dispose();
  }
}

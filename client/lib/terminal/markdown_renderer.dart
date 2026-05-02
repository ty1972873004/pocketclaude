import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'output_buffer.dart';
import 'output_parser.dart';

/// Renders parsed output chunks: Markdown blocks via flutter_markdown,
/// code blocks via flutter_highlight, plain text via SelectableText.
class MarkdownRenderer extends StatelessWidget {
  final OutputBuffer buffer;
  final ScrollController scrollController;

  const MarkdownRenderer({
    super.key,
    required this.buffer,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: buffer.changeNotifier,
      builder: (context, _, __) {
        final chunks = buffer.chunks;
        if (chunks.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text('Input prompt to start coding',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.all(12),
          itemCount: chunks.length,
          itemBuilder: (context, index) {
            return _buildChunk(context, chunks[index]);
          },
        );
      },
    );
  }

  Widget _buildChunk(BuildContext context, OutputChunk chunk) {
    switch (chunk.type) {
      case OutputChunkType.codeBlock:
        return _buildCodeBlock(context, chunk);
      case OutputChunkType.markdown:
        return _buildMarkdown(context, chunk.content);
      case OutputChunkType.text:
        return _buildText(context, chunk.content);
    }
  }

  Widget _buildCodeBlock(BuildContext context, OutputChunk chunk) {
    final lang = chunk.language ?? '';
    final code = chunk.content;
    final theme = Theme.of(context).brightness == Brightness.dark
        ? Map<String, TextStyle>.from(monokaiSublimeTheme)
        : <String, TextStyle>{};

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lang.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Text(
                lang,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ),
          HighlightView(
            code,
            language: _mapLanguage(lang),
            theme: theme,
            textStyle: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.5,
            ),
            padding: const EdgeInsets.all(12),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkdown(BuildContext context, String content) {
    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        code: TextStyle(
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          fontFamily: 'JetBrainsMono',
          fontSize: 13,
        ),
        codeblockDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildText(BuildContext context, String content) {
    // Check if the text contains inline code or markdown-like patterns
    if (_hasMarkdown(content)) {
      return MarkdownBody(
        data: content,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 13,
            height: 1.5,
          ),
          code: TextStyle(
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            fontFamily: 'JetBrainsMono',
            fontSize: 13,
          ),
        ),
      );
    }

    return SelectableText(
      content,
      style: const TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 13,
        height: 1.5,
      ),
    );
  }

  bool _hasMarkdown(String text) {
    // Detect common Markdown patterns: headers, bold, italic, inline code, lists
    return text.contains(RegExp(r'(^|\n)#{1,6}\s')) ||
        text.contains(RegExp(r'\*\*[^*]+\*\*')) ||
        text.contains(RegExp(r'`[^`]+`')) ||
        text.contains(RegExp(r'(^|\n)[-*]\s')) ||
        text.contains(RegExp(r'(^|\n)\d+\.\s'));
  }

  String _mapLanguage(String lang) {
    const mapping = {
      'js': 'javascript',
      'ts': 'typescript',
      'py': 'python',
      'rb': 'ruby',
      'sh': 'bash',
      'shell': 'bash',
      'yml': 'yaml',
      'md': 'markdown',
      'dart': 'dart',
      'go': 'go',
      'rs': 'rust',
      'cpp': 'cpp',
      'c': 'cpp',
      'java': 'java',
      'json': 'json',
      'html': 'xml',
      'xml': 'xml',
      'sql': 'sql',
    };
    return mapping[lang.toLowerCase()] ?? lang.toLowerCase();
  }
}

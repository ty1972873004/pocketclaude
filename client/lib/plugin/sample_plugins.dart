import 'plugin.dart';

/// Example plugin that logs session lifecycle events.
/// Serves as a reference for building real plugins.
class SessionLoggerPlugin extends BasePlugin {
  final void Function(String)? logger;

  SessionLoggerPlugin({this.logger})
      : super(const PluginManifest(
          id: 'session-logger',
          name: 'Session Logger',
          version: '1.0.0',
          description: 'Logs session lifecycle events for debugging',
          author: 'PocketClaude',
          hooks: [
            PluginHooks.sessionCreated,
            PluginHooks.sessionDestroyed,
            PluginHooks.outputProduced,
          ],
        ));

  @override
  PluginManifest get manifest => const PluginManifest(
        id: 'session-logger',
        name: 'Session Logger',
        version: '1.0.0',
        description: 'Logs session lifecycle events for debugging',
        author: 'PocketClaude',
        hooks: [
          PluginHooks.sessionCreated,
          PluginHooks.sessionDestroyed,
          PluginHooks.outputProduced,
        ],
      );

  @override
  Future<void> onLoad() async {
    _log('Session logger plugin loaded');
  }

  @override
  Future<void> onUnload() async {
    _log('Session logger plugin unloaded');
  }

  @override
  Future<Map<String, dynamic>?> onHook(PluginContext ctx) async {
    switch (ctx.hook) {
      case PluginHooks.sessionCreated:
        _log('Session created: ${ctx.sessionId}');
      case PluginHooks.sessionDestroyed:
        _log('Session destroyed: ${ctx.sessionId}');
      case PluginHooks.outputProduced:
        final data = ctx.data['data'] as String? ?? '';
        if (data.isNotEmpty) {
          _log('Output (${ctx.sessionId?.substring(0, 8)}...): ${data.length} chars');
        }
    }
    return null;
  }

  void _log(String message) {
    logger?.call('[SessionLogger] $message');
  }
}

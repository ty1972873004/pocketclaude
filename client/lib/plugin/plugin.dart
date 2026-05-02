/// Plugin manifest describing metadata and capabilities.
class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final List<String> hooks;

  const PluginManifest({
    required this.id,
    required this.name,
    this.version = '1.0.0',
    this.description = '',
    this.author = '',
    this.hooks = const [],
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '',
      hooks: (json['hooks'] as List?)?.cast<String>() ?? [],
    );
  }
}

/// Hook types that plugins can subscribe to.
class PluginHooks {
  static const sessionCreated = 'session.created';
  static const sessionDestroyed = 'session.destroyed';
  static const inputReceived = 'session.input_received';
  static const outputProduced = 'session.output_produced';
  static const fileChanged = 'fs.file_changed';
}

/// Context passed to plugin hooks.
class PluginContext {
  final String hook;
  final String? sessionId;
  final Map<String, dynamic> data;

  const PluginContext({
    required this.hook,
    this.sessionId,
    this.data = const {},
  });
}

/// The interface all client-side plugins must implement.
abstract class Plugin {
  PluginManifest get manifest;

  /// Called when the plugin is loaded.
  Future<void> onLoad();

  /// Called when the plugin is unloaded.
  Future<void> onUnload();

  /// Called when a subscribed hook fires.
  Future<Map<String, dynamic>?> onHook(PluginContext ctx);
}

/// A minimal base plugin that does nothing.
class BasePlugin implements Plugin {
  final PluginManifest _manifest;

  BasePlugin(this._manifest);

  @override
  PluginManifest get manifest => _manifest;

  @override
  Future<void> onLoad() async {}

  @override
  Future<void> onUnload() async {}

  @override
  Future<Map<String, dynamic>?> onHook(PluginContext ctx) async => null;
}

/// Registry managing loaded plugins on the client side.
class PluginRegistry {
  final Map<String, Plugin> _plugins = {};
  final Map<String, List<Plugin>> _hooks = {};

  List<PluginManifest> get manifests =>
      _plugins.values.map((p) => p.manifest).toList();

  /// Register a plugin and subscribe it to its declared hooks.
  Future<void> register(Plugin plugin) async {
    _plugins[plugin.manifest.id] = plugin;
    for (final hook in plugin.manifest.hooks) {
      _hooks.putIfAbsent(hook, () => []).add(plugin);
    }
    await plugin.onLoad();
  }

  /// Unregister a plugin.
  Future<void> unregister(String id) async {
    final plugin = _plugins.remove(id);
    if (plugin == null) return;
    for (final hook in plugin.manifest.hooks) {
      _hooks[hook]?.removeWhere((p) => p.manifest.id == id);
    }
    await plugin.onUnload();
  }

  /// Fire a hook event to all subscribed plugins.
  Future<List<Map<String, dynamic>>> fire(String hook, PluginContext ctx) async {
    final plugins = _hooks[hook];
    if (plugins == null) return [];

    final results = <Map<String, dynamic>>[];
    for (final p in plugins) {
      final result = await p.onHook(ctx);
      if (result != null) {
        results.add(result);
      }
    }
    return results;
  }

  /// Get a plugin by ID.
  Plugin? get(String id) => _plugins[id];
}

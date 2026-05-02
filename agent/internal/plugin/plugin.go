package plugin

import (
	"encoding/json"
	"fmt"
)

// Manifest describes a plugin's metadata and capabilities.
type Manifest struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Version     string   `json:"version"`
	Description string   `json:"description"`
	Author      string   `json:"author"`
	Hooks       []string `json:"hooks"` // which hooks this plugin subscribes to
}

// Hook types that plugins can subscribe to.
const (
	HookSessionCreated   = "session.created"
	HookSessionDestroyed = "session.destroyed"
	HookInputReceived    = "session.input_received"
	HookOutputProduced   = "session.output_produced"
	HookFileChanged      = "fs.file_changed"
	HookCommandExec      = "system.command"
)

// Context is passed to plugin hooks with relevant data.
type Context struct {
	Hook      string         `json:"hook"`
	SessionID string         `json:"session_id,omitempty"`
	Data      map[string]any `json:"data,omitempty"`
}

// Plugin is the interface that all plugins must implement.
type Plugin interface {
	// Info returns the plugin manifest.
	Info() Manifest

	// OnLoad is called when the plugin is loaded.
	OnLoad() error

	// OnUnload is called when the plugin is unloaded.
	OnUnload()

	// OnHook is called when a subscribed event fires.
	// Returns optional data to pass back, or nil.
	OnHook(ctx Context) (map[string]any, error)
}

// BasePlugin provides a minimal implementation that plugins can embed.
type BasePlugin struct {
	manifest Manifest
}

func NewBasePlugin(m Manifest) BasePlugin {
	return BasePlugin{manifest: m}
}

func (p *BasePlugin) Info() Manifest              { return p.manifest }
func (p *BasePlugin) OnLoad() error               { return nil }
func (p *BasePlugin) OnUnload()                   {}
func (p *BasePlugin) OnHook(ctx Context) (map[string]any, error) { return nil, nil }

// Registry manages loaded plugins.
type Registry struct {
	plugins map[string]Plugin
	hooks   map[string][]Plugin // hook name -> subscribed plugins
}

// NewRegistry creates an empty plugin registry.
func NewRegistry() *Registry {
	return &Registry{
		plugins: make(map[string]Plugin),
		hooks:   make(map[string][]Plugin),
	}
}

// Register adds a plugin and subscribes it to its declared hooks.
func (r *Registry) Register(p Plugin) error {
	m := p.Info()
	r.plugins[m.ID] = p

	for _, hook := range m.Hooks {
		r.hooks[hook] = append(r.hooks[hook], p)
	}

	return p.OnLoad()
}

// Unregister removes a plugin and calls OnUnload.
func (r *Registry) Unregister(id string) {
	p, ok := r.plugins[id]
	if !ok {
		return
	}

	m := p.Info()
	for _, hook := range m.Hooks {
		plugins := r.hooks[hook]
		for i, hp := range plugins {
			if hp.Info().ID == id {
				r.hooks[hook] = append(plugins[:i], plugins[i+1:]...)
				break
			}
		}
	}

	p.OnUnload()
	delete(r.plugins, id)
}

// Fire sends an event to all plugins subscribed to the given hook.
func (r *Registry) Fire(hook string, ctx Context) []map[string]any {
	plugins, ok := r.hooks[hook]
	if !ok {
		return nil
	}

	ctx.Hook = hook
	var results []map[string]any

	for _, p := range plugins {
		result, err := p.OnHook(ctx)
		if err != nil {
			continue
		}
		if result != nil {
			results = append(results, result)
		}
	}

	return results
}

// List returns info about all loaded plugins.
func (r *Registry) List() []Manifest {
	var list []Manifest
	for _, p := range r.plugins {
		list = append(list, p.Info())
	}
	return list
}

// PluginRPC handles JSON-RPC for plugin management.
func (r *Registry) HandleRPC(method string, params json.RawMessage) (interface{}, error) {
	switch method {
	case "plugin.list":
		return r.List(), nil

	case "plugin.info":
		var req struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(params, &req); err != nil {
			return nil, err
		}
		p, ok := r.plugins[req.ID]
		if !ok {
			return nil, fmt.Errorf("plugin not found: %s", req.ID)
		}
		return p.Info(), nil

	default:
		return nil, fmt.Errorf("unknown plugin method: %s", method)
	}
}

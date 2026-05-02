# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PocketClaude is a mobile remote AI coding tool that lets users control Claude Code / Open Code CLI from their phone. Three components communicate over E2E-encrypted WebSocket connections:

```
[Flutter Client] <--E2E encrypted--> [Relay / Direct] <--E2E encrypted--> [Go Agent]
```

## Build & Run Commands

### Relay Server (Go)
```bash
cd relay
go run ./cmd/main.go -addr :18080 -log-level debug   # start relay
go test -v -race ./...                                 # test
go vet ./...                                           # lint
```
CLI flags: `-addr` (listen address), `-tls-cert`/`-tls-key` (TLS), `-log-level` (debug/info/warn/error).

Docker: `docker build -t pocketclaude-relay .` (see `relay/Dockerfile`).

### Agent (Go)
```bash
cd agent
make build            # build binary to bin/
make build-all        # cross-compile for linux/darwin/windows (amd64+arm64)
make run              # run agent (equivalent to go run ./cmd/ start)
make test             # go test -v -race ./...
make lint             # go vet ./...
make fmt              # go fmt ./...

go run ./cmd/ init --relay ws://127.0.0.1:18080  # first-time setup
go run ./cmd/ pair                                 # QR code pairing
go run ./cmd/ start                                # start daemon
```
Global flags: `--relay` (relay URL), `--port` (local API port, default 9090).

Config stored at `~/.pocketclaude/config.json`. Session persistence at `~/.pocketclaude/sessions.json`.

### Flutter Client
```bash
cd client
flutter pub get
flutter run -d chrome          # web (recommended for dev)
flutter run -d android         # Android
flutter run -d windows         # Windows desktop
flutter build web              # static web build → build/web/
flutter test                   # run tests
```

## Architecture

### Communication Protocol

All inter-component communication uses **JSON-RPC 2.0 over WebSocket**. Binary WebSocket frames are forwarded as-is by the relay (first 32 bytes = null-padded target device ID, rest = encrypted payload).

Core RPC methods:
- **Sessions**: `session.create`, `session.list`, `session.send_input`, `session.destroy`
- **Filesystem**: `fs.read_dir`, `fs.read_file`, `fs.write_file`
- **Git**: `git.status`, `git.diff`, `git.log`
- **System**: `system.info`
- **Plugins**: `plugin.list`, `plugin.info`
- **Relay control**: `device.register`, `device.list_online`, `message.send`, `message.forward`, `presence.heartbeat`
- **Notifications** (no ID): `session.on_output`, `presence.online`, `presence.offline`

### E2E Encryption

- Key exchange: X25519 DH → shared secret → AES-256-GCM
- Signing: Ed25519
- Wire format: `[8-byte big-endian nonce counter][AES-256-GCM ciphertext+tag]`
- Pairing: Agent displays QR (contains agent ID + public keys + relay URL + pairing port + Tailscale IP + API port), client scans and sends its keys over a temporary WebSocket, both derive the same shared secret

### Connection Modes

The client supports two connection modes via `ConnectionManager`:
1. **Direct connection** (`DirectConnection`) — WebSocket to agent API at `ws://host:port/ws`, auto-detected via Tailscale IP (100.64.0.0/10 range). No encryption wrapper needed for local network; raw JSON-RPC.
2. **Relay connection** (`RelayConnection`) — WebSocket to cloud relay, E2E-encrypted. Unwraps `message.forward` envelopes automatically.

Strategy: try direct first (5s timeout), fall back to relay. Both extend `ConnectionBase` which provides shared connect/reconnect/heartbeat/encrypt/decrypt logic. `decryptRelayMessages` flag differentiates behavior.

### Agent Internal Structure

The agent has two paths for handling requests:
1. **Local WebSocket API** (`api.Server` on `0.0.0.0:PORT`) — direct browser/tool access
2. **Relay-routed messages** — encrypted messages from mobile client, decrypted then dispatched to same `api.Handler.HandleMessage`

`api.Handler` dispatches session methods directly (`session.create/list/send_input/destroy`) and delegates all other methods to service-layer `HandleRPC` via `dispatchServiceRPC()`:
- `fs.*` → `fs.Service.HandleRPC`
- `git.*` → `git.Service.HandleRPC`
- `system.*` → `process.Monitor.HandleRPC`
- `plugin.*` → `plugin.Registry.HandleRPC`

PTY output is piped back through `broadcast` channel to connected WebSocket clients and relay-forwarded (encrypted) to the mobile client.

PTY is platform-specific: `creack/pty` on Unix, `conpty` (Windows ConPTY) on Windows. Build tags `//go:build windows` / `//go:build !windows` select the implementation.

**tmux session persistence** (Unix only): When tmux is available, sessions are created inside tmux (`pocketclaude_` prefix). `SessionStore` persists metadata to `~/.pocketclaude/sessions.json`. On agent restart, `RestoreSessions()` re-attaches to existing tmux sessions. Output is captured via polling `capture-pane` at 100ms intervals with diff detection. Windows provides stub implementations.

**Plugin system**: `plugin.Registry` manages plugins implementing the `Plugin` interface (`Info/OnLoad/OnUnload/OnHook`). Plugins subscribe to hooks (`session.created`, `session.destroyed`, `session.input_received`, `session.output_produced`, `fs.file_changed`, `system.command`). `Fire()` dispatches events to all subscribed plugins.

### Relay Internal Structure

Stateless in-memory design. Per-connection `Router` handles JSON-RPC control messages, `Registry` is the thread-safe device map. `Presence` service runs a 30s heartbeat check, removes stale devices after 90s, broadcasts `presence.offline` to others.

### Flutter Client Structure

Uses **Riverpod** for state management, **go_router** for navigation.

**Routes** (all wrapped in `ShellRoute` with `AdaptiveShell` for tablet layout):
- `/` — device list with real-time online status via `PresenceWatcher`
- `/pair` — QR scan or paste pairing URL (QR hidden on web via `kIsWeb`)
- `/session/:deviceId` — coding session with multi-session tab bar
  - `/session/:deviceId/files` — file browser
  - `/session/:deviceId/file-preview` — syntax-highlighted file viewer
  - `/session/:deviceId/git` — git status
  - `/session/:deviceId/git-diff` — unified diff viewer
  - `/session/:deviceId/git-log` — commit history
- `/settings`

**Key client subsystems:**

- `ConnectionBase` → `RelayConnection` / `DirectConnection`: abstract WebSocket with auto-reconnect, heartbeat, encryption/decryption. `ConnectionManager` selects strategy.
- `PresenceWatcher`: lightweight relay connection for presence events only, emits `PresenceEvent` stream.
- `SessionService`: manages `ClaudeSession` instances with `OutputBuffer` + `OutputParser` per session. Multiplexes sessions over single connection, routes output by session_id.
- `OutputParser` → `OutputBuffer` → `MarkdownRenderer`: streaming pipeline. Parser feeds raw bytes, buffer appends typed chunks (Text/Markdown/CodeBlock), renderer uses `flutter_markdown` + `flutter_highlight`.
- `FileService` / `GitService`: encrypted RPC wrappers for fs/git operations. Share `SessionContext` (ConnectionBase + targetDeviceId).
- `SessionTabBar`: horizontal scrollable tabs for open sessions, with add (+) and close buttons.
- `AdaptiveShell`: responsive layout with 700dp breakpoint. Wide: 280dp sidebar + main content. Narrow: passthrough.
- Platform abstraction (`platform/`): conditional exports for `dart:io` vs web. `kIsWeb`, `supportsQrScanning`, Tailscale IP detection.

**Keyboard shortcuts**: `Ctrl+Enter` / `Cmd+Enter` sends message via Flutter `Shortcuts`+`Actions` system.

**Plugin system**: Mirrors agent-side API. `PluginRegistry` manages client-side plugins implementing `Plugin` interface with hook-based event subscriptions. Sample: `SessionLoggerPlugin`.

### Key Dependencies

| Component | Key libs |
|-----------|----------|
| Agent | `gorilla/websocket`, `spf13/cobra`, `creack/pty` (Unix), `conpty` (Win), `skip2/go-qrcode`, `golang.org/x/crypto` |
| Relay | `gorilla/websocket` |
| Client | `flutter_riverpod`, `go_router`, `web_socket_channel`, `pointycastle`, `mobile_scanner`, `flutter_markdown`, `flutter_highlight` |

## Development Notes

- Go modules: `github.com/pocketclaude/agent` and `github.com/pocketclaude/relay` — separate modules, no shared Go package
- Agent config dir: `~/.pocketclaude/` (key material stored as base64 in JSON config, sessions persisted in sessions.json)
- Agent local API binds to `0.0.0.0` — enables Tailscale/direct connections. Relay connections still E2E-encrypted.
- The relay never stores or decrypts user data (zero-knowledge forwarding)
- Agent `api.Handler` in `handlers.go` is a thin router — session methods handled directly, all other methods delegated to service-layer `HandleRPC` via prefix dispatch (`dispatchServiceRPC`)
- tmux stubs exist in `pty/tmux_stub.go` for Windows builds — all tmux functions return errors/false
- Client platform abstraction uses conditional exports (`export` in `platform.dart`) to avoid `dart:io` imports on web
- `RelayRpc` helper class provides "send encrypted, wait for decrypted response" pattern with 30s timeout
- Pairing data now includes `tailscale_ip` and `api_port` for direct connection auto-detection
- The project has completed V1 MVP + V1.5 + V2.0 features across 6 implementation batches

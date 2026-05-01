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

Config stored at `~/.pocketclaude/config.json`.

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
- **Sessions**: `session.create`, `session.list`, `session.send_input`, `session.destroy` (Agent handles these via `api.Handler.HandleMessage`)
- **Filesystem**: `fs.read_dir`, `fs.read_file`, `fs.write_file`
- **Git**: `git.status`, `git.diff`, `git.log`
- **System**: `system.info`
- **Relay control**: `device.register`, `device.list_online`, `message.send`, `message.forward`, `presence.heartbeat`
- **Notifications** (no ID): `session.on_output`, `presence.online`, `presence.offline`

### E2E Encryption

- Key exchange: X25519 DH → shared secret → AES-256-GCM
- Signing: Ed25519
- Nonce: incrementing counter per direction (8-byte prefix + GCM ciphertext)
- Pairing: Agent displays QR (contains agent ID + public keys + relay URL + pairing port), client scans and sends its keys over a temporary WebSocket, both derive the same shared secret

### Agent Internal Structure

The agent has two paths for handling requests:
1. **Local WebSocket API** (`api.Server` on `127.0.0.1:PORT`) — direct browser/tool access
2. **Relay-routed messages** — encrypted messages from mobile client, decrypted then dispatched to same `api.Handler.HandleMessage`

`api.Handler` dispatches to `pty.Manager` for session operations. PTY output is piped back through `broadcast` channel to connected WebSocket clients and relay-forwarded (encrypted) to the mobile client.

PTY is platform-specific: `creack/pty` on Unix, `conpty` (Windows ConPTY) on Windows. Build tags `//go:build windows` / `//go:build !windows` select the implementation.

### Relay Internal Structure

Stateless in-memory design. Per-connection `Router` handles JSON-RPC control messages, `Registry` is the thread-safe device map. `Presence` service runs a 30s heartbeat check, removes stale devices after 90s, broadcasts `presence.offline` to others.

### Flutter Client Structure

Uses **Riverpod** for state management, **go_router** for navigation. Routes: `/` (device list), `/pair` (QR scan), `/session/:deviceId` (coding session), `/settings`.

`RelayConnection` manages WebSocket with exponential backoff reconnect (max 10 attempts). `SessionService` wraps JSON-RPC calls for session lifecycle. Crypto uses `pointycastle` for X25519/Ed25519/AES-256-GCM.

### Key Dependencies

| Component | Key libs |
|-----------|----------|
| Agent | `gorilla/websocket`, `spf13/cobra`, `creack/pty` (Unix), `conpty` (Win), `skip2/go-qrcode`, `golang.org/x/crypto` |
| Relay | `gorilla/websocket` |
| Client | `flutter_riverpod`, `go_router`, `web_socket_channel`, `pointycastle`, `mobile_scanner`, `flutter_markdown` |

## Development Notes

- Go modules: `github.com/pocketclaude/agent` and `github.com/pocketclaude/relay` — separate modules, no shared Go package
- Agent config dir: `~/.pocketclaude/` (key material stored as base64 in JSON config)
- Agent local API binds to `127.0.0.1` only — external access must go through relay or direct connection
- The relay never stores or decrypts user data (zero-knowledge forwarding)
- `fs.Service`, `git.Service`, `process.Monitor`, and `session.Manager` each have their own `HandleRPC` method, but the main `api.Handler` in `handlers.go` directly implements the dispatch (some duplication exists between `api.Handler` and the service-layer `HandleRPC` methods)
- The project is in early MVP stage (V1) — no tests exist yet for Go code

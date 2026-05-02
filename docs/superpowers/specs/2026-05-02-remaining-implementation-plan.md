# PocketClaude Remaining Implementation Plan

**Date**: 2026-05-02
**Status**: Planning
**Based on**: Design doc (2026-04-29), current codebase analysis

---

## 0. Current Codebase State Summary

### Go Agent (14 files) — Complete
CLI (init/pair/start), PTY Manager (Unix/Windows), API (JSON-RPC dispatch), Crypto (E2E), Services (fs/git/process), Relay connection with auto-reconnect.

### Go Relay (6 files) — Complete
Device registry, JSON-RPC router, binary frame forwarding, presence/heartbeat, online/offline broadcast, Docker ready.

### Flutter Client (13 files) — Core complete
Device list, pairing (X25519 key exchange), session page (encrypted relay), settings, crypto (AES-256-GCM matching Go format), device persistence.

### Key Gaps
1. No tmux integration — PTY sessions are ephemeral
2. No Markdown rendering — session page uses plain SelectableText
3. Service-layer dispatch duplication in agent handlers.go
4. No file browser / git visualization UI — backend exists, no frontend
5. No direct connection mode
6. No multi-session support
7. No presence-driven online status — device list hardcodes isOnline: false
8. Session page manages its own WebSocket instead of shared connection

---

## 1. Phase 1: V1 MVP Completion

### Feature 1.1: Session Page Markdown Rendering + Code Syntax Highlighting
**Complexity**: M | **Files**: 5 | **Components**: Client only

Dependencies already in pubspec: `flutter_markdown`, `flutter_highlight`.

| File | Change |
|------|--------|
| `client/lib/terminal/ansi_processor.dart` | NEW. Strip/convert ANSI escape sequences to styled spans |
| `client/lib/terminal/output_parser.dart` | NEW. Streaming parser: raw bytes → typed chunks (Text/Markdown/CodeBlock) |
| `client/lib/terminal/output_buffer.dart` | NEW. Append-only buffer with ValueNotifier for incremental rebuilds |
| `client/lib/terminal/markdown_renderer.dart` | NEW. Widget rendering parsed chunks with flutter_markdown + flutter_highlight |
| `client/lib/ui/pages/session_page.dart` | MODIFY. Replace SelectableText ListView with OutputParser + MarkdownRenderer |

**Sequence**: ansi_processor → output_parser → output_buffer → markdown_renderer → session_page

### Feature 1.2: tmux Session Persistence
**Complexity**: L | **Files**: 5 | **Components**: Agent only (Unix)

| File | Change |
|------|--------|
| `agent/internal/pty/tmux.go` | NEW. CreateTmuxSession, AttachTmuxSession, ListTmuxSessions, KillTmuxSession, HasTmux |
| `agent/internal/pty/session_store.go` | NEW. Persist session metadata to ~/.pocketclaude/sessions.json |
| `agent/internal/pty/manager.go` | MODIFY. Use tmux backend on Unix when available; add RestoreSessions() |
| `agent/internal/pty/pty_unix.go` | MODIFY. Delegate to tmux when available |
| `agent/cmd/main.go` | MODIFY. Call ptyMgr.RestoreSessions() on startup |

---

## 2. Phase 2: V1.5 Features

### Feature 2.1: File Browser + Code Preview
**Complexity**: M | **Files**: 7 | **Depends on**: 1.1 (shares syntax highlighting)

| File | Change |
|------|--------|
| `client/lib/file_browser/file_models.dart` | NEW. DirEntry, FileContent models |
| `client/lib/file_browser/language_detector.dart` | NEW. File extension → highlight language mapping |
| `client/lib/file_browser/file_service.dart` | NEW. Encrypted RPC wrapper for fs.read_dir/read_file/write_file |
| `client/lib/ui/pages/file_browser_page.dart` | NEW. Breadcrumb nav + file/folder list |
| `client/lib/ui/pages/code_preview_page.dart` | NEW. Syntax-highlighted file viewer |
| `client/lib/router.dart` | MODIFY. Add /session/:deviceId/files and /session/:deviceId/file-preview routes |
| `client/lib/ui/pages/session_page.dart` | MODIFY. Add file browser button to quick actions |

### Feature 2.2: Git Visualization (Status/Diff/Log)
**Complexity**: M | **Files**: 8 | **Depends on**: 2.1 (shares RPC service pattern)

| File | Change |
|------|--------|
| `client/lib/git_view/git_models.dart` | NEW. GitStatusResult, GitDiffResult, GitLogResult |
| `client/lib/git_view/git_service.dart` | NEW. Encrypted RPC wrapper for git.status/diff/log |
| `client/lib/ui/pages/git_status_page.dart` | NEW. Branch name + changed files with status badges |
| `client/lib/ui/pages/git_diff_page.dart` | NEW. Color-coded unified diff viewer |
| `client/lib/ui/pages/git_log_page.dart` | NEW. Commit list with hash/message/author/date |
| `client/lib/router.dart` | MODIFY. Add git routes |
| `client/lib/ui/pages/session_page.dart` | MODIFY. Add git button to quick actions |
| `agent/internal/api/handlers.go` | MODIFY. Return branch name in git.status; structured log entries |

### Feature 2.3: Multi-Session Parallel Support
**Complexity**: M | **Files**: 6 | **Depends on**: 4.2 (connection refactoring)

| File | Change |
|------|--------|
| `client/lib/ui/pages/session_page.dart` | MAJOR REFACTOR. Extract connection logic, use shared providers |
| `client/lib/connection/relay_connection.dart` | MODIFY. Multiplex sessions over single connection, route output by session_id |
| `client/lib/session/session_service.dart` | MODIFY. Primary session API, add attachSession() |
| `client/lib/ui/widgets/session_tab_bar.dart` | NEW. Horizontal tab bar for open sessions |
| `client/lib/router.dart` | MODIFY. Support ?session_id= query param |
| `agent/internal/api/handlers.go` | MODIFY. Add session.attach dispatch |

### Feature 2.4: Direct Connection Mode (Tailscale/ZeroTier)
**Complexity**: M | **Files**: 8 | **Depends on**: 2.3 (connection refactoring)

| File | Change |
|------|--------|
| `client/lib/connection/connection_manager.dart` | NEW. Strategy: try direct first, fall back to relay |
| `client/lib/connection/direct_connection.dart` | NEW. Direct WebSocket to agent API, same JSON-RPC protocol |
| `client/lib/connection/tailscale_detector.dart` | NEW. Detect Tailscale IP (100.64.0.0/10 range) |
| `client/lib/connection/relay_connection.dart` | MODIFY. Expose same interface as DirectConnection |
| `client/lib/ui/pages/settings_page.dart` | MODIFY. Wire up direct connection toggle |
| `client/lib/models/paired_device.dart` | MODIFY. Add tailscaleIP, directPort fields |
| `agent/internal/crypto/pairing.go` | MODIFY. Add tailscale_ip to QR data |
| `agent/internal/api/server.go` | MODIFY. Bind API to Tailscale interface when detected |

---

## 3. Phase 3: V2.0 Features

### Feature 3.1: Web Client Adaptation
**Complexity**: L | **Files**: 7 | **Depends on**: 1.1, 2.3

Conditional imports for web: QR scanner → text input, secure storage → encrypted localStorage.

### Feature 3.2: Desktop Client (macOS/Windows)
**Complexity**: M | **Files**: 5 | **Depends on**: 2.4

Window management, keyboard shortcuts (Ctrl+Enter), paste pairing URL instead of QR.

### Feature 3.3: Tablet Adaptive Layout
**Complexity**: M | **Files**: 4 | **Depends on**: 2.3, 3.2

Responsive split-view: session list sidebar + main content. Breakpoints via MediaQuery.

### Feature 3.4: Plugin System
**Complexity**: XL | **Deferred** | Requires stable API from all prior phases.

### Feature 3.5: Multi-Device Management
**Complexity**: L | **Files**: 5 | **Depends on**: 2.3

Presence-driven online status, per-device session management, device grouping.

---

## 4. Cross-Cutting Concerns

### 4.1 Agent Service-Layer Dispatch Cleanup
**Complexity**: S | **Before**: 2.1, 2.2

handlers.go reimplements fs.Service/git.Service/session.Manager/process.Monitor logic. Refactor to thin router dispatching to service HandleRPC methods.

### 4.2 Session Page Connection Refactoring
**Complexity**: M | **Before**: 2.3

Extract WebSocket/encryption from session_page.dart into shared RelayConnection + SessionService providers.

### 4.3 Testing Infrastructure
**Alongside each phase**: crypto tests, handler tests, pty tests, relay router tests, client widget tests.

---

## 5. Implementation Batches

```
Batch 1 (V1 completion — parallelizable):
  1.1 Markdown rendering (client only)
  1.2 tmux persistence (agent only, Unix)

Batch 2 (V1.5 infrastructure):
  4.1 Agent service-layer dispatch cleanup
  4.2 Session page connection refactoring

Batch 3 (V1.5 features — parallelizable after Batch 2):
  2.1 File browser
  2.2 Git visualization

Batch 4 (V1.5 advanced):
  2.3 Multi-session support
  2.4 Direct connection mode

Batch 5 (V2.0 — parallelizable):
  3.1 Web client adaptation
  3.2 Desktop client
  3.5 Multi-device management

Batch 6 (V2.0 — sequential):
  3.3 Tablet adaptive layout
  3.4 Plugin system

Continuous:
  4.3 Testing alongside each feature
```

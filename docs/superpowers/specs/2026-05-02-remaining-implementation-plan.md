# PocketClaude Remaining Implementation Plan

**Date**: 2026-05-02
**Status**: COMPLETED
**Based on**: Design doc (2026-04-29), current codebase analysis

---

## 0. Current Codebase State Summary

### Go Agent (16 files) — Complete
CLI (init/pair/start), PTY Manager (Unix/Windows + tmux persistence), API (JSON-RPC dispatch with service-layer delegation), Crypto (E2E), Services (fs/git/process), Relay connection with auto-reconnect, Plugin system.

### Go Relay (6 files) — Complete
Device registry, JSON-RPC router, binary frame forwarding, presence/heartbeat, online/offline broadcast, Docker ready.

### Flutter Client (38 files) — Complete
Device list with presence, pairing (QR + paste URL), session page (Markdown rendering, multi-session tabs, keyboard shortcuts), file browser, git visualization (status/diff/log), direct connection mode, web client adaptation, tablet adaptive layout, plugin system, platform abstraction.

### All Original Gaps — Resolved
1. ✅ tmux integration — sessions persist across agent restarts
2. ✅ Markdown rendering — OutputParser → OutputBuffer → MarkdownRenderer pipeline
3. ✅ Service-layer dispatch cleanup — handlers.go delegates to service HandleRPC methods
4. ✅ File browser + Git visualization — full UI with syntax-highlighted preview
5. ✅ Direct connection mode — ConnectionManager with Tailscale auto-detection
6. ✅ Multi-session support — SessionTabBar with session Map management
7. ✅ Presence-driven online status — PresenceWatcher for real-time device status
8. ✅ Session page connection refactoring — ConnectionBase abstraction shared across all services

---

## 1. Phase 1: V1 MVP Completion — ✅ DONE

### Feature 1.1: Session Page Markdown Rendering + Code Syntax Highlighting ✅
**Complexity**: M | **Files**: 5 | **Components**: Client only

| File | Status |
|------|--------|
| `client/lib/terminal/ansi_processor.dart` | ✅ NEW. Strip/convert ANSI escape sequences |
| `client/lib/terminal/output_parser.dart` | ✅ NEW. Streaming parser: raw bytes → typed chunks |
| `client/lib/terminal/output_buffer.dart` | ✅ NEW. Append-only buffer with ValueNotifier |
| `client/lib/terminal/markdown_renderer.dart` | ✅ NEW. Widget with flutter_markdown + flutter_highlight |
| `client/lib/ui/pages/session_page.dart` | ✅ MODIFIED. Wired MarkdownRenderer |

### Feature 1.2: tmux Session Persistence ✅
**Complexity**: L | **Files**: 6 | **Components**: Agent only (Unix)

| File | Status |
|------|--------|
| `agent/internal/pty/tmux.go` | ✅ NEW. All tmux operations (`//go:build !windows`) |
| `agent/internal/pty/tmux_stub.go` | ✅ NEW. Windows stubs (`//go:build windows`) |
| `agent/internal/pty/session_store.go` | ✅ NEW. JSON persistence at `~/.pocketclaude/sessions.json` |
| `agent/internal/pty/manager.go` | ✅ MODIFIED. tmux backend, RestoreSessions(), pollTmuxOutput() |
| `agent/internal/pty/pty_unix.go` | ✅ Existing, delegates to tmux when available |
| `agent/cmd/main.go` | ✅ MODIFIED. RestoreSessions() on startup |

---

## 2. Phase 2: V1.5 Features — ✅ DONE

### Feature 2.1: File Browser + Code Preview ✅
**Complexity**: M | **Files**: 7

| File | Status |
|------|--------|
| `client/lib/file_browser/file_models.dart` | ✅ NEW. DirEntry, FileContent models |
| `client/lib/file_browser/language_detector.dart` | ✅ NEW. 30+ extension→language mappings |
| `client/lib/file_browser/file_service.dart` | ✅ NEW. Encrypted RPC wrapper |
| `client/lib/ui/pages/file_browser_page.dart` | ✅ NEW. Breadcrumb nav + file/folder list + preview |
| `client/lib/session/session_context.dart` | ✅ NEW. SessionContext, FilePreviewArgs, GitRouteArgs |
| `client/lib/router.dart` | ✅ MODIFIED. files, file-preview routes |
| `client/lib/ui/pages/session_page.dart` | ✅ MODIFIED. Files button in quick actions |

### Feature 2.2: Git Visualization (Status/Diff/Log) ✅
**Complexity**: M | **Files**: 7

| File | Status |
|------|--------|
| `client/lib/git_view/git_models.dart` | ✅ NEW. GitStatusResult, GitDiffResult, GitLogResult |
| `client/lib/git_view/git_service.dart` | ✅ NEW. Encrypted RPC wrapper |
| `client/lib/ui/pages/git_status_page.dart` | ✅ NEW. Branch header + color-coded status badges |
| `client/lib/ui/pages/git_diff_page.dart` | ✅ NEW. Color-coded unified diff viewer |
| `client/lib/ui/pages/git_log_page.dart` | ✅ NEW. Commit list with hash/message/author/date |
| `client/lib/router.dart` | ✅ MODIFIED. git, git-diff, git-log routes |
| `client/lib/ui/pages/session_page.dart` | ✅ MODIFIED. Git button in quick actions |

### Feature 2.3: Multi-Session Parallel Support ✅
**Complexity**: M | **Files**: 5

| File | Status |
|------|--------|
| `client/lib/ui/pages/session_page.dart` | ✅ MAJOR REFACTOR. Session Map, activeSessionId, tab switching |
| `client/lib/ui/widgets/session_tab_bar.dart` | ✅ NEW. Horizontal tab bar with add/close |
| `client/lib/session/session_service.dart` | ✅ MODIFIED. Uses ConnectionBase, multiplexes sessions |
| `client/lib/connection/relay_rpc.dart` | ✅ NEW. Send encrypted, wait for decrypted response |
| `client/lib/router.dart` | ✅ MODIFIED. Session ID handling |

### Feature 2.4: Direct Connection Mode (Tailscale/ZeroTier) ✅
**Complexity**: M | **Files**: 8

| File | Status |
|------|--------|
| `client/lib/connection/connection_base.dart` | ✅ NEW. Abstract base with shared logic |
| `client/lib/connection/direct_connection.dart` | ✅ NEW. Direct WebSocket to agent API |
| `client/lib/connection/relay_connection.dart` | ✅ SIMPLIFIED. Thin ConnectionBase subclass |
| `client/lib/connection/connection_manager.dart` | ✅ NEW. Strategy: direct first, relay fallback |
| `client/lib/connection/tailscale_detector.dart` | ✅ NEW. Detect 100.64.0.0/10 range |
| `client/lib/models/paired_device.dart` | ✅ MODIFIED. tailscaleIP, directPort fields |
| `agent/internal/crypto/pairing.go` | ✅ MODIFIED. TailscaleIP + APIPort in pairing data |
| `agent/cmd/main.go` | ✅ MODIFIED. API binds to 0.0.0.0 |

---

## 3. Phase 3: V2.0 Features — ✅ DONE

### Feature 3.1: Web Client Adaptation ✅
**Complexity**: L | **Files**: 4

| File | Status |
|------|--------|
| `client/lib/platform/platform.dart` | ✅ NEW. Conditional export (io vs web) |
| `client/lib/platform/platform_io.dart` | ✅ NEW. kIsWeb=false, QR support, Tailscale detection |
| `client/lib/platform/platform_web.dart` | ✅ NEW. kIsWeb=true, no QR, no Tailscale |
| `client/lib/platform/platform_stub.dart` | ✅ NEW. Default stub implementations |

### Feature 3.2: Desktop Client (Keyboard Shortcuts) ✅
**Complexity**: M | **Files**: 2

| File | Status |
|------|--------|
| `client/lib/ui/pages/session_page.dart` | ✅ MODIFIED. Ctrl+Enter/Cmd+Enter via Shortcuts+Actions |
| `client/lib/ui/pages/pairing_page.dart` | ✅ MODIFIED. Paste pairing URL button + dialog |

### Feature 3.3: Tablet Adaptive Layout ✅
**Complexity**: M | **Files**: 2

| File | Status |
|------|--------|
| `client/lib/ui/shells/adaptive_shell.dart` | ✅ NEW. 700dp breakpoint, 280dp sidebar on wide screens |
| `client/lib/router.dart` | ✅ MODIFIED. ShellRoute wrapping all routes |

### Feature 3.4: Plugin System ✅
**Complexity**: L | **Files**: 3

| File | Status |
|------|--------|
| `agent/internal/plugin/plugin.go` | ✅ NEW. Plugin interface, BasePlugin, Registry, hooks, HandleRPC |
| `client/lib/plugin/plugin.dart` | ✅ NEW. Client-side mirror of agent plugin API |
| `client/lib/plugin/sample_plugins.dart` | ✅ NEW. SessionLoggerPlugin example |

### Feature 3.5: Multi-Device Management ✅
**Complexity**: L | **Files**: 2

| File | Status |
|------|--------|
| `client/lib/connection/presence_watcher.dart` | ✅ NEW. Real-time online/offline via relay events |
| `client/lib/ui/pages/device_list_page.dart` | ✅ MODIFIED. Real-time online status badges |

---

## 4. Cross-Cutting Concerns

### 4.1 Agent Service-Layer Dispatch Cleanup ✅ DONE
handlers.go reduced from ~196 to ~75 lines. Thin router dispatches to service HandleRPC methods via `dispatchServiceRPC()` based on method prefix.

### 4.2 Session Page Connection Refactoring ✅ DONE
WebSocket/encryption extracted into `ConnectionBase` abstract class. `SessionService`, `FileService`, `GitService` all use `ConnectionBase`. Session page uses `ConnectionManager` for strategy-based connection.

### 4.3 Testing Infrastructure
**Status**: Not yet implemented. Recommended next steps:
- Agent: crypto round-trip tests, handler dispatch tests, tmux session store tests
- Relay: router tests, presence tests, registry tests
- Client: widget tests for session page, connection mock tests

---

## 5. Implementation Batches — All Completed

```
✅ Batch 1 (V1 completion):
     1.1 Markdown rendering
     1.2 tmux persistence

✅ Batch 2 (V1.5 infrastructure):
     4.1 Agent service-layer dispatch cleanup
     4.2 Session page connection refactoring

✅ Batch 3 (V1.5 features):
     2.1 File browser
     2.2 Git visualization

✅ Batch 4 (V1.5 advanced):
     2.3 Multi-session support
     2.4 Direct connection mode

✅ Batch 5 (V2.0):
     3.1 Web client adaptation
     3.2 Desktop keyboard shortcuts + paste pairing URL
     3.5 Multi-device management (PresenceWatcher)

✅ Batch 6 (V2.0):
     3.3 Tablet adaptive layout
     3.4 Plugin system (agent + client)

⬜ Continuous:
     4.3 Testing alongside each feature (not yet started)
```

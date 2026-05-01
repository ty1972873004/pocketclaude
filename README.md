# PocketClaude

Mobile remote AI coding tool - control Claude Code / Open Code CLI from your pocket.

## Architecture

```
[Flutter Client] <--E2E encrypted--> [Relay / Direct] <--E2E encrypted--> [Go Agent]
```

- **Relay** - WebSocket 中继服务器，负责设备注册、消息转发、在线状态管理
- **Agent** - 桌面端代理，运行在开发机上，提供 PTY 会话、文件读写、Git 操作等能力
- **Client** - Flutter 客户端（支持 Web / Android / iOS / Desktop），通过扫码配对控制 Agent

## Prerequisites

- Go 1.22+
- Flutter 3.16+ (Dart 3.2+)
- Windows / macOS / Linux

## Quick Start

### 1. 启动 Relay Server

```bash
cd relay

# 下载依赖（国内网络使用 goproxy.cn）
GOPROXY=https://goproxy.cn,direct go mod tidy

# 启动（默认端口 8080，可自定义）
go run ./cmd/main.go -addr :18080 -log-level debug

# 可选参数
#   -addr       监听地址 (默认 :8080)
#   -tls-cert   TLS 证书路径
#   -tls-key    TLS 私钥路径
#   -log-level  日志级别: debug, info, warn, error (默认 info)
```

启动成功后输出：
```
{"level":"INFO","msg":"relay server starting","addr":":18080","tls":false}
{"level":"INFO","msg":"presence service started"}
```

健康检查：`curl http://127.0.0.1:18080/health`

### 2. 启动 Desktop Agent

```bash
cd agent

# 下载依赖
GOPROXY=https://goproxy.cn,direct go mod tidy

# 步骤一：初始化（生成密钥对和设备 ID，仅需一次）
go run ./cmd/ init --relay ws://127.0.0.1:18080

# 步骤二：配对（生成 QR 码，用手机客户端扫码）
go run ./cmd/ pair

# 步骤三：启动 agent 守护进程
go run ./cmd/ start

# 可选全局参数
#   --relay   relay 服务器地址 (默认 ws://relay.pocketclaude.dev:8080)
#   --port    本地 API 端口 (默认 9090)
```

启动成功后输出：
```
[Agent] Starting PocketClaude Agent (device: xxx)
[Agent] API server listening on 127.0.0.1:9090
[Agent] Agent is running. Press Ctrl+C to stop.
[Relay] Connected to relay server
```

Agent 本地 API：`curl http://127.0.0.1:9090/health`

### 3. 启动 Flutter Client

```bash
cd client

# 下载依赖
flutter pub get

# Web 方式运行（推荐，开发调试最方便）
flutter run -d chrome

# 也可以构建 Web 静态文件
flutter build web
# 构建产物在 build/web/，可用任意 HTTP 服务器托管

# Android
flutter run -d android

# Windows Desktop
flutter run -d windows
```

Client 路由结构：

| 路径 | 页面 | 说明 |
|------|------|------|
| `/` | DeviceListPage | 已配对设备列表 |
| `/pair` | PairingPage | 扫码配对新设备 |
| `/session/:deviceId` | SessionPage | 远程终端会话 |
| `/settings` | SettingsPage | 设置（Relay 地址等） |

## 完整操作流程

```
1. 启动 Relay Server
   └─ go run ./cmd/main.go -addr :18080

2. 启动 Agent（在开发机上）
   ├─ go run ./cmd/ init --relay ws://<relay-ip>:18080   # 首次初始化
   ├─ go run ./cmd/ pair                                  # 生成配对 QR 码
   └─ go run ./cmd/ start                                 # 启动并连接 Relay

3. 启动 Client（手机/浏览器）
   ├─ flutter run -d chrome                               # 或 flutter run -d android
   ├─ 在设置页配置 Relay 地址: ws://<relay-ip>:18080
   ├─ 进入配对页，扫描 Agent 终端上的 QR 码
   └─ 配对成功后，在设备列表点击设备进入远程会话
```

## Network Notes

端口说明：

| 端口 | 服务 | 说明 |
|------|------|------|
| 18080 | Relay | WebSocket 中继服务（可自定义） |
| 9090 | Agent API | 本地 API 服务（仅绑定 127.0.0.1） |
| 随机 | Agent Pairing | 配对时的临时 WebSocket 端口 |

如果 Relay 和 Agent 不在同一台机器，确保 Agent 的 `--relay` 参数指向 Relay 的可达地址。

国内网络下载 Go 依赖时使用 `GOPROXY=https://goproxy.cn,direct`。

## Project Structure

```
pocketclaude/
├── agent/                     # Go desktop agent
│   ├── cmd/main.go            # CLI 入口 (init / pair / start)
│   └── internal/
│       ├── api/               # 本地 WebSocket API
│       ├── connection/        # Relay WebSocket 客户端
│       ├── crypto/            # E2E 加密、密钥管理、配对
│       ├── fs/                # 文件系统操作
│       ├── git/               # Git 操作
│       ├── process/           # 进程监控
│       ├── pty/               # PTY 管理 (Unix / Windows)
│       └── session/           # 会话管理
├── relay/                     # Go relay server
│   ├── cmd/main.go            # 服务入口
│   └── internal/
│       ├── api/               # WebSocket handler
│       ├── presence/          # 心跳检测
│       ├── protocol/          # JSON-RPC 协议类型
│       ├── registry/          # 设备注册表
│       └── router/            # 消息路由
├── client/                    # Flutter client
│   ├── lib/
│   │   ├── main.dart          # App 入口
│   │   ├── router.dart        # 路由配置
│   │   ├── crypto/            # 客户端加密
│   │   ├── session/           # 会话服务
│   │   └── ui/                # 页面和组件
│   └── web/                   # Web 平台资源
└── docs/                      # 文档
```

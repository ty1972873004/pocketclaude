# PocketClaude - 移动端远程 AI Coding 工具设计文档

> 日期：2026-04-29
> 状态：设计中
> 作者：tuyong + Claude

## 1. 背景与目标

### 问题
个人开发者希望在手机上远程操作电脑上已运行的 Claude Code 或 Open Code CLI，实现随时随地的 vibe coding。

### 目标
构建一个跨平台移动应用（PocketClaude），能够：
- 远程连接开发机上的 Claude Code / Open Code CLI
- 发送 prompt 并实时查看流式输出
- 浏览远程文件系统和代码
- 查看 Git 状态和差异
- 端到端加密保护通信安全

### 约束
- 个人开发者自用，非 SaaS
- MVP 优先，2 周内可验证
- 全平台支持：iOS/Android/Web/桌面/平板
- 端到端加密
- 支持云中转和直连两种连接模式

## 2. 系统架构

### 2.1 整体架构：三层架构

```
[Flutter 全平台客户端] <--E2E加密--> [云 Relay / 直连] <--E2E加密--> [Go 桌面 Agent]
```

### 2.2 组件职责

| 组件 | 技术 | 职责 |
|------|------|------|
| **Flutter 客户端** | Dart + Flutter 3.x | 全平台 UI：prompt 输入、流式 Markdown/代码渲染、文件浏览、会话管理 |
| **Go Agent** | Go 1.22+ 单二进制 | 开发机守护进程：PTY 管理 CLI 进程，暴露文件系统和 Git API |
| **Relay Server** | Go 轻量服务 | WebSocket 中转，NAT 穿透，设备发现。不存储任何用户数据 |

### 2.3 连接模式

- **Relay 模式（默认）**：客户端和 Agent 都连接云端 Relay，适合 NAT 后面的设备
- **直连模式**：通过 Tailscale/ZeroTier mesh VPN 直连，延迟更低
- 客户端自动检测并选择最优连接方式

## 3. Go 桌面 Agent

### 3.1 核心模块

```
Go Agent (单二进制)
├── cmd/pocketclaude-agent        # CLI 入口
│   ├── init                      # 初始化：生成密钥对 + 配置文件
│   ├── pair                      # 配对：显示 QR 码
│   └── start                     # 启动：后台守护运行
├── internal/
│   ├── api/                      # WebSocket API Server
│   ├── session/                  # 会话管理器
│   ├── pty/                      # PTY 进程管理
│   ├── fs/                       # 文件系统服务
│   ├── git/                      # Git 操作封装
│   ├── process/                  # 进程监控
│   ├── connection/               # Relay + 直连管理
│   └── crypto/                   # 加密层
└── go.mod
```

### 3.2 安装与使用流程

1. **安装**：`curl -fsSL pocketclaude.dev/install | bash`（一行命令，Win/Mac/Linux 通用）
2. **初始化**：`pocketclause-agent init` → 生成 Ed25519 + X25519 密钥对 + 配置文件
3. **配对**：`pocketclaude-agent pair` → 显示 QR 码，手机扫码完成密钥交换
4. **启动**：`pocketclaude-agent start` → 后台守护，自动连接 Relay，等待客户端连接

### 3.3 PTY 管理策略

- 通过 Go 的 `os/exec` + pty 库启动 Claude Code / Open Code 进程
- V1（MVP）：直接转发原始 ANSI 输出流到客户端
- V2：解析 Claude Code 结构化输出为 JSON 事件（file_change, command, diff, tool_use）

### 3.4 会话持久化

- 底层使用 tmux/screen 维持终端会话
- Agent 重启后自动 reattach 到已有 tmux session
- 每个 tmux session 对应一个 Claude Code 实例
- 支持多会话并行（不同项目目录）

### 3.5 安全

- Agent 只监听 localhost WebSocket
- 外部访问必须通过 Relay 或直连（均需 E2E 加密认证）
- 拒绝未配对设备的连接请求

## 4. Flutter 客户端

### 4.1 页面结构

| 页面 | 功能 | MVP |
|------|------|-----|
| 设备列表（首页） | 显示已配对设备、在线状态、活跃会话数 | Yes |
| AI Coding 会话 | Prompt 输入 + 流式输出 + 快捷操作 | Yes |
| 文件浏览器 | 远程文件系统浏览 + 代码预览 | No (V1.5) |
| Git 可视化 | status/diff/log | No (V1.5) |
| 设置 | 设备管理、连接配置、密钥管理 | Yes (简化) |

### 4.2 客户端模块

```
Flutter Client (lib/)
├── connection/       # Relay/直连管理，自动重连，心跳
├── crypto/           # E2E 加密：密钥存储、加解密
├── session/          # Claude Code 会话生命周期
├── terminal/         # 解析输出 → Flutter UI 渲染
├── file_browser/     # 远程文件系统（V1.5）
├── git_view/         # Git 可视化（V1.5）
├── settings/         # 设备管理、配置
└── ui/               # 共享组件、主题、响应式布局
```

### 4.3 AI Coding 会话页交互

- 顶部：会话标题 + 项目路径 + 连接状态指示
- 中部：流式输出区域，支持 Markdown 渲染和代码语法高亮
- 底部：Prompt 输入框 + 发送按钮
- 快捷操作栏：文件浏览、Git 状态、历史记录

## 5. Relay Server

### 5.1 架构

```
Relay Server (Go, Docker 部署, ~50MB 内存)
├── cmd/relay                     # 入口
├── internal/
│   ├── registry/                 # 设备注册表 (内存 + 可选 Redis)
│   ├── router/                   # 消息路由 (基于 device_id)
│   ├── presence/                 # 心跳 (30s) + 在线状态 + 断线清理
│   └── api/                      # WebSocket handler
└── Dockerfile
```

### 5.2 核心原则

- **零知识**：只转发密文，不存储、不解密、不解析任何用户数据
- **无状态**：设备注册表在内存中，重启后设备重新注册即可
- **轻量**：单实例可支持数千设备，内存占用 < 50MB

### 5.3 部署

- Docker 容器，端口 443 (WSS)
- 可部署在任何 VPS 上（推荐：DigitalOcean/Lightsail 最低配）
- 域名 + Let's Encrypt TLS 证书

## 6. E2E 加密

### 6.1 密钥体系

| 密钥 | 类型 | 用途 |
|------|------|------|
| Agent 签名密钥 | Ed25519 | 消息签名，防篡改 |
| Agent 加密密钥 | X25519 | 密钥交换 |
| 客户端签名密钥 | Ed25519 | 消息签名 |
| 客户端加密密钥 | X25519 | 密钥交换 |
| 共享会话密钥 | AES-256-GCM | 对称加密通信 |

### 6.2 配对流程

1. Agent 生成 QR 码，包含：Agent ID + 加密公钥 + 签名
2. 客户端扫描 QR 码，验证签名
3. 客户端生成 X25519 DH 共享密钥
4. 客户端用 Agent 公钥加密自己的公钥，发送给 Agent
5. Agent 解密获得客户端公钥，生成相同的 DH 共享密钥
6. 双方确认共享密钥哈希（显示短指纹供用户比对）

### 6.3 通信加密

- 每条消息用 AES-256-GCM 加密
- Nonce 从计数器派生，防止重放
- 每 24 小时自动轮换共享密钥

## 7. 通信协议

### 7.1 消息格式

JSON-RPC 2.0 over WebSocket：

```json
// 请求
{
  "jsonrpc": "2.0",
  "id": "uuid-v4",
  "method": "session.send_input",
  "params": {
    "session_id": "s1",
    "input": "帮我写一个快速排序"
  }
}

// 流式响应（通知，无 id）
{
  "jsonrpc": "2.0",
  "method": "session.on_output",
  "params": {
    "session_id": "s1",
    "data": "好的，我来帮你写快速排序...\n",
    "type": "stream",
    "sequence": 1
  }
}
```

### 7.2 核心 RPC 方法

**会话管理：**
- `session.create` - 创建新的 Claude Code 会话
- `session.list` - 列出所有活跃会话
- `session.attach` - 附加到已有会话
- `session.send_input` - 发送 prompt/命令到会话
- `session.on_output` - 流式输出通知（Agent → Client）
- `session.destroy` - 销毁会话

**文件操作：**
- `fs.read_dir` - 读取目录列表
- `fs.read_file` - 读取文件内容
- `fs.write_file` - 写入文件

**Git 操作：**
- `git.status` - 工作区状态
- `git.diff` - 查看差异
- `git.log` - 提交历史

**系统信息：**
- `system.info` - 系统信息（OS、内存、CPU）
- `system.processes` - 运行中的进程列表

## 8. MVP 范围与迭代计划

### V1 MVP（2 周）

**包含：**
- Go Agent：PTY 管理 + 单会话 + Relay 连接 + QR 配对
- Relay Server：设备注册 + 消息转发 + 心跳
- Flutter 客户端（iOS + Android）：设备列表 + AI Coding 会话页
- E2E 加密：完整密钥交换 + AES-256-GCM 通信
- 原始文本流式输出（不做 ANSI 解析）

**不包含：**
- 直连模式
- 文件浏览器
- Git 可视化
- 多会话并行
- Web/桌面适配
- PTY 结构化解析

### V1.5 迭代

- 直连模式（Tailscale/ZeroTier 自动检测）
- 文件浏览器 + 代码预览（语法高亮）
- Git 可视化（status、diff、log）
- 多会话并行
- Claude Code 结构化输出解析

### V2.0 完整版

- Web 版客户端
- 桌面客户端（macOS/Windows）
- 平板自适应布局
- 插件系统
- 多设备管理

## 9. 项目目录结构

```
pocketclaude/
├── agent/                    # Go 桌面 Agent
│   ├── cmd/
│   │   └── main.go           # CLI 入口 (init, pair, start)
│   ├── internal/
│   │   ├── api/              # WebSocket API Server
│   │   ├── session/          # 会话管理
│   │   ├── pty/              # PTY 进程管理
│   │   ├── fs/               # 文件系统服务
│   │   ├── git/              # Git 操作
│   │   ├── process/          # 进程监控
│   │   ├── connection/       # Relay + 直连
│   │   └── crypto/           # 加密层
│   ├── go.mod
│   └── Makefile
├── relay/                    # Go Relay Server
│   ├── cmd/
│   │   └── main.go
│   ├── internal/
│   │   ├── registry/         # 设备注册
│   │   ├── router/           # 消息路由
│   │   └── presence/         # 在线状态
│   ├── go.mod
│   └── Dockerfile
├── client/                   # Flutter 客户端
│   ├── lib/
│   │   ├── main.dart
│   │   ├── connection/
│   │   ├── crypto/
│   │   ├── session/
│   │   ├── terminal/
│   │   ├── settings/
│   │   └── ui/
│   ├── pubspec.yaml
│   └── test/
└── docs/
    └── architecture.md
```

## 10. 验证方案

### MVP 验收测试

1. **Agent 安装**：在 Windows/Mac/Linux 分别执行 install → init → pair → start
2. **设备配对**：手机扫描 QR 码，确认密钥交换和指纹验证
3. **Relay 连接**：手机通过 Relay 连接 Agent，验证双向消息收发
4. **Claude Code 集成**：手机发送 prompt，验证流式输出显示
5. **断线恢复**：模拟网络中断，验证自动重连 + 会话保持（tmux）
6. **加密验证**：抓包确认 Relay 中转的消息为密文

### 开发环境启动

```bash
# 1. 启动 Relay（本地测试）
cd relay && go run cmd/main.go --port 8080

# 2. 启动 Agent
cd agent && go run cmd/main.go start --relay ws://localhost:8080

# 3. 启动 Flutter 客户端
cd client && flutter run
```

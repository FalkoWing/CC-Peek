# Glossary / 术语对照

三端（官网 / Mac / iOS）共享的核心词汇。新加翻译时先来这里查，避免同一概念跨端措辞不一致。

## 不翻译

- **CC Peek** — 产品名
- **Claude Code** — 引用 Anthropic 产品
- **Hook** — Claude Code 的钩子机制术语
- **MultipeerConnectivity** — Apple 框架名
- **Wi-Fi** / **Bluetooth** / **iPhone** / **Mac** / **macOS** / **iOS** / **App Store**
- **Terminal.app** / **iTerm2** / **Ghostty** / **Warp** / **VS Code** — 终端应用名
- **CC Switch** — 第三方工具名

## 状态体系（必须跨端一致）

| 中文 | 英文 | 备注 |
|---|---|---|
| 运行中 | Running | active state, ACTIVE 是 mono 标签的全大写 variant |
| 等待输入 | Waiting input | WAITING INPUT |
| 等待权限 | Awaiting permission | AWAIT PERMISSION |
| 状态未知 | Unknown | UNKNOWN |
| 已结束 | Completed | Mac 端 ProcessCardView 用 |
| 暂无活跃进程 | No active sessions | |
| 暂无 Claude Code 进程 | No Claude Code sessions | |

## 配对 / 设备

| 中文 | 英文 |
|---|---|
| 配对 | Pair |
| 解除配对 | Unpair |
| 已配对 | Paired |
| 已连接 / 已连接 iPhone | Connected / iPhone connected |
| 未连接 Mac / 未连接 iPhone | No Mac connected / iPhone disconnected |
| 已断开 | Disconnected |
| 已同步 | Synced |
| 在线 | Online |
| 离线 | Offline |
| 信任新设备 | Trust new device |
| 局域网内可达 | Reachable on the local network |

## 时长（带占位符的 key）

iOS 用 String Catalog 的占位符 `%lld`，Mac 等 SPM 端用传统 `%lld 秒` 格式 key。

| 中文 key | 英文 value |
|---|---|
| `%lld 秒` | `%lld sec` |
| `%lld 分` | `%lld min` |
| `%lld 分 %lld 秒` | `%1$lld min %2$lld sec` |
| `%lld 小时` | `%lld h` |
| `%lld 小时 %lld 分` | `%1$lld h %2$lld min` |
| `%lld 小时 %lld 分 %lld 秒` | `%1$lld h %2$lld min %3$lld sec` |

短缩写（sec/min/h）是为了卡片右侧栏宽度受限。

## 设置 / 操作

| 中文 | 英文 |
|---|---|
| 设置 | Settings |
| 通用 | General |
| 关于 | About |
| 系统权限 | System permissions |
| 危险操作 | Danger zone |
| 演示模式 | Demo mode |
| 自动化（权限） | Automation |
| 本地网络（权限） | Local Network |
| 蓝牙（权限） | Bluetooth |
| 去设置 | Open Settings |
| 已授权 | Granted |
| 已拒绝 | Denied |
| 检测中 | Checking |
| 保持屏幕常亮 | Keep screen awake |
| 全局快捷键 | Global shortcut |
| 开机自启 | Launch at login |
| 自动检查更新 | Check for updates automatically |
| 检查更新 | Check for updates |
| 重看引导 | Replay onboarding |
| 反馈 | Feedback |
| 诊断日志 | Diagnostic logs |
| 卸载 / 卸载说明 | Uninstall / Uninstall instructions |
| 清理配置信息 | Clear configuration data |

## 通用动词

| 中文 | 英文 |
|---|---|
| 取消 | Cancel |
| 解除 | Unpair |
| 应用 | Apply |
| 检查 | Check |
| 查看 | View |
| 打开 | Open |
| 复制 | Copy |
| 已复制 | Copied |
| 重新搜索 | Search again |
| 处理中... | Working… |
| 好的 | OK |

## 路径 / 平台特定差异

- **官网**：用 "side-screen" / "second screen" 描述桌面副屏概念，避免 "secondary monitor"（会让人想到外接显示器）。
- **iOS / Mac**：UI 内部的 "side-screen" 不会出现在文案里 —— 客户端文案直接说功能，不用宣传词。
- "进程" 在 UI 文案里翻成 **session**（更口语，跟 Claude Code 自己用的术语一致），不翻成 "process"。
- "终端" 一律翻 **terminal**（小写），除非是 "Terminal.app" 专有产品名。

## 维护

加新翻译时：

1. 来这里查现有词条 — 同一中文已有翻译就照用，避免同一概念跨端不同。
2. 翻译需要新增的词，回填到对应端的本地化文件：
   - 官网：`website/en/index.html` 直接改文案
   - iOS：`ios/CCPeekiOS/CCPeekiOS/Localizable.xcstrings`（在 Xcode 里编辑最方便）
   - Mac：`Sources/CCPeekMac/Resources/{en,zh-Hans}.lproj/Localizable.strings`
3. 如果产生了通用术语（一种说法在多端复用），加到本表。

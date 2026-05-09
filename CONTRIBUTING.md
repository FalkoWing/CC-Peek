# Contributing

CC Peek 目前由一人维护，欢迎以下形式的贡献：

## Bug / 功能建议

开 [Issue](https://github.com/FalkoWing/CC-Peek/issues)。麻烦带上：

- 复现步骤
- macOS / iOS 系统版本
- 当前用的是 [ccpeek.com](https://ccpeek.com) / App Store 分发版本，还是自己 `./scripts/build-app.sh` 构建出来的 ad-hoc 版

## Pull Request

- **小改动**（typo、局部 bug fix）：直接发 PR。
- **较大改动**（新功能 / 架构调整）：先开 Issue 讨论方向，避免做完才发现想法不一致。
- 提 PR 前请确认 `swift build` 通过；改动涉及 iOS 部分时请用 Xcode 构建一次。
- 改了 UI 文案：请同步更新中文与英文资源（Mac 端 `Sources/CCPeekMac/Resources/{en,zh-Hans}.lproj/Localizable.strings`；iOS 端 `Localizable.xcstrings`）。

## 本地构建

见 [README.md 「从源码构建」](./README.md#从源码构建)。

## 响应节奏

单人项目，Issue / PR 响应可能延迟数日。涉及崩溃、数据丢失等问题会优先处理。

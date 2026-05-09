# Contributing

English | [简体中文](./CONTRIBUTING.zh-CN.md)

CC Peek is currently maintained by one person. Contributions are welcome in the following forms.

## Bugs and feature requests

Open an [Issue](https://github.com/FalkoWing/CC-Peek/issues). Please include:

- Steps to reproduce
- macOS / iOS versions
- Whether you are using the [ccpeek.com](https://ccpeek.com) / App Store distribution, or an ad-hoc build produced by `./scripts/build-app.sh`

## Pull requests

- **Small changes** such as typos or focused bug fixes: feel free to open a PR directly.
- **Larger changes** such as new features or architecture changes: please open an Issue first to discuss the direction, so we do not discover a mismatch after the work is done.
- Before opening a PR, make sure `swift build` passes. If the change touches the iOS app, please also build it once in Xcode.
- If you change UI copy, update both Chinese and English resources: Mac uses `Sources/CCPeekMac/Resources/{en,zh-Hans}.lproj/Localizable.strings`; iOS uses `Localizable.xcstrings`.

## Local build

See [Build from source](./README.md#build-from-source) in the README.

## Response time

This is a single-maintainer project, so Issue / PR responses may be delayed by a few days. Crashes, data loss, and similar problems are prioritized.

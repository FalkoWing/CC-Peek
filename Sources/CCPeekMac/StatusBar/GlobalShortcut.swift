import KeyboardShortcuts

/// MacUI-2.5 全局热键名称定义。
///
/// 不设默认值——任何默认 combo 都会撞用户日常使用的 app（⌘⌥P / ⌘⇧K 等），
/// 让用户自己在「设置 → 通用」里录制。
extension KeyboardShortcuts.Name {
    static let togglePeek = Self("togglePeek")
}

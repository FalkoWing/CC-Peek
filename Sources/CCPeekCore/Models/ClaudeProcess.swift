import Foundation

public struct ClaudeProcess: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var state: ProcessState
    public let startedAt: Date
    public var stateChangedAt: Date
    public var cwd: String?
    public var claudePID: Int32?
    public var terminal: TerminalLocation?

    public init(
        id: String,
        name: String,
        state: ProcessState,
        startedAt: Date,
        stateChangedAt: Date,
        cwd: String? = nil,
        claudePID: Int32? = nil,
        terminal: TerminalLocation? = nil
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.startedAt = startedAt
        self.stateChangedAt = stateChangedAt
        self.cwd = cwd
        self.claudePID = claudePID
        self.terminal = terminal
    }
}

/// 进程在终端中的位置, SessionStart 时由 ProcessTreeResolver 解析得到.
public struct TerminalLocation: Equatable, Sendable {
    public let kind: TerminalKind
    public let appPID: Int32
    public let shellPID: Int32
    public let tty: String?

    public init(kind: TerminalKind, appPID: Int32, shellPID: Int32, tty: String?) {
        self.kind = kind
        self.appPID = appPID
        self.shellPID = shellPID
        self.tty = tty
    }
}

/// 已知终端 app, 决定切换支持级别.
public enum TerminalKind: String, Equatable, Sendable {
    case appleTerminal     // com.apple.Terminal      ✅ 完整
    case iterm2            // com.googlecode.iterm2   ✅ 完整
    case ghostty           // com.mitchellh.ghostty   🟡 仅激活
    case warp              // dev.warp.Warp-Stable    🟡 仅激活
    case vscode            // com.microsoft.VSCode    🟡 仅激活
    case unknown           // 不支持

    public var displayName: String {
        switch self {
        case .appleTerminal: return "Terminal"
        case .iterm2:        return "iTerm2"
        case .ghostty:       return "Ghostty"
        case .warp:          return "Warp"
        case .vscode:        return "VS Code"
        case .unknown:       return "未知终端"
        }
    }

    public var supportsTabSwitch: Bool {
        switch self {
        case .appleTerminal, .iterm2: return true
        default: return false
        }
    }

    public static func from(bundleId: String?) -> TerminalKind? {
        guard let bundleId else { return nil }
        switch bundleId {
        case "com.apple.Terminal":     return .appleTerminal
        case "com.googlecode.iterm2":  return .iterm2
        case "com.mitchellh.ghostty":  return .ghostty
        case "dev.warp.Warp-Stable":   return .warp
        case "com.microsoft.VSCode":   return .vscode
        default: return nil
        }
    }
}

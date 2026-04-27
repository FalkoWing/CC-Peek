import SwiftUI
import CCPeekCore

struct ProcessCardView: View {
    let process: ClaudeProcess
    let onSwitch: (ClaudeProcess) -> Void

    @State private var now = Date()
    @State private var lastFlashAt: Date?
    @State private var errorText: String?

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Button(action: triggerSwitch) {
            HStack(alignment: .top, spacing: 12) {
                Text(stateIcon)
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 3) {
                    Text(process.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(stateText)
                        if let terminal = process.terminal?.kind.displayName {
                            Text("·").foregroundStyle(.tertiary)
                            Text(terminal)
                        }
                        Text("·").foregroundStyle(.tertiary)
                        Text("已 \(durationText)")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if !canSwitch {
                    Image(systemName: "lock.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(flashOpacity), lineWidth: flashOpacity > 0.1 ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSwitch)
        .onReceive(tick) { now = $0 }
    }

    private var canSwitch: Bool { TerminalSwitcher.canSwitch(process) }

    private func triggerSwitch() {
        guard canSwitch else { return }
        lastFlashAt = Date()
        errorText = nil
        let result = TerminalSwitcher.switch(to: process)
        switch result {
        case .ok, .activatedAppOnly:
            break
        case let .unsupported(reason), let .failed(reason):
            errorText = reason
        }
    }

    // MARK: - 视觉派生

    private var stateIcon: String {
        switch process.state {
        case .active: return "🟢"
        case .waitingInput: return "⏳"
        case .waitingPermission: return "🔐"
        case .completed: return "✅"
        case .unknown: return "⚪️"
        }
    }

    private var stateText: String {
        switch process.state {
        case .active: return "运行中"
        case .waitingInput: return "等待输入"
        case .waitingPermission: return "等待权限"
        case .completed: return "已结束"
        case .unknown: return "状态未知"
        }
    }

    private var background: Color {
        switch process.state {
        case .waitingInput: return Color.orange.opacity(0.12)
        case .waitingPermission: return Color.red.opacity(0.12)
        case .unknown: return Color.gray.opacity(0.12)
        default: return Color.secondary.opacity(0.06)
        }
    }

    /// 点击后短暂高亮 (PRD 3.2.6 本地反馈).
    private var flashOpacity: Double {
        guard let t = lastFlashAt else { return 0.06 }
        let elapsed = now.timeIntervalSince(t)
        if elapsed > 0.3 { return 0.06 }
        return 0.4 * (1.0 - elapsed / 0.3)
    }

    private var durationText: String {
        let total = max(0, Int(now.timeIntervalSince(process.stateChangedAt)))
        if total < 60 { return "\(total) 秒" }
        if total < 3600 {
            let m = total / 60, s = total % 60
            return s == 0 ? "\(m) 分" : "\(m) 分 \(s) 秒"
        }
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if m == 0 && s == 0 { return "\(h) 小时" }
        if s == 0 { return "\(h) 小时 \(m) 分" }
        return "\(h) 小时 \(m) 分 \(s) 秒"
    }
}

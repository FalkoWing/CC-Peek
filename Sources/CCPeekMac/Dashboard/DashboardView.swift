import SwiftUI
import AppKit
import CCPeekCore

/// Mac 端 Dashboard —— 同一份 view 同时承载 popover 和 MacUI-2.5 独立 NSPanel.
/// 设计稿对齐 cc-peek-ui/mac-screens.jsx MacDashboardPopover.
struct DashboardView: View {
    @ObservedObject var store: ProcessStateStore
    @ObservedObject var bridge: HostTransportBridge

    /// hook 错误状态 (MacUI-2 暂未接入实时检测，预留以便 MacUI-4 接通)
    var hasHookError: Bool = false
    /// 独立 NSPanel 首次出现时显示快捷键引导 banner (MacUI-2.5 接入)
    var showFirstUseHint: Bool = false

    var onOpenSettings: () -> Void = { SettingsWindowController.show() }
    var onQuit: () -> Void = { NSApp.terminate(nil) }

    var body: some View {
        VStack(spacing: 0) {
            if hasHookError {
                hookErrorBanner
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
            }
            header
            Divider().background(Theme.lineSoft)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(Theme.lineSoft)
            footer
        }
        .frame(width: 400, height: 520)
        .background(AmbientBackground())
        .background(Theme.bgDeepest)
        .colorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("CC PEEK")
                    .font(Theme.mono(14, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.fg)
                Spacer()
                Text(versionString)
                    .font(Theme.mono(10.5, weight: .regular))
                    .tracking(0.6)
                    .foregroundStyle(Theme.fgFaint)
            }

            HStack(spacing: 8) {
                connectionDot
                Text(connectionText)
                    .font(Theme.ui(13, weight: bridge.connectedPeerCount > 0 ? .medium : .regular))
                    .foregroundStyle(bridge.connectedPeerCount > 0 ? Theme.fg : Theme.fgMuted)
            }

            Text(processCountText)
                .font(Theme.mono(11.5, weight: .regular))
                .foregroundStyle(Theme.fgDim)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var connectionDot: some View {
        if bridge.connectedPeerCount > 0 {
            DotIndicator(state: .active, size: 8)
        } else {
            Circle()
                .fill(Theme.statusUnknown)
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Theme.lineSoft, lineWidth: 0.5))
        }
    }

    private var connectionText: String {
        bridge.connectedPeerCount > 0 ? "已连接 iPhone" : "未连接 iPhone"
    }

    private var processCountText: String {
        store.processes.isEmpty
            ? "暂无活跃进程"
            : "监控中：\(store.processes.count) 个 Claude Code 进程"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.processes.isEmpty {
            emptyState
        } else {
            processList
        }
    }

    private var processList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if showFirstUseHint {
                    firstUseHintBanner
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                }
                ForEach(store.processes) { process in
                    MacProcessRow(process: process)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.bgRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.lineSoft, lineWidth: 1)
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "play")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.fgFaint)
            }
            Text("暂无 Claude Code 进程")
                .font(Theme.ui(13, weight: .regular))
                .foregroundStyle(Theme.fgMuted)
            Text("启动 Claude Code 后会自动显示")
                .font(Theme.mono(11, weight: .regular))
                .foregroundStyle(Theme.fgDim)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Banners

    private var hookErrorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.slash")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.statusPerm)
            Text("Hook 配置已失效，点击修复")
                .font(Theme.ui(12, weight: .regular))
                .foregroundStyle(Theme.fg)
            Spacer(minLength: 4)
            Text("修复 →")
                .font(Theme.ui(12, weight: .semibold))
                .foregroundStyle(Theme.statusPerm)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.oklch(0.30, 0.10, 25, alpha: 0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.oklch(0.55, 0.18, 25, alpha: 0.45), lineWidth: 1)
        )
    }

    private var firstUseHintBanner: some View {
        HStack(spacing: 8) {
            Text("💡")
                .font(.system(size: 12))
            Text("图标被挤掉时，可在设置里设置全局快捷键随时唤起")
                .font(Theme.ui(11.5, weight: .regular))
                .foregroundStyle(Theme.fgMuted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.oklch(0.22, 0.011, 250, alpha: 0.6))
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            FooterButton(systemImage: "gearshape", label: "设置", action: onOpenSettings)
            Spacer()
            FooterButton(systemImage: "xmark", label: "退出", action: onQuit)
        }
        .padding(6)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        return "v\(short)"
    }
}

// MARK: - Footer button

private struct FooterButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .regular))
                Text(label)
                    .font(Theme.ui(12.5, weight: .regular))
            }
            .foregroundStyle(Theme.fgMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hover ? Color.oklch(0.22, 0.011, 250) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Process row

struct MacProcessRow: View {
    let process: ClaudeProcess

    @State private var hover = false
    @State private var errorText: String?
    @State private var lastErrorAt: Date?

    var body: some View {
        Button(action: handleTap) {
            HStack(alignment: .center, spacing: 12) {
                DotIndicator(state: process.state, size: 10)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(process.name)
                            .font(Theme.mono(14, weight: .semibold))
                            .foregroundStyle(Theme.fg)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let terminal = process.terminal?.kind.displayName {
                            Text("·")
                                .font(Theme.mono(11, weight: .regular))
                                .foregroundStyle(Theme.fgFaint)
                            Text(terminal)
                                .font(Theme.mono(11, weight: .regular))
                                .foregroundStyle(Theme.fgFaint)
                                .lineLimit(1)
                        }
                    }
                    statusFooter
                    if let errorText {
                        Text(errorText)
                            .font(Theme.mono(10.5, weight: .regular))
                            .foregroundStyle(Theme.statusPerm)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if !canSwitch {
                    Text("窗口不可用")
                        .font(Theme.mono(10.5, weight: .regular))
                        .foregroundStyle(Theme.statusPermDim)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.fgFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hover && canSwitch ? Color.oklch(0.22, 0.011, 250) : Color.clear)
            )
            .opacity(canSwitch ? 1.0 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSwitch)
        .onHover { hover = $0 }
    }

    private var canSwitch: Bool { TerminalSwitcher.canSwitch(process) }

    private func handleTap() {
        guard canSwitch else { return }
        let result = TerminalSwitcher.switch(to: process)
        switch result {
        case .ok, .activatedAppOnly:
            errorText = nil
        case let .unsupported(reason), let .failed(reason):
            errorText = reason
            lastErrorAt = Date()
            // 4s 后自动清掉
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                if let last = lastErrorAt, Date().timeIntervalSince(last) >= 4 {
                    errorText = nil
                }
            }
        }
    }

    private var statusFooter: some View {
        TimelineView(.periodic(from: process.stateChangedAt, by: 1)) { context in
            HStack(spacing: 6) {
                Text(stateLabel)
                    .font(Theme.mono(11.5, weight: .medium))
                    .foregroundStyle(stateColor)
                Text("·")
                    .foregroundStyle(Theme.fgFaint)
                Text("已 \(durationText(now: context.date))")
                    .font(Theme.mono(11.5, weight: .regular))
                    .foregroundStyle(Theme.fgDim)
                    .monospacedDigit()
            }
        }
    }

    private var stateLabel: String {
        switch process.state {
        case .active:            return "运行中"
        case .waitingInput:      return "等待输入"
        case .waitingPermission: return "等待权限"
        case .completed:         return "已结束"
        case .unknown:           return "状态未知"
        }
    }

    private var stateColor: Color {
        switch process.state {
        case .active:            return Theme.statusActive
        case .waitingInput:      return Theme.statusInput
        case .waitingPermission: return Theme.statusPerm
        case .completed, .unknown: return Theme.fgDim
        }
    }

    private func durationText(now: Date) -> String {
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

import SwiftUI
import CCPeekCore

// 主页 layout —— 设计稿: cc-peek-ui/dashboard.jsx + components.jsx (TopChrome / BottomBar / SignalBars / PageIndicator)
// iOS-2a: 横竖屏自适应 + 最多 6 卡片单页 + TabView 分页骨架 + TopBar/BottomBar 占位
// iOS-2c: 卡片增删动画 + 分页指示器宽度过渡

struct DashboardScreen: View {
    let processes: [TransportMessage.SnapshotProcess]
    let macName: String
    let isConnected: Bool
    /// A5 演示模式: TopBar 居中标题改为 "CC PEEK · DEMO" 紫色高亮, 用户随时一眼能识别.
    var isDemo: Bool = false
    let onSettingsTap: () -> Void
    let onMacTap: () -> Void
    let onCardTap: (String) -> Void
    let onRetryConnect: () -> Void
    let onRefresh: () -> Void
    /// PRD 3.3.5 stale window: 非 nil 表示已断开但仍在 5 分钟内 → 显示进程列表(半透明) + 顶部 stale banner.
    let staleSince: Date?
    /// 最近一次 switch_to 失败的进程 → 错误消息(传给 ProcessCardView 显示错误态)
    var switchErrors: [String: String] = [:]

    @State private var currentPage = 0

    private static let pageSize = 6

    private var pages: [[TransportMessage.SnapshotProcess]] {
        guard !processes.isEmpty else { return [] }
        return processes.chunked(into: Self.pageSize)
    }

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                TopBar(macName: macName,
                       isConnected: isConnected,
                       isDemo: isDemo,
                       onMacTap: onMacTap,
                       onSettingsTap: onSettingsTap)

                if let staleSince {
                    StaleBanner(since: staleSince)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if isOffline {
                    DisconnectedView(onRetry: onRetryConnect)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if processes.isEmpty {
                    DashboardEmpty()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    pageContent
                        .opacity(staleSince != nil ? 0.55 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: staleSince != nil)
                }

                BottomBar(currentPage: currentPage,
                          totalPages: max(1, pages.count),
                          isConnected: isConnected)
            }
            .animation(.easeInOut(duration: 0.3), value: staleSince != nil)
        }
        .preferredColorScheme(.dark)
    }

    /// 真正"已离线" — 断开且超出 stale window (或从未连过).
    private var isOffline: Bool { !isConnected && staleSince == nil }

    @ViewBuilder
    private var pageContent: some View {
        GeometryReader { geo in
            let orientation: Orientation = geo.size.width > geo.size.height ? .landscape : .portrait
            let padX: CGFloat = orientation == .landscape ? 20 : 18
            let padY: CGFloat = 8

            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { idx, pageProcs in
                    // PRD 3.6.6 下拉刷新: 每页套 ScrollView, refreshable 即使内容不溢出
                    // 也能识别下拉手势. minHeight 撑满避免 grid 顶部塌陷.
                    ScrollView {
                        DashboardGrid(processes: pageProcs, orientation: orientation, switchErrors: switchErrors, onCardTap: onCardTap)
                            .padding(.init(top: padY, leading: padX, bottom: padX, trailing: padX))
                            .frame(minHeight: geo.size.height)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable {
                        onRefresh()
                        // 给 spinner 露脸时间, 否则刷新瞬间结束没有反馈
                        try? await Task.sleep(nanoseconds: 600_000_000)
                    }
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

}

private enum Orientation { case portrait, landscape }

// MARK: - 卡片网格

private struct DashboardGrid: View {
    let processes: [TransportMessage.SnapshotProcess]
    let orientation: Orientation
    let switchErrors: [String: String]
    let onCardTap: (String) -> Void

    var body: some View {
        let count = min(6, processes.count)
        let (cols, rows) = gridFor(count: count, orientation: orientation)
        let variant = pickVariant(count: count, orientation: orientation)
        let chunks = processes.chunked(into: cols)

        VStack(spacing: 12) {
            ForEach(0..<rows, id: \.self) { rowIdx in
                HStack(spacing: 12) {
                    if rowIdx < chunks.count {
                        ForEach(chunks[rowIdx], id: \.id) { p in
                            ProcessCardView(process: p, variant: variant, switchError: switchErrors[p.id], onTap: onCardTap)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                        // 当前行不足 cols 的位置补 spacer
                        ForEach(0..<(cols - chunks[rowIdx].count), id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: processes.map(\.id))
    }

    // 翻译自 dashboard.jsx 的 gridFor
    private func gridFor(count: Int, orientation: Orientation) -> (cols: Int, rows: Int) {
        let n = max(1, min(6, count))
        switch orientation {
        case .landscape:
            if n <= 3 { return (n, 1) }
            return ((n + 1) / 2, 2)
        case .portrait:
            if n <= 3 { return (1, n) }
            return (2, (n + 1) / 2)
        }
    }

    private func pickVariant(count: Int, orientation: Orientation) -> ProcessCardView.CardVariant {
        if count == 1 { return orientation == .landscape ? .wide : .tall }
        if count <= 3 { return orientation == .landscape ? .wide : .tall }
        return .compact
    }
}

// MARK: - Top bar

private struct TopBar: View {
    let macName: String
    let isConnected: Bool
    let isDemo: Bool
    let onMacTap: () -> Void
    let onSettingsTap: () -> Void

    var body: some View {
        ZStack {
            HStack {
                MacNameButton(name: macName, isConnected: isConnected, action: onMacTap)
                Spacer()
                Button(action: onSettingsTap) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Theme.fgMuted)
                        .frame(width: 36, height: 36)
                        .background(chromeButtonBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // 居中的 page-title; 演示模式时改为紫色 "CC PEEK · DEMO" 加强视觉提示
            Text(isDemo ? "CC PEEK · DEMO" : "CC PEEK")
                .font(Theme.mono(11, weight: .regular))
                .tracking(1.32)        // 0.12em @ 11pt
                .foregroundStyle(isDemo ? Color.oklch(0.78, 0.16, 290) : Theme.fgFaint)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var chromeButtonBackground: some View {
        LinearGradient(
            colors: [Color.oklch(0.24, 0.012, 248), Color.oklch(0.20, 0.010, 250)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct MacNameButton: View {
    let name: String
    let isConnected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SignalBars(connected: isConnected)
                Text(name)
                    .font(Theme.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.fg.opacity(0.6))
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color.oklch(0.24, 0.012, 248), Color.oklch(0.20, 0.010, 250)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Signal bars (4 条高度递增的柱)

private struct SignalBars: View {
    let connected: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            bar(height: 4,  active: true)
            bar(height: 7,  active: true)
            bar(height: 10, active: true)
            bar(height: 13, active: false)
        }
        .frame(height: 13)
    }

    private func bar(height: CGFloat, active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(active && connected ? Theme.statusActive : Theme.fgFaint.opacity(0.4))
            .frame(width: 2.5, height: height)
            .shadow(color: active && connected ? Theme.statusActiveGlow : .clear, radius: 2)
    }
}

// MARK: - Stale banner (PRD 3.3.5: 断开 ≤ 5 分钟时显示, 提醒"非实时, X 分钟前的状态")

private struct StaleBanner: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.statusInput)
                    .frame(width: 6, height: 6)
                    .shadow(color: Theme.statusInputGlow, radius: 2)
                Text(label(elapsed: context.date.timeIntervalSince(since)))
                    .font(Theme.mono(11, weight: .regular))
                    .tracking(0.4)
                    .foregroundStyle(Theme.fgMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color.oklch(0.30, 0.06, 70, alpha: 0.20))
            .overlay(
                Rectangle().fill(Color.oklch(0.50, 0.10, 70, alpha: 0.32)).frame(height: 0.5),
                alignment: .top
            )
            .overlay(
                Rectangle().fill(Color.oklch(0.50, 0.10, 70, alpha: 0.32)).frame(height: 0.5),
                alignment: .bottom
            )
        }
    }

    private func label(elapsed: TimeInterval) -> String {
        let minutes = Int(elapsed / 60)
        if minutes < 1 { return "已断开 · 显示刚才的状态" }
        return "已断开 · 显示 \(minutes) 分钟前的状态"
    }
}

// MARK: - Bottom bar

private struct BottomBar: View {
    let currentPage: Int
    let totalPages: Int
    let isConnected: Bool

    var body: some View {
        HStack {
            Text(isConnected ? "已同步" : "已断开")
                .font(Theme.mono(10, weight: .regular))
                .tracking(1.0)             // 0.1em @ 10pt
                .foregroundStyle(Theme.fgFaint)

            Spacer()

            if totalPages > 1 {
                PageDots(current: currentPage, total: totalPages)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? Theme.statusActive : Theme.fgFaint)
                    .frame(width: 6, height: 6)
                    .shadow(color: isConnected ? Theme.statusActiveGlow : .clear, radius: 3)
                Text(isConnected ? "LIVE" : "OFFLINE")
                    .font(Theme.mono(10, weight: .regular))
                    .tracking(1.0)
                    .foregroundStyle(Theme.fgFaint)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

private struct PageDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Theme.fgMuted : Color.oklch(0.35, 0.012, 250))
                    .frame(width: i == current ? 16 : 5, height: 5)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: current)
    }
}

// MARK: - Disconnected (设计稿 dashboard.jsx Disconnected)

private struct DisconnectedView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color.oklch(0.24, 0.04, 25, alpha: 0.4),
                            Color.oklch(0.18, 0.02, 25, alpha: 0.4)
                        ],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.oklch(0.45, 0.10, 25, alpha: 0.4), lineWidth: 1)
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.oklch(0.55, 0.16, 25, alpha: 0.18), radius: 12)
                Image(systemName: "wifi.slash")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Color.oklch(0.85, 0.10, 25))
            }

            VStack(spacing: 6) {
                Text("未连接 Mac")
                    .font(Theme.ui(17, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                Text("请确认 Mac 端 CC Peek 已启动")
                    .font(Theme.mono(12, weight: .regular))
                    .foregroundStyle(Theme.fgDim)
                    .multilineTextAlignment(.center)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onRetry()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                    Text("重新搜索")
                        .font(Theme.ui(13, weight: .semibold))
                }
                .foregroundStyle(Theme.fg)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color.oklch(0.24, 0.012, 248), Color.oklch(0.20, 0.010, 250)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                .shadow(color: Theme.cardOuterShadow1, radius: 1, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(30)
    }
}

// MARK: - Empty state

private struct DashboardEmpty: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.oklch(0.22, 0.011, 250), Color.oklch(0.18, 0.010, 250)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.cardHighlightSoft, lineWidth: 1)
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: Theme.cardOuterShadow3, radius: 10, x: 0, y: 4)
                Image(systemName: "play.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.fgFaint)
            }

            VStack(spacing: 6) {
                Text("当前没有 Claude Code 进程在运行")
                    .font(Theme.ui(16, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                Text("启动 Claude Code 后会自动显示在这里")
                    .font(Theme.mono(12, weight: .regular))
                    .foregroundStyle(Theme.fgDim)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(30)
    }
}

// MARK: - Helpers

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Preview

#Preview("Dashboard — 6 卡 (compact, portrait)") {
    DashboardScreen(
        processes: sampleProcesses(),
        macName: "MacBook Pro",
        isConnected: true,
        onSettingsTap: {},
        onMacTap: {},
        onCardTap: { _ in },
        onRetryConnect: {},
        onRefresh: {},
        staleSince: nil
    )
}

#Preview("Empty") {
    DashboardScreen(
        processes: [],
        macName: "MacBook Pro",
        isConnected: true,
        onSettingsTap: {},
        onMacTap: {},
        onCardTap: { _ in },
        onRetryConnect: {},
        onRefresh: {},
        staleSince: nil
    )
}

#Preview("3 卡 (tall variant, portrait)") {
    DashboardScreen(
        processes: Array(sampleProcesses().prefix(3)),
        macName: "MacBook Pro",
        isConnected: true,
        onSettingsTap: {},
        onMacTap: {},
        onCardTap: { _ in },
        onRetryConnect: {},
        onRefresh: {},
        staleSince: nil
    )
}

#Preview("Disconnected") {
    DashboardScreen(
        processes: [],
        macName: "MacBook Pro",
        isConnected: false,
        onSettingsTap: {},
        onMacTap: {},
        onCardTap: { _ in },
        onRetryConnect: {},
        onRefresh: {},
        staleSince: nil
    )
}

#Preview("Stale (≤ 5min)") {
    DashboardScreen(
        processes: Array(sampleProcesses().prefix(3)),
        macName: "MacBook Pro",
        isConnected: false,
        onSettingsTap: {},
        onMacTap: {},
        onCardTap: { _ in },
        onRetryConnect: {},
        onRefresh: {},
        staleSince: Date(timeIntervalSinceNow: -120)
    )
}

private func sampleProcesses() -> [TransportMessage.SnapshotProcess] {
    [
        .init(id: "p1", name: "login-refactor", state: .active,
              terminal: "iTerm2", switchable: true,
              startedAt: Date(timeIntervalSinceNow: -1000),
              stateChangedAt: Date(timeIntervalSinceNow: -412)),
        .init(id: "p2", name: "data-pipeline", state: .waitingInput,
              terminal: "Ghostty", switchable: true,
              startedAt: Date(timeIntervalSinceNow: -200),
              stateChangedAt: Date(timeIntervalSinceNow: -38)),
        .init(id: "p3", name: "api-server", state: .waitingPermission,
              terminal: "Terminal", switchable: true,
              startedAt: Date(timeIntervalSinceNow: -100),
              stateChangedAt: Date(timeIntervalSinceNow: -12)),
        .init(id: "p4", name: "docs-site", state: .active,
              terminal: "iTerm2", switchable: true,
              startedAt: Date(timeIntervalSinceNow: -8000),
              stateChangedAt: Date(timeIntervalSinceNow: -7325)),
        .init(id: "p5", name: "auth-tests", state: .unknown,
              terminal: "VS Code", switchable: false,
              startedAt: Date(timeIntervalSinceNow: -300),
              stateChangedAt: Date(timeIntervalSinceNow: -95)),
        .init(id: "p6", name: "api-server #2", state: .active,
              terminal: "Ghostty", switchable: true,
              startedAt: Date(timeIntervalSinceNow: -2000),
              stateChangedAt: Date(timeIntervalSinceNow: -1860))
    ]
}

import SwiftUI
import AppKit
import CCPeekCore
import KeyboardShortcuts

// MARK: - 分类

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case hookConfig
    case pairedPhones
    case permissions
    case terminals
    case general
    case about
    case danger

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hookConfig:   return "Hook 配置"
        case .pairedPhones: return "已配对手机"
        case .permissions:  return "系统权限"
        case .terminals:    return "支持的终端"
        case .general:      return "通用"
        case .about:        return "关于"
        case .danger:       return "危险操作"
        }
    }

    var icon: String {
        switch self {
        case .hookConfig:   return "shield.lefthalf.filled"
        case .pairedPhones: return "iphone"
        case .permissions:  return "lock.shield"
        case .terminals:    return "keyboard"
        case .general:      return "gearshape"
        case .about:        return "questionmark.circle"
        case .danger:       return "xmark.octagon"
        }
    }

    var isDanger: Bool { self == .danger }
}

// MARK: - 主入口

struct SettingsView: View {
    @State private var selection: SettingsCategory = .hookConfig

    // hook 错误检测暂未接通；hookConfig sidebar 项的 badge 红点先固定 false (留待 hook 异常实时检测后接入)
    private let hasHookError = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 180, max: 200)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 560)
        .background(AmbientBackground())
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(SettingsCategory.allCases) { cat in
                    Button {
                        selection = cat
                    } label: {
                        SidebarRow(
                            category: cat,
                            isSelected: selection == cat,
                            showsBadge: cat == .hookConfig && hasHookError
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bgBase)
    }

    @ViewBuilder
    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch selection {
                case .hookConfig:   HookConfigDetail()
                case .pairedPhones: PairedPhonesDetail()
                case .permissions:  PermissionsDetail()
                case .terminals:    TerminalSupportDetail()
                case .general:      GeneralDetail()
                case .about:        AboutDetail()
                case .danger:       DangerZoneDetail()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.clear)
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let category: SettingsCategory
    let isSelected: Bool
    let showsBadge: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: category.icon)
                .font(.system(size: 13, weight: .regular))
                .frame(width: 16)
            Text(category.label)
                .font(Theme.ui(12.5, weight: isSelected ? .semibold : .medium))
            Spacer(minLength: 0)
            if showsBadge {
                Circle()
                    .fill(Theme.statusPerm)
                    .frame(width: 7, height: 7)
                    .shadow(color: Theme.statusPermGlow, radius: 3)
            }
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.oklch(0.28, 0.06, 240, alpha: 0.4) : .clear)
        )
        .contentShape(Rectangle())
    }

    private var textColor: Color {
        if category.isDanger { return Color.oklch(0.80, 0.10, 25) }
        return isSelected ? Theme.fg : Theme.fgMuted
    }
}

// MARK: - Detail Header

private struct DetailHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.ui(17, weight: .semibold))
                .foregroundStyle(Theme.fg)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - 1. Hook 配置

private struct HookConfigDetail: View {
    @State private var hookInstalled = HookInstaller.isInstalled()
    @State private var hookActionMessage: String?
    @State private var showingHookDiff = false
    @State private var hookBusy = false
    @State private var pendingPlan: HookInstaller.Plan?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailHeader(
                title: "Hook 配置",
                trailing: AnyView(
                    Text("~/.claude/settings.json")
                        .font(Theme.mono(11, weight: .regular))
                        .foregroundStyle(Theme.fgDim)
                )
            )

            SurfaceCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        statusIcon
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hookInstalled ? "已配置 — 正常运行中" : "未配置")
                                .font(Theme.ui(13.5, weight: .semibold))
                                .foregroundStyle(Theme.fg)
                            Text(hookInstalled
                                ? "Stop / Notification / SessionStart 等 6 类 Hook 已注册"
                                : "未在 settings.json 中检测到 CC Peek Hook 条目")
                                .font(Theme.mono(11.5, weight: .regular))
                                .foregroundStyle(Theme.fgDim)
                        }
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        Button(hookBusy ? "处理中..." : (hookInstalled ? "重新配置" : "安装 Hook")) {
                            reinstallHook()
                        }
                        .disabled(hookBusy)
                        Button("查看 settings.json") { revealSettingsFile() }
                            .disabled(hookBusy)
                    }
                    if let msg = hookActionMessage {
                        Text(msg)
                            .font(Theme.ui(11.5))
                            .foregroundStyle(Theme.fgDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
        }
        .onAppear { hookInstalled = HookInstaller.isInstalled() }
        .sheet(isPresented: $showingHookDiff) {
            if let plan = pendingPlan {
                HookDiffSheet(plan: plan, onCancel: {
                    showingHookDiff = false
                    pendingPlan = nil
                }, onApply: {
                    showingHookDiff = false
                    pendingPlan = nil
                    applyHook(plan)
                })
            }
        }
    }

    private var statusIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(hookInstalled
                    ? Color.oklch(0.30, 0.10, 150, alpha: 0.4)
                    : Color.oklch(0.30, 0.10, 75, alpha: 0.4))
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(hookInstalled
                    ? Color.oklch(0.50, 0.14, 150, alpha: 0.5)
                    : Color.oklch(0.50, 0.12, 75, alpha: 0.5), lineWidth: 1)
            Image(systemName: hookInstalled ? "checkmark" : "exclamationmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(hookInstalled ? Theme.statusActive : Theme.statusInput)
        }
        .frame(width: 32, height: 32)
    }

    private func reinstallHook() {
        guard !hookBusy else { return }
        hookBusy = true
        hookActionMessage = "正在准备配置预览..."
        Task.detached {
            let plan = HookInstaller.computePlan()
            await MainActor.run {
                pendingPlan = plan
                showingHookDiff = true
                hookBusy = false
                hookActionMessage = nil
            }
        }
    }

    private func applyHook(_ plan: HookInstaller.Plan) {
        guard !hookBusy else { return }
        hookBusy = true
        hookActionMessage = "正在写入配置..."
        Task.detached {
            let (ok, err) = HookInstaller.apply(plan: plan)
            let installed = HookInstaller.isInstalled()
            await MainActor.run {
                hookBusy = false
                hookInstalled = installed
                if ok {
                    hookActionMessage = "已写入. 备份在 \(plan.backupPath ?? "(未备份)")"
                } else {
                    hookActionMessage = "写入失败: \(err ?? "未知错误")"
                }
            }
        }
    }

    private func revealSettingsFile() {
        let url = HookInstaller.settingsFileURL()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - 2. 已配对手机

private struct PairedPhonesDetail: View {
    @State private var paired: [String] = []
    @State private var unpairTarget: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailHeader(title: "已配对手机")

            if paired.isEmpty {
                SurfaceCard {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone.slash")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Theme.fgFaint)
                        Text("尚未配对手机")
                            .font(Theme.ui(13, weight: .medium))
                            .foregroundStyle(Theme.fgMuted)
                        Text("在 iPhone 上打开 CC Peek，确保与 Mac 处于同一 Wi-Fi，然后接受配对邀请。")
                            .font(Theme.ui(11.5))
                            .foregroundStyle(Theme.fgDim)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 28)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                }
            } else {
                SurfaceCard {
                    VStack(spacing: 0) {
                        ForEach(Array(paired.enumerated()), id: \.element) { idx, name in
                            SettingsRow(
                                leadingIcon: "iphone",
                                title: name,
                                subtitle: "已配对",
                                divider: idx < paired.count - 1,
                                trailing: AnyView(
                                    Button("解除配对") { unpairTarget = name }
                                        .controlSize(.small)
                                )
                            )
                        }
                    }
                }
            }

            Text("解除配对后，对应 iPhone 将无法再连接到此 Mac，需要重新走配对流程。")
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.fgDim)
                .padding(.horizontal, 4)
        }
        .onAppear { reload() }
        .alert("解除配对", isPresented: Binding(
            get: { unpairTarget != nil },
            set: { if !$0 { unpairTarget = nil } }
        )) {
            Button("取消", role: .cancel) { unpairTarget = nil }
            Button("解除", role: .destructive) {
                if let name = unpairTarget {
                    PairedClientStorage.remove(name)
                    reload()
                }
                unpairTarget = nil
            }
        } message: {
            if let name = unpairTarget {
                Text("将解除与「\(name)」的配对，下次连接需要重新接受邀请。")
            }
        }
    }

    private func reload() {
        paired = PairedClientStorage.paired.sorted()
    }
}

// MARK: - 3. 系统权限

private struct PermissionsDetail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailHeader(title: "系统权限")

            SurfaceCard {
                VStack(spacing: 0) {
                    SettingsRow(
                        leadingIcon: "play.rectangle",
                        title: "自动化权限",
                        subtitle: "Terminal / iTerm2 切 tab 与窗口激活所需",
                        divider: true,
                        trailing: AnyView(
                            Button("去设置") { openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") }
                                .controlSize(.small)
                        )
                    )
                    SettingsRow(
                        leadingIcon: "wifi",
                        title: "本地网络权限",
                        subtitle: "MultipeerConnectivity 与 iPhone 通信所需",
                        divider: true,
                        trailing: AnyView(
                            Button("去设置") { openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") }
                                .controlSize(.small)
                        )
                    )
                    SettingsRow(
                        leadingIcon: "dot.radiowaves.left.and.right",
                        title: "蓝牙权限",
                        subtitle: "MultipeerConnectivity 设备发现所需",
                        divider: false,
                        trailing: AnyView(
                            Button("去设置") { openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") }
                                .controlSize(.small)
                        )
                    )
                }
            }

            Text("首次使用时系统会按需弹窗请求授权；若已拒绝，需要到「系统设置 > 隐私与安全性」对应分类手动开启。")
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.fgDim)
                .padding(.horizontal, 4)
        }
    }

    private func openURL(_ str: String) {
        if let url = URL(string: str) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - 4. 支持的终端

private struct TerminalSupportDetail: View {
    private struct Item { let name, behavior: String; let tier: Tier }
    private enum Tier { case full, partial, none }

    private let items: [Item] = [
        Item(name: "Terminal.app",   behavior: "激活 app + 精确定位到 tab",   tier: .full),
        Item(name: "iTerm2",         behavior: "激活 app + 精确定位到 tab/pane", tier: .full),
        Item(name: "Ghostty",        behavior: "仅激活 app",                  tier: .partial),
        Item(name: "Warp",           behavior: "仅激活 app",                  tier: .partial),
        Item(name: "VS Code 终端",   behavior: "仅激活窗口",                  tier: .partial),
        Item(name: "其他终端",       behavior: "显示状态，禁用切换",          tier: .none),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailHeader(title: "支持的终端")

            SurfaceCard {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.name) { idx, item in
                        SettingsRow(
                            leading: AnyView(tierDot(item.tier)),
                            title: item.name,
                            subtitle: item.behavior,
                            divider: idx < items.count - 1,
                            trailing: AnyView(tierLabel(item.tier))
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tierDot(_ tier: Tier) -> some View {
        Circle()
            .fill(tierColor(tier))
            .frame(width: 8, height: 8)
            .shadow(color: tierColor(tier).opacity(0.6), radius: 2)
            .frame(width: 16)
    }

    @ViewBuilder
    private func tierLabel(_ tier: Tier) -> some View {
        switch tier {
        case .full:    StatusPill(text: "完整", style: .online)
        case .partial: StatusPill(text: "部分", style: .warning)
        case .none:    StatusPill(text: "不支持", style: .offline)
        }
    }

    private func tierColor(_ tier: Tier) -> Color {
        switch tier {
        case .full:    return Theme.statusActive
        case .partial: return Theme.statusInput
        case .none:    return Theme.fgFaint
        }
    }
}

// MARK: - 5. 通用

private struct GeneralDetail: View {
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var shortcutAtMouse = UserDefaults.standard.bool(
        forKey: DashboardPresenter.shortcutOpensAtMouseKey
    )
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailHeader(title: "通用")

            SurfaceCard {
                VStack(spacing: 0) {
                    SettingsRow(
                        leadingIcon: "command",
                        title: "全局快捷键",
                        subtitle: "随时唤起 Dashboard；菜单栏图标被遮挡时也能用",
                        divider: true,
                        trailing: AnyView(
                            KeyboardShortcuts.Recorder(for: .togglePeek)
                                .controlSize(.small)
                        )
                    )
                    SettingsRow(
                        leadingIcon: "cursorarrow",
                        title: "快捷键在鼠标位置打开",
                        subtitle: "开启后, 按下快捷键时主页面以鼠标为中心弹出; 关闭则贴菜单栏图标",
                        divider: true,
                        trailing: AnyView(
                            Toggle("", isOn: Binding(
                                get: { shortcutAtMouse },
                                set: { newValue in
                                    shortcutAtMouse = newValue
                                    UserDefaults.standard.set(
                                        newValue,
                                        forKey: DashboardPresenter.shortcutOpensAtMouseKey
                                    )
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        )
                    )
                    SettingsRow(
                        leadingIcon: "power",
                        title: "开机自启",
                        subtitle: "系统登录时自动启动 CC Peek",
                        divider: true,
                        trailing: AnyView(
                            Toggle("", isOn: Binding(
                                get: { launchAtLogin },
                                set: { setLaunchAtLogin($0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        )
                    )
                    SettingsRow(
                        leadingIcon: "arrow.down.circle",
                        title: "自动检查更新",
                        subtitle: "暂未实现 (Sparkle 集成后置)",
                        divider: false,
                        trailing: AnyView(
                            Toggle("", isOn: .constant(false))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(true)
                                .opacity(0.5)
                        )
                    )
                }
            }

            if !LaunchAtLoginManager.hint.isEmpty {
                Text(LaunchAtLoginManager.hint)
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.fgDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            if let msg = statusMessage {
                Text(msg)
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.fgDim)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let result = LaunchAtLoginManager.setEnabled(enabled)
        switch result {
        case .success:
            launchAtLogin = LaunchAtLoginManager.isEnabled
        case .failure(let err):
            statusMessage = "开机自启切换失败: \(err.localizedDescription)"
            launchAtLogin = LaunchAtLoginManager.isEnabled
        }
    }
}

// MARK: - 6. 关于

private struct AboutDetail: View {
    @State private var showingUninstallSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailHeader(title: "关于")

            SurfaceCard {
                VStack(spacing: 0) {
                    SettingsRow(
                        leadingIcon: "tag",
                        title: "版本",
                        subtitle: nil,
                        divider: true,
                        trailing: AnyView(
                            Text(versionString)
                                .font(Theme.mono(12, weight: .regular))
                                .foregroundStyle(Theme.fgDim)
                        )
                    )
                    SettingsRow(
                        leadingIcon: "doc.text.magnifyingglass",
                        title: "诊断日志",
                        subtitle: "查看最近 24 小时的运行日志",
                        divider: true,
                        trailing: AnyView(
                            Button("查看") { DiagnosticLogWindowController.show() }
                                .controlSize(.small)
                        )
                    )
                    SettingsRow(
                        leadingIcon: "sparkles",
                        title: "重看引导",
                        subtitle: "重新运行首次配置流程",
                        divider: true,
                        trailing: AnyView(
                            Button("打开") { OnboardingWindowController.show(force: true) }
                                .controlSize(.small)
                        )
                    )
                    SettingsRow(
                        leadingIcon: "trash",
                        title: "卸载说明",
                        subtitle: "如何完全移除 CC Peek",
                        divider: false,
                        trailing: AnyView(
                            Button("查看") { showingUninstallSheet = true }
                                .controlSize(.small)
                        )
                    )
                }
            }

            FAQCard()
        }
        .sheet(isPresented: $showingUninstallSheet) {
            UninstallInstructionsSheet(onClose: { showingUninstallSheet = false })
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "v\(short) (\(build))"
    }
}

// MARK: - FAQ 卡片 (MacUI-2.5)

private struct FAQCard: View {
    private struct Item: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    private let items: [Item] = [
        Item(
            question: "菜单栏图标看不见怎么办？",
            answer: "可能被 Bartender / Hidden Bar / 刘海 / 其他 app 挤出可见区域。两条兜底：① 在「通用 → 全局快捷键」里录制热键，按下即可唤起 Dashboard；② 用 Spotlight / Launchpad 重新打开 CC Peek，会自动在屏幕右上角弹出 Dashboard。"
        ),
        Item(
            question: "想让图标固定在菜单栏右侧？",
            answer: "macOS 原生方式：按住 ⌘ 键拖动菜单栏图标到希望的位置，系统会记住顺序。Bartender / Hidden Bar 等第三方工具有各自的固定逻辑，参考其设置。"
        ),
        Item(
            question: "想彻底关闭 / 卸载 CC Peek？",
            answer: "关闭进程：Dashboard 底部「退出」按钮，或终端 pkill -f CCPeekMac。完整卸载请见「关于 → 卸载说明」（清理 settings.json 中的 hook、应用数据、LaunchAgent 后再删除 .app）。"
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("常见问题")
                .font(Theme.ui(13, weight: .semibold))
                .foregroundStyle(Theme.fgMuted)
                .padding(.horizontal, 4)

            SurfaceCard {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        FAQRow(question: item.question, answer: item.answer)
                        if idx < items.count - 1 {
                            DottedDivider()
                                .padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
    }
}

private struct FAQRow: View {
    let question: String
    let answer: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.fgMuted)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(question)
                        .font(Theme.ui(12.5, weight: .medium))
                        .foregroundStyle(Theme.fg)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(answer)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.fgDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .padding(.leading, 24) // 与 chevron 对齐
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct UninstallInstructionsSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("卸载 CC Peek")
                .font(Theme.ui(15, weight: .semibold))
                .foregroundStyle(Theme.fg)
            Text("""
            完整卸载步骤：

            1. 在「设置 → 危险操作」中点击「清理配置信息」，移除 settings.json 中的 Hook 条目和应用数据。
            2. 退出 CC Peek（菜单栏图标 → 退出）。
            3. 将 /Applications/CCPeek.app 拖到废纸篓。
            4. 如已开启开机自启，删除 ~/Library/LaunchAgents/me.lifawei.ccpeek.agent.plist。
            """)
                .font(Theme.ui(12))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("好的", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.bgRaised)
        .preferredColorScheme(.dark)
    }
}

// MARK: - 7. 危险操作

private struct DangerZoneDetail: View {
    @State private var showingCleanupConfirm = false
    @State private var cleanupDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailHeader(title: "危险操作")

            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("清理 CC Peek 写入到 ~/.claude/settings.json 的 Hook 配置、所有已配对设备信息、应用数据 (events.jsonl 与归档) 和偏好设置。清理后 app 将回到初始状态。")
                        .font(Theme.ui(12.5))
                        .foregroundStyle(Theme.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        showingCleanupConfirm = true
                    } label: {
                        Label("清理配置信息", systemImage: "trash")
                            .font(Theme.ui(12.5, weight: .semibold))
                    }
                    .buttonStyle(DangerButtonStyle())
                    if cleanupDone {
                        Text("已清理。可将 CC Peek.app 从 Applications 拖到废纸篓完成卸载。")
                            .font(Theme.ui(11.5))
                            .foregroundStyle(Theme.statusActive)
                    }
                }
                .padding(16)
            }
        }
        .alert("清理 CC Peek 的配置数据?", isPresented: $showingCleanupConfirm) {
            Button("取消", role: .cancel) { }
            Button("清理", role: .destructive) { performCleanup() }
        } message: {
            Text("将移除 settings.json 中的 hook 条目, 删除 ~/Library/Application Support/cc-peek/ 下的应用数据 (含 events.jsonl 与归档).\n\n如需完全卸载, 清理后请将 CC Peek.app 从 Applications 拖到废纸篓.")
        }
    }

    private func performCleanup() {
        HookInstaller.uninstall()
        let appSupport = AppPaths.appSupportDirectory
        try? FileManager.default.removeItem(at: appSupport)
        AppPaths.ensureAppSupportDirectory()
        cleanupDone = true
    }
}

private struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [
                        Color.oklch(0.32, 0.14, 25, alpha: configuration.isPressed ? 0.75 : 0.55),
                        Color.oklch(0.24, 0.10, 25, alpha: configuration.isPressed ? 0.75 : 0.55),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.oklch(0.55, 0.18, 25, alpha: 0.5), lineWidth: 1)
            )
            .foregroundStyle(Color.oklch(0.92, 0.10, 25))
    }
}

// MARK: - SettingsRow (公共行布局)

private struct SettingsRow: View {
    var leading: AnyView? = nil
    var leadingIcon: String? = nil
    let title: String
    var subtitle: String? = nil
    var divider: Bool = true
    var trailing: AnyView? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let leading {
                    leading
                } else if let leadingIcon {
                    Image(systemName: leadingIcon)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Theme.fgMuted)
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.ui(13, weight: .medium))
                        .foregroundStyle(Theme.fg)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.ui(11.5))
                            .foregroundStyle(Theme.fgDim)
                    }
                }
                Spacer()
                if let trailing { trailing }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if divider {
                DottedDivider()
                    .padding(.horizontal, 14)
            }
        }
    }
}

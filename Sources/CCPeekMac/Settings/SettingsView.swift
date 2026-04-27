import SwiftUI
import AppKit
import CCPeekCore

struct SettingsView: View {
    @State private var hookInstalled = HookInstaller.isInstalled()
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var hookActionMessage: String?
    @State private var showingCleanupConfirm = false
    @State private var cleanupDone = false
    @State private var showingHookDiff = false
    @State private var pendingPlan: HookInstaller.Plan?

    private let supportedTerminals: [(String, String)] = [
        ("Terminal.app", "✅ 完整支持"),
        ("iTerm2", "✅ 完整支持"),
        ("Ghostty", "🟡 仅激活 app"),
        ("Warp", "🟡 仅激活 app"),
        ("VS Code 终端", "🟡 仅激活窗口"),
        ("其他终端", "❌ 不支持"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hookSection
                permissionSection
                terminalSupportSection
                generalSection
                aboutSection
                dangerousSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 620)
        .onAppear { refresh() }
        .alert("清理 CC Peek 的配置数据?", isPresented: $showingCleanupConfirm) {
            Button("取消", role: .cancel) { }
            Button("清理", role: .destructive) { performCleanup() }
        } message: {
            Text("将移除 ~/.claude/settings.json 中的 hook 条目, 删除 ~/Library/Application Support/cc-peek/ 下的应用数据 (含 events.jsonl 与归档).\n\n如需完全卸载, 清理后请将 CC Peek.app 从 Applications 拖到废纸篓.")
        }
        .sheet(isPresented: $showingHookDiff) {
            if let plan = pendingPlan {
                HookDiffSheet(plan: plan, onCancel: {
                    showingHookDiff = false
                    pendingPlan = nil
                }, onApply: {
                    let (ok, err) = HookInstaller.apply(plan: plan)
                    showingHookDiff = false
                    pendingPlan = nil
                    if ok {
                        hookInstalled = HookInstaller.isInstalled()
                        hookActionMessage = "已写入. 备份在 \(plan.backupPath ?? "(未备份)")"
                    } else {
                        hookActionMessage = "写入失败: \(err ?? "未知错误")"
                    }
                })
            }
        }
    }

    // MARK: - Sections

    private var hookSection: some View {
        SectionView(title: "Hook 配置") {
            HStack(spacing: 8) {
                if hookInstalled {
                    Label("已配置", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("未配置", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Spacer()
                Button("重新配置") { reinstallHook() }
                Button("查看 settings.json") { revealSettingsFile() }
            }
            if let msg = hookActionMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionSection: some View {
        SectionView(title: "系统权限") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("自动化")
                    Spacer()
                    Text("Terminal/iTerm2 切换需要")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("去设置") { openAutomationSettings() }
                }
                Text("首次点击进程卡片时系统会弹窗请求授权; 若已拒绝, 请到 系统设置 > 隐私与安全性 > 自动化 修复.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var terminalSupportSection: some View {
        SectionView(title: "支持的终端") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(supportedTerminals, id: \.0) { item in
                    HStack {
                        Text(item.0)
                        Spacer()
                        Text(item.1).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var generalSection: some View {
        SectionView(title: "通用") {
            HStack {
                Toggle("开机自启", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                Spacer()
                Text(LaunchAtLoginManager.statusDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if !LaunchAtLoginManager.hint.isEmpty {
                Text(LaunchAtLoginManager.hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var aboutSection: some View {
        SectionView(title: "关于") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(versionString).foregroundStyle(.secondary)
                }
                HStack {
                    Text("诊断日志")
                    Spacer()
                    Button("查看") { DiagnosticLogWindowController.show() }
                    Button("重看引导") { OnboardingWindowController.show(force: true) }
                }
                Text("卸载说明: 设置中点 \"清理配置信息\", 然后将 CC Peek.app 从 Applications 拖到废纸篓.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    private var dangerousSection: some View {
        SectionView(title: "危险操作") {
            VStack(alignment: .leading, spacing: 6) {
                Button(role: .destructive) {
                    showingCleanupConfirm = true
                } label: {
                    Label("清理配置信息", systemImage: "trash")
                }
                if cleanupDone {
                    Text("已清理. 现在可以将 CC Peek.app 从 Applications 拖到废纸篓.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func refresh() {
        hookInstalled = HookInstaller.isInstalled()
        launchAtLogin = LaunchAtLoginManager.isEnabled
    }

    private func reinstallHook() {
        pendingPlan = HookInstaller.computePlan()
        showingHookDiff = true
    }

    private func revealSettingsFile() {
        let url = HookInstaller.settingsFileURL()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let result = LaunchAtLoginManager.setEnabled(enabled)
        switch result {
        case .success:
            launchAtLogin = LaunchAtLoginManager.isEnabled
        case .failure(let err):
            hookActionMessage = "开机自启切换失败: \(err.localizedDescription)"
            launchAtLogin = LaunchAtLoginManager.isEnabled
        }
    }

    private func performCleanup() {
        HookInstaller.uninstall()
        // 删 ~/Library/Application Support/cc-peek/ 下数据
        let appSupport = AppPaths.appSupportDirectory
        try? FileManager.default.removeItem(at: appSupport)
        AppPaths.ensureAppSupportDirectory()
        cleanupDone = true
        hookInstalled = false
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

private struct SectionView<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

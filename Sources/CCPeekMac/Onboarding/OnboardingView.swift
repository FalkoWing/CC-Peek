import SwiftUI
import AppKit
import CCPeekCore

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome
        case permissions
        case hookConfig
        case done
    }

    @State private var step: Step = .welcome
    @State private var plan: HookInstaller.Plan = HookInstaller.computePlan()
    @State private var applyError: String?
    @State private var applied = false

    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(28)
            }
            .frame(maxHeight: .infinity)

            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 720, height: 640)
    }

    // MARK: - Step body

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:    welcomeView
        case .permissions: permissionsView
        case .hookConfig: hookConfigView
        case .done:       doneView
        }
    }

    private var welcomeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepBadge("1 / 3")
            Text("欢迎使用 CC Peek").font(.system(size: 22, weight: .bold))
            Text("让 Claude Code 多进程的状态从主屏幕外置出来——菜单栏看一眼就知道哪个进程在等你, 一键就能切到对应终端窗口.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Group {
                bullet("✦ 实时显示所有 Claude Code 进程的状态")
                bullet("✦ 等待审批 / 等待输入时菜单栏徽章数字提醒")
                bullet("✦ 点卡片直接激活对应终端窗口")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepBadge("2 / 3")
            Text("系统权限").font(.system(size: 20, weight: .bold))
            Text("CC Peek 完整运行需要以下权限. 现在不必立即授予, 在你第一次使用相关功能时系统会自动弹窗.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                permissionRow(
                    icon: "terminal",
                    title: "自动化 (Automation)",
                    desc: "用 AppleScript 控制 Terminal / iTerm2 切到目标 tab. 拒绝后切换功能不可用, 状态显示不受影响."
                )
                permissionRow(
                    icon: "wifi",
                    title: "本地网络 / 蓝牙 (M3 启用)",
                    desc: "用于 iPhone 第二屏的 MPC 通信. 当前 MVP 没用到, M3 (iPhone 端) 上线后才请求."
                )
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hookConfigView: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepBadge("3 / 3")
            Text("配置 Claude Code hook").font(.system(size: 20, weight: .bold))
            Text("CC Peek 会往 ~/.claude/settings.json 写入 6 个 hook 条目, 用来采集进程状态. 应用前会自动备份原文件.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HookDiffView(plan: plan)

            if let err = applyError {
                Label(err, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var doneView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("配置完成").font(.system(size: 22, weight: .bold))
            Text("现在可以开始使用 Claude Code 了, 状态会实时出现在菜单栏 popover 里.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(role: .cancel) {
                onFinish()
            } label: {
                Text(step == .done ? "关闭" : "跳过引导")
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if step != .welcome && step != .done {
                Button("上一步") {
                    if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
                }
            }
            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome, .permissions:
            Button("继续") {
                if let next = Step(rawValue: step.rawValue + 1) { step = next }
            }
            .keyboardShortcut(.defaultAction)
        case .hookConfig:
            Button(plan.isNoOp ? "已是最新, 完成" : "应用并继续") {
                applyHook()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(applied)
        case .done:
            Button("开始使用") { onFinish() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    private func applyHook() {
        let (ok, err) = HookInstaller.apply(plan: plan)
        if ok {
            applied = true
            applyError = nil
            step = .done
        } else {
            applyError = err
        }
    }

    // MARK: - Helpers

    private func stepBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.secondary.opacity(0.15))
            )
    }

    private func bullet(_ text: String) -> some View {
        Text(text).font(.system(size: 13))
    }

    private func permissionRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(desc).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

import SwiftUI

/// 在设置 / 引导外, 让"重新配置"按钮也能弹出 diff 预览的 sheet 包装.
struct HookDiffSheet: View {
    let plan: HookInstaller.Plan
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Hook 配置预览")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                }
                HookDiffView(plan: plan)
            }
            .padding(20)

            Divider()
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(plan.isNoOp ? "已是最新" : "应用", action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan.isNoOp)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 760, height: 480)
    }
}

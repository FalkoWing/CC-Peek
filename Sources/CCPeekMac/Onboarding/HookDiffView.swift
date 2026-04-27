import SwiftUI

/// 简单的 before/after diff 预览. 不做行级高亮 (那个工作量太大且容易看不清),
/// 只两列等宽文本对照, 让用户一眼看出"哪边多了什么".
struct HookDiffView: View {
    let plan: HookInstaller.Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                column(title: "当前 ~/.claude/settings.json",
                       text: plan.existingText.isEmpty ? "(文件不存在, 应用后将创建)" : plan.existingText)
                column(title: "应用后",
                       text: plan.targetText,
                       highlight: true)
            }
            footerNote
        }
    }

    private func column(title: String, text: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView(.vertical) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(height: 280)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(highlight ? Color.green.opacity(0.06) : Color.secondary.opacity(0.05))
            )
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let backup = plan.backupPath, !plan.willCreateSettingsFile {
                Label("应用前会备份到 \(backup)", systemImage: "tray.and.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if plan.willCreateSettingsFile {
                Label("settings.json 不存在, 将创建新文件", systemImage: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if plan.isNoOp {
                Label("当前配置已是最新, 应用后内容不变", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Label("hook 二进制: \(plan.hookCommandPath)", systemImage: "terminal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

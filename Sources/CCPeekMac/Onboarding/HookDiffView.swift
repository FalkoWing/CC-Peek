import SwiftUI

/// 单列 diff 预览：保留目标 settings.json 的上下文行，新增/变化行用 `+` 和绿色底色标出。
struct HookDiffView: View {
    let plan: HookInstaller.Plan

    private var diffLines: [DiffLine] {
        DiffLine.build(existingText: plan.existingText, targetText: plan.targetText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                        diffRow(line)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 280)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.bgDeepest)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.lineSoft, lineWidth: 1)
            )
            .textSelection(.enabled)

            footerNote
        }
    }

    private func diffRow(_ line: DiffLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(line.kind == .added ? "+" : " ")
                .font(Theme.mono(11.5, weight: .semibold))
                .foregroundStyle(line.kind == .added ? Theme.statusActive : Theme.fgFaint)
                .frame(width: 18, alignment: .leading)
            Text(line.text.isEmpty ? " " : line.text)
                .font(Theme.mono(11.5))
                .foregroundStyle(line.kind == .added ? Color.oklch(0.90, 0.10, 150) : Theme.fgMuted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 1.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(line.kind == .added ? Color.oklch(0.30, 0.06, 150, alpha: 0.18) : Color.clear)
    }

    @ViewBuilder
    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let backup = plan.backupPath, !plan.willCreateSettingsFile {
                Label("应用前会自动备份原配置文件到 \(backup)", systemImage: "checkmark")
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if plan.willCreateSettingsFile {
                Label("settings.json 不存在，将创建新文件", systemImage: "plus.circle")
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.fgDim)
            }
            if plan.isNoOp {
                Label("当前配置已是最新，应用后内容不变", systemImage: "checkmark")
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.statusActive)
            }
        }
    }
}

private struct DiffLine {
    enum Kind { case context, added }

    let kind: Kind
    let text: String

    static func build(existingText: String, targetText: String) -> [DiffLine] {
        let existing = normalizedLines(existingText)
        let target = normalizedLines(targetText)

        guard !target.isEmpty else { return [] }
        guard !existing.isEmpty else {
            return target.map { DiffLine(kind: .added, text: $0) }
        }

        var remainingExistingLines: [String: Int] = [:]
        for line in existing {
            remainingExistingLines[line, default: 0] += 1
        }

        return target.map { line in
            if let count = remainingExistingLines[line], count > 0 {
                remainingExistingLines[line] = count - 1
                return DiffLine(kind: .context, text: line)
            }
            return DiffLine(kind: .added, text: line)
        }
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}

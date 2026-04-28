import SwiftUI
import AppKit
import CCPeekCore

struct DiagnosticLogView: View {
    @State private var entries: [DiagnosticLogger.Entry] = []
    @State private var filter: DiagnosticLogger.Severity? = nil

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 0) {
                toolbar
                Divider().background(Theme.lineSoft)
                if filteredEntries.isEmpty {
                    emptyView
                } else {
                    table
                }
                Divider().background(Theme.lineSoft)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgBase)
        .preferredColorScheme(.dark)
        .onAppear { reload() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $filter) {
                Text("全部").tag(DiagnosticLogger.Severity?.none)
                Text("仅错误").tag(DiagnosticLogger.Severity?.some(.error))
                Text("错误 + 警告").tag(DiagnosticLogger.Severity?.some(.warning))
                Text("仅信息").tag(DiagnosticLogger.Severity?.some(.info))
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 130)

            Text("\(entries.count) 条记录")
                .font(Theme.mono(11, weight: .regular))
                .tracking(0.6)
                .foregroundStyle(Theme.fgFaint)

            Spacer()

            Button { reload() } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ChromeButtonStyle())

            Button { exportLog() } label: {
                Label("导出日志", systemImage: "arrow.up.right")
            }
            .buttonStyle(ChromeButtonStyle())

            Button {
                DiagnosticLogger.clear()
                reload()
            } label: {
                Label("清空", systemImage: "trash")
            }
            .buttonStyle(ChromeButtonStyle(danger: true))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.oklch(0.17, 0.009, 250))
    }

    private var table: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { idx, entry in
                    row(entry)
                    if idx < filteredEntries.count - 1 {
                        Divider()
                            .background(Color.oklch(0.22, 0.011, 250, alpha: 0.5))
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func row(_ entry: DiagnosticLogger.Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(Theme.mono(11.5, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(Theme.fgFaint)
                .frame(width: 110, alignment: .leading)

            TypePill(category: entry.category, severity: entry.severity)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.message)
                    .font(Theme.mono(12))
                    .foregroundStyle(messageColor(entry.severity))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !entry.context.isEmpty {
                    Text(formatContext(entry.context))
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.fgFaint)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.fgFaint)
            Text("最近 24 小时无诊断记录")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.fgDim)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text(DiagnosticLogger.fileURL.path)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.fgFaint)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.oklch(0.17, 0.009, 250))
    }

    // MARK: -

    private var filteredEntries: [DiagnosticLogger.Entry] {
        guard let filter else { return entries }
        switch filter {
        case .error:   return entries.filter { $0.severity == .error }
        case .warning: return entries.filter { $0.severity == .error || $0.severity == .warning }
        case .info:    return entries.filter { $0.severity == .info }
        }
    }

    private func reload() {
        entries = DiagnosticLogger.recentEntries()
    }

    private func formatContext(_ ctx: [String: String]) -> String {
        ctx.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "  ")
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ccpeek-diagnostic-\(Int(Date().timeIntervalSince1970)).log"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.copyItem(at: DiagnosticLogger.fileURL, to: dest)
        }
    }

    private func messageColor(_ s: DiagnosticLogger.Severity) -> Color {
        switch s {
        case .error:   return Color.oklch(0.88, 0.10, 25)
        case .warning: return Color.oklch(0.90, 0.08, 75)
        case .info:    return Theme.fgMuted
        }
    }
}

// MARK: - 类型 pill

/// 把 DiagnosticLogger.category (如 "transport", "switch") 映射为设计稿的 6 类 pill (HOOK/COMM/PARSE/AS/PROC/EVT).
/// 未知 category 兜底为大写前 4 个字符 + 灰色.
private struct TypePill: View {
    let category: String
    let severity: DiagnosticLogger.Severity

    var body: some View {
        Text(label)
            .font(Theme.mono(9.5, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.oklch(0.20, 0.010, 250))
                    .overlay(Capsule().strokeBorder(color.opacity(severity == .error ? 1.0 : 0.6), lineWidth: 1))
            )
            .frame(width: 56, alignment: .center)
    }

    private var mapping: (label: String, color: Color) {
        switch category.lowercased() {
        case "transport", "comm", "mpc":
            return ("COMM", Theme.accent)
        case "switch", "resolve", "process", "process-fail":
            return ("PROC", Theme.statusInput)
        case "applescript", "as":
            return ("AS", Theme.statusInput)
        case "hook", "hook-config":
            return ("HOOK", Theme.statusActive)
        case "parse", "parse-fail":
            return ("PARSE", Theme.statusInput)
        case "events", "event", "evt", "prune":
            return ("EVT", Theme.statusUnknown)
        default:
            // 兜底：大写前 4 字符
            let upper = category.uppercased()
            return (String(upper.prefix(4)), Theme.fgFaint)
        }
    }

    private var label: String { mapping.label }
    private var color: Color { mapping.color }
}

// MARK: - Chrome button style (toolbar 用)

private struct ChromeButtonStyle: ButtonStyle {
    var danger: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(11.5))
            .foregroundStyle(danger ? Color.oklch(0.85, 0.12, 25) : Theme.fgMuted)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                LinearGradient(
                    colors: [
                        Color.oklch(0.24, 0.012, 248, alpha: configuration.isPressed ? 0.65 : 1.0),
                        Color.oklch(0.20, 0.010, 250, alpha: configuration.isPressed ? 0.65 : 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        danger
                            ? Color.oklch(0.45, 0.14, 25, alpha: 0.4)
                            : Theme.cardHighlightSoft,
                        lineWidth: 0.5
                    )
            )
    }
}

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
        VStack(spacing: 0) {
            toolbar
            Divider()

            if filteredEntries.isEmpty {
                emptyView
            } else {
                table
            }

            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { reload() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("严重度", selection: $filter) {
                Text("全部").tag(DiagnosticLogger.Severity?.none)
                Text("仅错误").tag(DiagnosticLogger.Severity?.some(.error))
                Text("错误 + 警告").tag(DiagnosticLogger.Severity?.some(.warning))
                Text("仅信息").tag(DiagnosticLogger.Severity?.some(.info))
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            Spacer()

            Text("最近 24 小时, \(entries.count) 条")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("刷新") { reload() }
            Button("导出") { exportLog() }
            Button(role: .destructive) {
                DiagnosticLogger.clear()
                reload()
            } label: {
                Text("清空")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var table: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredEntries) { entry in
                    row(entry)
                    Divider().opacity(0.5)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func row(_ entry: DiagnosticLogger.Entry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            severityBadge(entry.severity)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(Self.timeFormatter.string(from: entry.timestamp))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(entry.category)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(entry.message)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                if !entry.context.isEmpty {
                    Text(formatContext(entry.context))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func severityBadge(_ s: DiagnosticLogger.Severity) -> some View {
        let (color, label): (Color, String) = {
            switch s {
            case .error:   return (.red, "ERR")
            case .warning: return (.orange, "WARN")
            case .info:    return (.blue, "INFO")
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
            .frame(width: 44, alignment: .center)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("最近 24 小时无诊断记录")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text(DiagnosticLogger.fileURL.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
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
}

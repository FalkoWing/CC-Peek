import SwiftUI
import CCPeekCore

struct DashboardView: View {
    @ObservedObject var store: ProcessStateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if store.processes.isEmpty {
                emptyState
            } else {
                processList
            }

            Divider()

            footer
        }
        .frame(width: 360, height: 480)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.fill")
                .foregroundStyle(.secondary)
            Text("监控中: \(store.processes.count) 个进程")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("暂无 Claude Code 进程")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("启动 Claude Code 后会自动显示")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var processList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(store.processes) { process in
                    ProcessCardView(process: process) { _ in }
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                SettingsWindowController.show()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text("设置")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("退出")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

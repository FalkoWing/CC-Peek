import Foundation
import CCPeekCore

/// 演示模式专用 Transport. 模拟一台已配对 Mac 的完整通信链路:
/// start → onPeerDiscovered → onPeerConnected → 自动吐 snapshot → 周期性 stateUpdate / snapshot.
///
/// 设计目标: PeekClient / UI 走真实代码路径, 不需要任何"isDemo 分支".
/// 未来 TransportMessage 加新 case, 这里跟着补就行, UI 自动覆盖.
final class DemoTransport: Transport {

    static let demoMacName = "Demo Mac"

    var onPeerDiscovered: ((TransportPeer) -> Void)?
    var onPeerLost: ((TransportPeer) -> Void)?
    var onPeerConnected: ((TransportPeer) -> Void)?
    var onPeerDisconnected: ((TransportPeer) -> Void)?
    var onReceive: ((TransportMessage, TransportPeer) -> Void)?

    var connectedPeers: [TransportPeer] { connected ? [demoPeer] : [] }

    private let demoPeer = TransportPeer(id: DemoTransport.demoMacName, displayName: DemoTransport.demoMacName)
    private var connected = false
    private var processes: [TransportMessage.SnapshotProcess] = []
    private var stateTimer: Timer?
    private var lifecycleTimer: Timer?
    private var lifecycleTickCount = 0
    private var addPoolCursor = 0

    func start() {
        // 模拟"扫描发现 → 自动连接"时序, 与真实 MPC 节奏接近
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.onPeerDiscovered?(self.demoPeer)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, !self.connected else { return }
            self.connected = true
            self.onPeerConnected?(self.demoPeer)
            self.startSimulation()
        }
    }

    func stop() {
        stateTimer?.invalidate()
        stateTimer = nil
        lifecycleTimer?.invalidate()
        lifecycleTimer = nil
        if connected {
            connected = false
            onPeerDisconnected?(demoPeer)
        }
        processes = []
    }

    func send(_ message: TransportMessage, to peer: TransportPeer) throws {
        guard connected, peer.id == demoPeer.id else {
            throw TransportError.notConnected(peerId: peer.id)
        }
        // 异步回调避免 onCardTap → send → onReceive 同步路径里 SwiftUI 重入抖动
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch message {
            case .snapshotRequest:
                self.emitSnapshot()
            case .switchTo(let payload):
                self.handleSwitch(payload)
            case .unpairNotification:
                self.stop()
            default:
                break
            }
        }
    }

    // MARK: - simulation

    private func startSimulation() {
        processes = Self.makeInitialProcesses()
        emitSnapshot()

        stateTimer = Timer.scheduledTimer(withTimeInterval: 5.5, repeats: true) { [weak self] _ in
            self?.tickStateChange()
        }
        lifecycleTimer = Timer.scheduledTimer(withTimeInterval: 18, repeats: true) { [weak self] _ in
            self?.tickLifecycle()
        }
    }

    private func emitSnapshot() {
        onReceive?(.snapshot(.init(processes: processes)), demoPeer)
    }

    private func handleSwitch(_ payload: TransportMessage.SwitchTo) {
        let target = processes.first(where: { $0.id == payload.processId })
        // 不可切的进程: 让卡片真显示一次切换失败错误态 (覆盖 PRD 错误态视觉)
        let success = target?.switchable ?? false
        let result = TransportMessage.SwitchResult(
            processId: payload.processId,
            success: success,
            errorMessage: success ? nil : String(localized: "演示模式: 该进程暂不可切换")
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.onReceive?(.switchResult(result), self.demoPeer)
        }
    }

    /// 周期性切一个进程的状态. 让用户能看到颜色 / 呼吸节奏切换 / 状态过渡动画.
    private func tickStateChange() {
        guard !processes.isEmpty else { return }
        let idx = Int.random(in: 0..<processes.count)
        let candidates: [ProcessState] = [.active, .waitingInput, .waitingPermission, .completed]
        let current = processes[idx].state
        let next = candidates.filter { $0 != current }.randomElement() ?? .active
        let now = Date()
        let p = processes[idx]
        processes[idx] = .init(
            id: p.id, name: p.name, state: next, terminal: p.terminal,
            switchable: p.switchable, startedAt: p.startedAt, stateChangedAt: now
        )
        onReceive?(.stateUpdate(.init(processId: p.id, state: next, timestamp: now)), demoPeer)
    }

    /// 周期性增删一个进程, 让用户能看到卡片增删动画 (PRD 3.6.6 scale + opacity transition).
    private func tickLifecycle() {
        lifecycleTickCount += 1
        // 奇数次加 (上限 6 即一页), 偶数次删 (下限 2 保持页面有内容)
        if lifecycleTickCount % 2 == 1, processes.count < 6 {
            let pool = Self.lifecycleAddPool
            let template = pool[addPoolCursor % pool.count]
            addPoolCursor += 1
            let now = Date()
            let new = TransportMessage.SnapshotProcess(
                id: template.id + "-\(lifecycleTickCount)",
                name: template.name,
                state: template.state,
                terminal: template.terminal,
                switchable: template.switchable,
                startedAt: now,
                stateChangedAt: now
            )
            processes.append(new)
        } else if processes.count > 2 {
            processes.removeLast()
        }
        emitSnapshot()
    }

    // MARK: - fixtures

    private static func makeInitialProcesses() -> [TransportMessage.SnapshotProcess] {
        let now = Date()
        return [
            .init(id: "demo-auth", name: "auth-refactor",
                  state: .active, terminal: "iTerm2",
                  switchable: true,
                  startedAt: now.addingTimeInterval(-720),
                  stateChangedAt: now.addingTimeInterval(-12)),
            .init(id: "demo-api", name: "api-gateway",
                  state: .waitingInput, terminal: "Terminal",
                  switchable: true,
                  startedAt: now.addingTimeInterval(-1850),
                  stateChangedAt: now.addingTimeInterval(-26)),
            .init(id: "demo-deploy", name: "deploy-script",
                  state: .waitingPermission, terminal: "Ghostty",
                  switchable: true,
                  startedAt: now.addingTimeInterval(-95),
                  stateChangedAt: now.addingTimeInterval(-7)),
            .init(id: "demo-docs", name: "docs-site",
                  state: .completed, terminal: "iTerm2",
                  switchable: true,
                  startedAt: now.addingTimeInterval(-3200),
                  stateChangedAt: now.addingTimeInterval(-180)),
        ]
    }

    private static let lifecycleAddPool: [TransportMessage.SnapshotProcess] = [
        .init(id: "demo-pipeline", name: "data-pipeline",
              state: .active, terminal: "Warp",
              switchable: true, startedAt: Date(), stateChangedAt: Date()),
        // 演示一个不可切换的进程, 让用户在演示中也能看到 disabled 卡片视觉
        .init(id: "demo-frontend", name: "frontend",
              state: .waitingInput, terminal: "VS Code",
              switchable: false, startedAt: Date(), stateChangedAt: Date()),
        .init(id: "demo-perf", name: "perf-tests",
              state: .active, terminal: "Terminal",
              switchable: true, startedAt: Date(), stateChangedAt: Date()),
    ]
}

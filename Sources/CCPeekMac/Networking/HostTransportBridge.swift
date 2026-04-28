import Foundation
import Combine
import AppKit
import CCPeekCore

/// Mac 端 (host) 与 iPhone 端的桥. 负责把 ProcessStateStore 的状态推到 transport,
/// 以及处理来自 iPhone 的 snapshot_request / switch_to 指令.
///
/// 推送策略 (PRD 3.3.4 推为主 + 拉为辅):
/// - 进程状态变化 -> state_update (单条)
/// - 进程增删    -> snapshot (整份, 简单可靠地 reconcile, 协议无 add/remove)
/// - 收 snapshot_request -> snapshot
/// - 收 switch_to        -> 调 TerminalSwitcher, 回 switch_result
@MainActor
final class HostTransportBridge: ObservableObject {
    /// 当前连接的 iPhone 数量（菜单栏图标连接绿点订阅这个）
    @Published private(set) var connectedPeerCount: Int = 0

    private let transport: MPCTransport
    private let store: ProcessStateStore
    private var cancellables: Set<AnyCancellable> = []
    private var lastPushed: [String: ClaudeProcess] = [:]

    init(store: ProcessStateStore, displayName: String? = nil) {
        let name = displayName ?? Host.current().localizedName ?? "Mac"
        self.store = store
        self.transport = MPCTransport(displayName: name, role: .host)
    }

    func start() {
        transport.onPeerConnected = { [weak self] peer in
            // PRD 3.3.5: 连上后 iPhone 必发 snapshot_request, host 不主动 push
            // (避免和 snapshot_request 的回包重复一份).
            DiagnosticLogger.info("transport", "peer connected", context: ["peer": peer.displayName])
            Task { @MainActor in self?.refreshPeerCount() }
        }
        transport.onPeerDisconnected = { [weak self] peer in
            DiagnosticLogger.info("transport", "peer disconnected", context: ["peer": peer.displayName])
            Task { @MainActor in self?.refreshPeerCount() }
        }
        transport.onReceive = { [weak self] message, peer in
            self?.handleIncoming(message, from: peer)
        }
        transport.onInvitationReceived = { [weak self] peer, accept in
            // MVP 1:1 (PRD 3.7.1): 已连一台时拒绝新邀请, 即使是已配对设备.
            // 拒绝即可, 不附 reason: MPC invitationHandler 不支持携带文本.
            if let connected = self?.transport.connectedPeers, !connected.isEmpty {
                DiagnosticLogger.info("transport", "拒绝邀请: 已有连接 (1:1 约束)", context: [
                    "peer": peer.displayName,
                    "connected": connected.map(\.displayName).joined(separator: ","),
                ])
                accept(false)
                return
            }
            // 已配对: 静默接受. 未配对: 弹 NSAlert 询问用户.
            if PairedClientStorage.contains(peer.displayName) {
                DiagnosticLogger.info("transport", "auto-accept paired", context: ["peer": peer.displayName])
                accept(true)
                return
            }
            let trusted = HostTransportBridge.askUserToTrust(peer: peer)
            if trusted {
                PairedClientStorage.add(peer.displayName)
                DiagnosticLogger.info("transport", "user accepted pairing", context: ["peer": peer.displayName])
            } else {
                DiagnosticLogger.info("transport", "user rejected pairing", context: ["peer": peer.displayName])
            }
            accept(trusted)
        }
        transport.start()

        store.$processes
            .sink { [weak self] processes in
                self?.diffAndPush(processes)
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        transport.stop()
        connectedPeerCount = 0
    }

    private func refreshPeerCount() {
        connectedPeerCount = transport.connectedPeers.count
    }

    // MARK: - 推送

    private func diffAndPush(_ current: [ClaudeProcess]) {
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let lastIDs = Set(lastPushed.keys)
        let currentIDs = Set(currentByID.keys)

        let added = currentIDs.subtracting(lastIDs)
        let removed = lastIDs.subtracting(currentIDs)
        let stateChanges: [ClaudeProcess] = currentIDs.intersection(lastIDs).compactMap { id in
            guard let now = currentByID[id], let prev = lastPushed[id], now.state != prev.state else {
                return nil
            }
            return now
        }

        defer { lastPushed = currentByID }

        let peers = transport.connectedPeers
        guard !peers.isEmpty else { return }

        for proc in stateChanges {
            let msg = TransportMessage.stateUpdate(.init(
                processId: proc.id,
                state: proc.state,
                timestamp: proc.stateChangedAt
            ))
            broadcast(msg, to: peers)
        }

        if !added.isEmpty || !removed.isEmpty {
            broadcast(.snapshot(makeSnapshot(from: current)), to: peers)
        }
    }

    private func sendSnapshot(to peer: TransportPeer) {
        do {
            try transport.send(.snapshot(makeSnapshot(from: store.processes)), to: peer)
        } catch {
            DiagnosticLogger.error("transport", "snapshot 发送失败", context: [
                "peer": peer.displayName,
                "error": error.localizedDescription,
            ])
        }
    }

    private func broadcast(_ message: TransportMessage, to peers: [TransportPeer]) {
        for peer in peers {
            do {
                try transport.send(message, to: peer)
            } catch {
                DiagnosticLogger.warn("transport", "推送失败", context: [
                    "peer": peer.displayName,
                    "error": error.localizedDescription,
                ])
            }
        }
    }

    private func makeSnapshot(from procs: [ClaudeProcess]) -> TransportMessage.Snapshot {
        TransportMessage.Snapshot(processes: procs.map { proc in
            TransportMessage.SnapshotProcess(
                id: proc.id,
                name: proc.name,
                state: proc.state,
                terminal: proc.terminal?.kind.displayName,
                switchable: proc.terminal != nil,
                startedAt: proc.startedAt,
                stateChangedAt: proc.stateChangedAt
            )
        })
    }

    // MARK: - 接收

    private func handleIncoming(_ message: TransportMessage, from peer: TransportPeer) {
        switch message {
        case .snapshotRequest:
            sendSnapshot(to: peer)
        case .switchTo(let payload):
            handleSwitchTo(payload, from: peer)
        case .unpairNotification:
            PairedClientStorage.remove(peer.displayName)
            DiagnosticLogger.info("transport", "client unpaired", context: ["peer": peer.displayName])
        case .stateUpdate, .snapshot, .switchResult:
            // host 端不期望从 iPhone 收到这些
            break
        }
    }

    /// 阻塞式 NSAlert. 在 main queue 调用. 30s 超时自动拒绝避免邀请方超时.
    private static func askUserToTrust(peer: TransportPeer) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "信任新设备?"
        alert.informativeText = "iPhone “\(peer.displayName)” 想要连接到 CC Peek。\n仅信任你认识的设备。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "信任并配对")
        alert.addButton(withTitle: "拒绝")
        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    private func handleSwitchTo(_ payload: TransportMessage.SwitchTo, from peer: TransportPeer) {
        guard let proc = store.processes.first(where: { $0.id == payload.processId }) else {
            replySwitch(processId: payload.processId, success: false, error: "进程不存在", to: peer)
            return
        }
        let result = TerminalSwitcher.switch(to: proc)
        switch result {
        case .ok, .activatedAppOnly:
            replySwitch(processId: payload.processId, success: true, error: nil, to: peer)
        case .unsupported(let reason):
            replySwitch(processId: payload.processId, success: false, error: reason, to: peer)
        case .failed(let reason):
            replySwitch(processId: payload.processId, success: false, error: reason, to: peer)
        }
    }

    private func replySwitch(processId: String, success: Bool, error: String?, to peer: TransportPeer) {
        let msg = TransportMessage.switchResult(.init(
            processId: processId,
            success: success,
            errorMessage: error
        ))
        do {
            try transport.send(msg, to: peer)
        } catch {
            DiagnosticLogger.warn("transport", "switch_result 发送失败", context: [
                "peer": peer.displayName,
                "error": error.localizedDescription,
            ])
        }
    }
}

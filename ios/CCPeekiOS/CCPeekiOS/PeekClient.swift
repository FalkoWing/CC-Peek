import Foundation
import Combine
import UIKit
import CCPeekCore

/// iOS-1b: 配对感知客户端.
/// - 未配对: browse, 把发现的 host 暴露给 UI 让用户选, 选中后调 selectAndPair.
/// - 已配对: browse, 一旦发现 displayName 匹配的 host 自动 invite.
///
/// A5 演示模式: 用 DemoTransport 替换真实 MPCTransport, 上层 UI 完全无感.
/// invite 不在 Transport 协议上 (各 transport 实现细节差异大), 用 inviteHandler 闭包桥接.
final class PeekClient: ObservableObject {

    enum Mode { case real, demo }

    enum Status: Equatable {
        case idle
        case browsing            // 已 start, 还没发现任何 host
        case awaitingSelection   // 未配对, 已发现至少一个 host, 等用户选
        case connecting(peer: String)
        case connected(peer: String)
        case disconnected
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var discoveredHosts: [TransportPeer] = []
    @Published private(set) var pairedHostName: String?
    @Published private(set) var processes: [TransportMessage.SnapshotProcess] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastSwitchResult: TransportMessage.SwitchResult?
    /// 最近一次 switch_to 失败的进程 → 错误消息. 卡片据此显示"切换失败"错误态,
    /// 3s 后自动清除避免一直挡着.
    @Published private(set) var switchErrors: [String: String] = [:]
    /// 上次 peer disconnect 的时间. 用于 PRD 3.3.5 的 "断开 ≤ 5 分钟保留最后已知状态" 分层判断.
    @Published private(set) var lastDisconnectedAt: Date?

    let isDemo: Bool

    var isPaired: Bool { pairedHostName != nil }

    /// PRD 3.3.5 stale window: 断开后保留最后已知状态展示的时长上限 (秒).
    static let staleWindow: TimeInterval = 300

    private let transport: any Transport
    private let inviteHandler: (TransportPeer, String?) -> Void
    private var currentPeer: TransportPeer?
    private var pairedHostToken: String?
    private var pendingPairing: (host: TransportPeer, token: String)?
    private var pairingTimeoutTask: Task<Void, Never>?
    private var presenceTickTimer: AnyCancellable?
    private var switchErrorClearTasks: [String: Task<Void, Never>] = [:]

    init(mode: Mode = .real) {
        switch mode {
        case .real:
            let name = UIDevice.current.name
            let mpc = MPCTransport(displayName: name, role: .client, autoInvite: false)
            self.transport = mpc
            self.inviteHandler = { [weak mpc] peer, token in
                let context = token.flatMap { TransportInvitationContext.encode(pairingToken: $0) }
                mpc?.invite(peer, context: context)
            }
            let pairedHost = PairedHostStorage.pairedHost
            self.pairedHostName = pairedHost?.displayName
            self.pairedHostToken = pairedHost?.token
            self.isDemo = false
        case .demo:
            let demo = DemoTransport()
            self.transport = demo
            // demo 在 start() 后自动走 discover→connected, 不需要 invite.
            self.inviteHandler = { _, _ in }
            self.pairedHostName = DemoTransport.demoMacName
            self.isDemo = true
        }
        wireCallbacks()
        startPresenceTicker()
    }

    func start() {
        status = .browsing
        transport.start()
    }

    func stop() {
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = nil
        pendingPairing = nil
        transport.stop()
        status = .idle
    }

    /// 用于"重新搜索"按钮: 重启 transport, 已配对状态下会自动重新邀请配对的 host
    func restart() {
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = nil
        pendingPairing = nil
        transport.stop()
        discoveredHosts = []
        currentPeer = nil
        status = .idle
        transport.start()
        status = .browsing
    }

    /// 未配对状态下用户从 device list 点击一个 host: 生成临时 token + 邀请.
    /// 只有 Mac 接受并真正连上后才持久化, 避免拒绝/超时时误进入已配对态.
    func selectAndPair(_ host: TransportPeer) {
        let token = Self.makePairingToken()
        pendingPairing = (host: host, token: token)
        status = .connecting(peer: host.displayName)
        inviteHandler(host, token)
        startPairingTimeout(for: host)
    }

    /// 解除配对: 通知 host (best-effort) + 清本地 + 重启 transport.
    func unpair() {
        if let peer = currentPeer {
            try? transport.send(.unpairNotification, to: peer)
        }
        PairedHostStorage.clear()
        pairedHostName = nil
        pairedHostToken = nil
        pendingPairing = nil
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = nil
        currentPeer = nil
        processes = []
        lastSwitchResult = nil

        // 重启 transport 以清掉所有 discovered / connected 状态,
        // 让 UI 干净进入未配对设备列表.
        transport.stop()
        discoveredHosts = []
        status = .idle
        transport.start()
        status = .browsing
    }

    func requestSnapshot() {
        guard let peer = currentPeer else { return }
        do {
            try transport.send(.snapshotRequest, to: peer)
        } catch {
            lastError = String(describing: error)
        }
    }

    func switchTo(_ processId: String) {
        guard let peer = currentPeer else { return }
        do {
            try transport.send(.switchTo(.init(processId: processId)), to: peer)
        } catch {
            lastError = String(describing: error)
        }
    }

    /// 仅在断开期间需触发 objectWillChange 让 UI 重算 stale → offline 边界.
    /// 30s tick 对 5min 阈值的精度足够 (最大延迟 30s, 用户感知不到).
    private func startPresenceTicker() {
        presenceTickTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.lastDisconnectedAt != nil else { return }
                self.objectWillChange.send()
            }
    }

    private static func makePairingToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "") +
            UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    private func startPairingTimeout(for host: TransportPeer) {
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(12))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.currentPeer == nil,
                      self.pendingPairing?.host.id == host.id else { return }
                self.pendingPairing = nil
                self.status = self.discoveredHosts.isEmpty ? .browsing : .awaitingSelection
                self.lastError = "配对未完成,请确认 Mac 端已接受邀请"
                self.pairingTimeoutTask = nil
            }
        }
    }

    private func wireCallbacks() {
        transport.onPeerDiscovered = { [weak self] peer in
            guard let self else { return }
            if !self.discoveredHosts.contains(where: { $0.id == peer.id }) {
                self.discoveredHosts.append(peer)
            }
            if let paired = self.pairedHostName, peer.displayName == paired, self.currentPeer == nil {
                // 已配对 host 出现, 自动 invite
                self.status = .connecting(peer: peer.displayName)
                self.inviteHandler(peer, self.pairedHostToken)
            } else if self.pairedHostName == nil, self.currentPeer == nil {
                self.status = .awaitingSelection
            }
        }

        transport.onPeerLost = { [weak self] peer in
            guard let self else { return }
            self.discoveredHosts.removeAll { $0.id == peer.id }
            if self.currentPeer == nil {
                self.status = self.discoveredHosts.isEmpty ? .browsing : .awaitingSelection
            }
        }

        transport.onPeerConnected = { [weak self] peer in
            guard let self else { return }
            self.currentPeer = peer
            self.lastDisconnectedAt = nil
            if let pending = self.pendingPairing, pending.host.id == peer.id {
                PairedHostStorage.savePaired(peer.displayName, token: pending.token)
                self.pairedHostName = peer.displayName
                self.pairedHostToken = pending.token
                self.pendingPairing = nil
                self.pairingTimeoutTask?.cancel()
                self.pairingTimeoutTask = nil
            }
            self.status = .connected(peer: peer.displayName)
            do {
                try self.transport.send(.snapshotRequest, to: peer)
            } catch {
                self.lastError = String(describing: error)
            }
        }

        transport.onPeerDisconnected = { [weak self] peer in
            guard let self else { return }
            if self.currentPeer?.id == peer.id { self.currentPeer = nil }
            if self.pendingPairing?.host.id == peer.id {
                self.pendingPairing = nil
                self.pairingTimeoutTask?.cancel()
                self.pairingTimeoutTask = nil
            }
            guard self.pairedHostName != nil else {
                self.status = self.discoveredHosts.isEmpty ? .browsing : .awaitingSelection
                return
            }
            // PRD 3.3.5: 不清 processes, 让 UI 在 stale window 内继续展示最后已知状态.
            // 超出 stale window 由 ContentView 基于 lastDisconnectedAt 决策切到 offline 大屏.
            self.lastDisconnectedAt = Date()
            self.status = .disconnected
        }

        transport.onReceive = { [weak self] message, _ in
            guard let self else { return }
            switch message {
            case .snapshot(let snap):
                self.processes = snap.processes
            case .stateUpdate(let upd):
                if let idx = self.processes.firstIndex(where: { $0.id == upd.processId }) {
                    let old = self.processes[idx]
                    self.processes[idx] = .init(
                        id: old.id,
                        name: old.name,
                        state: upd.state,
                        terminal: old.terminal,
                        switchable: old.switchable,
                        startedAt: old.startedAt,
                        stateChangedAt: upd.timestamp
                    )
                }
            case .switchResult(let result):
                self.lastSwitchResult = result
                self.switchErrorClearTasks[result.processId]?.cancel()
                self.switchErrorClearTasks.removeValue(forKey: result.processId)
                if result.success {
                    self.switchErrors.removeValue(forKey: result.processId)
                } else {
                    let message = result.errorMessage ?? "切换失败"
                    self.switchErrors[result.processId] = message
                    let pid = result.processId
                    self.switchErrorClearTasks[pid] = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(3))
                        await MainActor.run {
                            guard let self else { return }
                            self.switchErrors.removeValue(forKey: pid)
                            self.switchErrorClearTasks.removeValue(forKey: pid)
                        }
                    }
                }
            case .unpairNotification:
                // host 主动解除? 暂时同等处理: 清本地配对
                self.unpair()
            default:
                break
            }
        }
    }
}

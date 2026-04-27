import Foundation
import Combine
import UIKit
import CCPeekCore

/// iOS-1b: 配对感知客户端.
/// - 未配对: browse, 把发现的 host 暴露给 UI 让用户选, 选中后调 selectAndPair.
/// - 已配对: browse, 一旦发现 displayName 匹配的 host 自动 invite.
final class PeekClient: ObservableObject {

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

    var isPaired: Bool { pairedHostName != nil }

    private let transport: MPCTransport
    private var currentPeer: TransportPeer?

    init() {
        let name = UIDevice.current.name
        self.transport = MPCTransport(displayName: name, role: .client, autoInvite: false)
        self.pairedHostName = PairedHostStorage.pairedHostName
        wireCallbacks()
    }

    func start() {
        status = .browsing
        transport.start()
    }

    func stop() {
        transport.stop()
        status = .idle
    }

    /// 用于"重新搜索"按钮: 重启 transport, 已配对状态下会自动重新邀请配对的 host
    func restart() {
        transport.stop()
        discoveredHosts = []
        currentPeer = nil
        status = .idle
        transport.start()
        status = .browsing
    }

    /// 未配对状态下用户从 device list 点击一个 host: 持久化 + 邀请.
    func selectAndPair(_ host: TransportPeer) {
        PairedHostStorage.savePaired(host.displayName)
        pairedHostName = host.displayName
        status = .connecting(peer: host.displayName)
        transport.invite(host)
    }

    /// 解除配对: 通知 host (best-effort) + 清本地 + 重启 transport.
    func unpair() {
        if let peer = currentPeer {
            try? transport.send(.unpairNotification, to: peer)
        }
        PairedHostStorage.clear()
        pairedHostName = nil
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

    private func wireCallbacks() {
        transport.onPeerDiscovered = { [weak self] peer in
            guard let self else { return }
            if !self.discoveredHosts.contains(where: { $0.id == peer.id }) {
                self.discoveredHosts.append(peer)
            }
            if let paired = self.pairedHostName, peer.displayName == paired, self.currentPeer == nil {
                // 已配对 host 出现, 自动 invite
                self.status = .connecting(peer: peer.displayName)
                self.transport.invite(peer)
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
            self.processes = []
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
            case .unpairNotification:
                // host 主动解除? 暂时同等处理: 清本地配对
                self.unpair()
            default:
                break
            }
        }
    }
}

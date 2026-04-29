import Foundation
import MultipeerConnectivity

/// 基于 MultipeerConnectivity 的 Transport 实现. macOS + iOS 共用.
///
/// 拓扑约定 (MVP):
/// - Mac 端以 host (advertiser) 角色运行, 等待 iPhone 来连;
/// - iPhone 端以 client (browser) 角色运行, 发现到 Mac 后自动邀请;
/// - 邀请到达 host 时本类默认接受. 真正的"配对白名单"由上层在 onInvitationReceived hook 上拦截 (后续配对持久化时接入);
/// - Session 加密强制开启 (MCEncryptionPreference.required), 由系统提供 TLS.
public final class MPCTransport: NSObject, Transport {

    // MARK: - 公开接口 (Transport)

    public var onPeerDiscovered: ((TransportPeer) -> Void)?
    public var onPeerLost: ((TransportPeer) -> Void)?
    public var onPeerConnected: ((TransportPeer) -> Void)?
    public var onPeerDisconnected: ((TransportPeer) -> Void)?
    public var onReceive: ((TransportMessage, TransportPeer) -> Void)?

    /// 收到邀请时的决策 hook. 默认接受所有邀请. 上层可设置为
    /// 检查 peerID 是否在配对白名单. handler 必须调用一次 accept.
    public var onInvitationReceived: ((TransportPeer, @escaping (Bool) -> Void) -> Void)?

    public var connectedPeers: [TransportPeer] {
        session.connectedPeers.map(Self.peer)
    }

    // MARK: - 配置

    private let myPeerID: MCPeerID
    private let serviceType: String
    private let role: TransportRole
    private let autoInvite: Bool
    private let pauseDiscoveryWhileConnected: Bool

    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var isRunning = false

    /// browser 发现的 peer 缓存. 上层手动 invite 时凭 displayName 反查 MCPeerID.
    private var discoveredMCPeers: [String: MCPeerID] = [:]

    /// session 不健康检测: 短时间内多次 disconnect 触发整盘重建.
    /// 阈值: 10 秒内 >= 3 次 disconnect.
    private var disconnectTimestamps: [Date] = []
    private static let unhealthyWindow: TimeInterval = 10
    private static let unhealthyThreshold = 3

    /// - Parameters:
    ///   - displayName: 本端展示名. 推荐 Mac 用 Host.current().localizedName, iOS 用 UIDevice.current.name.
    ///   - role: host (Mac) / client (iPhone) / both.
    ///   - serviceType: 双方必须一致, 默认 TransportServiceType.mvp ("cc-peek-v1").
    ///   - autoInvite: client 角色发现 peer 后是否自动 invite. 默认 true (mock client 行为).
    ///                 iOS 端配对模式下传 false, 由 UI 让用户选目标后再调 `invite(_:)`.
    ///   - pauseDiscoveryWhileConnected: 连接建立后暂停 Bonjour 广告/浏览, 断开后恢复.
    ///                                  MVP 是 1:1 连接, 连接期间继续发现只会增加后台工作量.
    public init(
        displayName: String,
        role: TransportRole,
        serviceType: String = TransportServiceType.mvp,
        autoInvite: Bool = true,
        pauseDiscoveryWhileConnected: Bool = true
    ) {
        // displayName 限制: ≤ 63 bytes UTF-8, 非空. 截断保险.
        let safeName = MPCTransport.sanitize(displayName: displayName)
        self.myPeerID = MCPeerID(displayName: safeName)
        self.serviceType = serviceType
        self.role = role
        self.autoInvite = autoInvite
        self.pauseDiscoveryWhileConnected = pauseDiscoveryWhileConnected
        self.session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        super.init()
        self.session.delegate = self
    }

    /// 上层手动邀请已发现的 peer (autoInvite=false 时用).
    /// 没找到对应 MCPeerID (没被发现 / 已 lost) 时静默无效.
    public func invite(_ peer: TransportPeer) {
        guard let mc = discoveredMCPeers[peer.id], let browser else { return }
        browser.invitePeer(mc, to: session, withContext: nil, timeout: 10)
    }

    public func start() {
        isRunning = true
        resumeDiscoveryIfAppropriate()
    }

    public func stop() {
        isRunning = false
        stopDiscovery(clearDiscoveredPeers: true)
        session.disconnect()
    }

    public func send(_ message: TransportMessage, to peer: TransportPeer) throws {
        guard let target = session.connectedPeers.first(where: { $0.displayName == peer.id }) else {
            throw TransportError.notConnected(peerId: peer.id)
        }
        let data: Data
        do {
            data = try TransportCoding.encode(message)
        } catch {
            throw TransportError.encodingFailed(underlying: error)
        }
        do {
            try session.send(data, toPeers: [target], with: .reliable)
        } catch {
            throw TransportError.sendFailed(underlying: error)
        }
    }

    // MARK: - 内部

    private func resumeDiscoveryIfAppropriate() {
        guard isRunning else { return }
        guard !pauseDiscoveryWhileConnected || session.connectedPeers.isEmpty else { return }

        switch role {
        case .host:
            startAdvertiserIfNeeded()
        case .client:
            startBrowserIfNeeded()
        case .both:
            startAdvertiserIfNeeded()
            startBrowserIfNeeded()
        }
    }

    private func pauseDiscoveryForActiveConnection() {
        guard pauseDiscoveryWhileConnected, !session.connectedPeers.isEmpty else { return }
        stopDiscovery(clearDiscoveredPeers: false)
    }

    private func stopDiscovery(clearDiscoveredPeers: Bool) {
        advertiser?.delegate = nil
        advertiser?.stopAdvertisingPeer()
        advertiser = nil

        browser?.delegate = nil
        browser?.stopBrowsingForPeers()
        browser = nil

        if clearDiscoveredPeers {
            discoveredMCPeers.removeAll()
        }
    }

    private func startAdvertiserIfNeeded() {
        guard advertiser == nil else { return }
        let adv = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )
        adv.delegate = self
        adv.startAdvertisingPeer()
        self.advertiser = adv
    }

    private func startBrowserIfNeeded() {
        guard browser == nil else { return }
        let br = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        br.delegate = self
        br.startBrowsingForPeers()
        self.browser = br
    }

    fileprivate static func peer(_ id: MCPeerID) -> TransportPeer {
        TransportPeer(id: id.displayName, displayName: id.displayName)
    }

    private static func sanitize(displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "cc-peek-device"
        let raw = trimmed.isEmpty ? fallback : trimmed
        // 63 bytes UTF-8 上限, 安全截到 32 字符.
        return String(raw.prefix(32))
    }
}

// MARK: - Session

extension MPCTransport: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peer = Self.peer(peerID)
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .connected:
                self?.pauseDiscoveryForActiveConnection()
                self?.onPeerConnected?(peer)
            case .notConnected:
                self?.onPeerDisconnected?(peer)
                self?.recordDisconnectAndMaybeRebuild()
                self?.resumeDiscoveryIfAppropriate()
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    /// 在 main queue 调用. 记录 disconnect 时间戳, 超阈值则重建 session.
    private func recordDisconnectAndMaybeRebuild() {
        let now = Date()
        disconnectTimestamps.append(now)
        let cutoff = now.addingTimeInterval(-Self.unhealthyWindow)
        disconnectTimestamps.removeAll { $0 < cutoff }

        guard disconnectTimestamps.count >= Self.unhealthyThreshold else { return }
        rebuildSession()
    }

    /// 整盘重建: stop -> 新 session -> 按 role 重新 start.
    /// 副作用: 当前所有连接会断, client 端依赖自身的 browser 自动重连.
    private func rebuildSession() {
        disconnectTimestamps.removeAll()
        stopDiscovery(clearDiscoveredPeers: true)

        session.disconnect()
        session.delegate = nil

        session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self

        resumeDiscoveryIfAppropriate()
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let peer = Self.peer(peerID)
        guard let message = try? TransportCoding.decode(data) else {
            // 解码失败静默丢弃. MVP 不打印; 真出问题时由调用方在 onReceive 里加日志.
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onReceive?(message, peer)
        }
    }

    // MVP 不传 stream / resource.
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Advertiser

extension MPCTransport: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let peer = Self.peer(peerID)
        let accept: (Bool) -> Void = { [weak self] ok in
            guard let self else { return }
            invitationHandler(ok, ok ? self.session : nil)
        }
        DispatchQueue.main.async { [weak self] in
            if let hook = self?.onInvitationReceived {
                hook(peer, accept)
            } else {
                accept(true)
            }
        }
    }

    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        // MVP: 静默. 上层若需要可加 onError 回调.
    }
}

// MARK: - Browser

extension MPCTransport: MCNearbyServiceBrowserDelegate {
    public func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        let peer = Self.peer(peerID)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.discoveredMCPeers[peer.id] = peerID
            self.onPeerDiscovered?(peer)
            if self.autoInvite {
                browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
            }
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peer = Self.peer(peerID)
        DispatchQueue.main.async { [weak self] in
            self?.discoveredMCPeers[peer.id] = nil
            self?.onPeerLost?(peer)
        }
    }

    public func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        // MVP: 静默.
    }
}

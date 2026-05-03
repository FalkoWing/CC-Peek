import Foundation

/// 跨设备双向通信抽象. MVP 唯一实现是 MPCTransport (基于 Multipeer Connectivity).
///
/// 设计为 protocol 是为了在 MPC 表现不达预期时, 可以替换为
/// WebSocketTransport / BLETransport, 上层不需要改动.
public protocol Transport: AnyObject {
    /// 启动广告 / 浏览. 需要在用户授予本地网络权限后调用.
    func start()

    /// 停止广告 / 浏览, 断开所有 session.
    func stop()

    /// 发送一条消息给指定 peer. 失败抛错 (peer 不在线 / 编码失败 / 系统错误).
    func send(_ message: TransportMessage, to peer: TransportPeer) throws

    /// 已连接的 peers 列表.
    var connectedPeers: [TransportPeer] { get }

    // 事件回调. 使用前赋值; 在主队列回调.
    var onPeerDiscovered: ((TransportPeer) -> Void)? { get set }
    var onPeerLost: ((TransportPeer) -> Void)? { get set }
    var onPeerConnected: ((TransportPeer) -> Void)? { get set }
    var onPeerDisconnected: ((TransportPeer) -> Void)? { get set }
    var onReceive: ((TransportMessage, TransportPeer) -> Void)? { get set }
}

/// 抽象的对端身份. 不直接暴露 MPC 的 MCPeerID, 让 Transport 协议保持平台无关.
public struct TransportPeer: Hashable, Sendable {
    /// 稳定标识. MPCTransport 实现里取 MCPeerID.displayName.
    public let id: String
    /// 给用户看的设备名 (一般同 id, 但保留扩展余地).
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public enum TransportError: Error, LocalizedError {
    case notConnected(peerId: String)
    case encodingFailed(underlying: Error)
    case sendFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .notConnected(let id): return "对端未连接: \(id)"
        case .encodingFailed(let e): return "消息编码失败: \(e.localizedDescription)"
        case .sendFailed(let e): return "消息发送失败: \(e.localizedDescription)"
        }
    }
}

/// 端在 MPC 拓扑中的角色.
/// - host: 仅广告 (Mac 端默认)
/// - client: 仅浏览 (iPhone 端默认)
/// - both: 同时广告和浏览 (调试场景, 提高发现成功率)
public enum TransportRole: String, Sendable {
    case host
    case client
    case both
}

/// MPC service type 的全局约束: 1-15 字符, 仅 [a-z0-9-], 不能以连字符开头/结尾.
/// 该常量是 Mac/iPhone 双方必须一致才能互相发现的唯一字符串.
public enum TransportServiceType {
    public static let mvp = "cc-peek-v1"
}

/// MPC invitation context 里的轻量配对凭证.
/// displayName 只用于展示和查找, 自动重连必须额外校验这个随机 token.
public enum TransportInvitationContext {
    private struct Payload: Codable {
        let version: Int
        let pairingToken: String

        enum CodingKeys: String, CodingKey {
            case version
            case pairingToken = "pairing_token"
        }
    }

    public static func encode(pairingToken: String) -> Data? {
        guard !pairingToken.isEmpty else { return nil }
        return try? JSONEncoder().encode(Payload(version: 1, pairingToken: pairingToken))
    }

    public static func pairingToken(from data: Data?) -> String? {
        guard let data,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == 1,
              !payload.pairingToken.isEmpty else {
            return nil
        }
        return payload.pairingToken
    }
}

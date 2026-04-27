import Foundation

/// 跨设备的应用层消息. JSON 编码, 通过 Transport 收发.
/// Schema 与 PRD 3.3.3 节一一对应; 新增功能加新 case 不破坏旧端.
public enum TransportMessage: Sendable {
    case stateUpdate(StateUpdate)
    case snapshotRequest
    case snapshot(Snapshot)
    case switchTo(SwitchTo)
    case switchResult(SwitchResult)
    case unpairNotification

    public struct StateUpdate: Codable, Sendable, Equatable {
        public let processId: String
        public let state: ProcessState
        public let timestamp: Date

        public init(processId: String, state: ProcessState, timestamp: Date) {
            self.processId = processId
            self.state = state
            self.timestamp = timestamp
        }

        enum CodingKeys: String, CodingKey {
            case processId = "process_id"
            case state
            case timestamp
        }
    }

    public struct Snapshot: Codable, Sendable, Equatable {
        public let processes: [SnapshotProcess]
        public init(processes: [SnapshotProcess]) { self.processes = processes }
    }

    public struct SnapshotProcess: Codable, Sendable, Equatable {
        public let id: String
        public let name: String
        public let state: ProcessState
        public let terminal: String?
        public let switchable: Bool
        public let startedAt: Date
        public let stateChangedAt: Date

        public init(
            id: String,
            name: String,
            state: ProcessState,
            terminal: String?,
            switchable: Bool,
            startedAt: Date,
            stateChangedAt: Date
        ) {
            self.id = id
            self.name = name
            self.state = state
            self.terminal = terminal
            self.switchable = switchable
            self.startedAt = startedAt
            self.stateChangedAt = stateChangedAt
        }

        enum CodingKeys: String, CodingKey {
            case id, name, state, terminal, switchable
            case startedAt = "started_at"
            case stateChangedAt = "state_changed_at"
        }
    }

    public struct SwitchTo: Codable, Sendable, Equatable {
        public let processId: String
        public init(processId: String) { self.processId = processId }
        enum CodingKeys: String, CodingKey { case processId = "process_id" }
    }

    public struct SwitchResult: Codable, Sendable, Equatable {
        public let processId: String
        public let success: Bool
        public let errorMessage: String?

        public init(processId: String, success: Bool, errorMessage: String? = nil) {
            self.processId = processId
            self.success = success
            self.errorMessage = errorMessage
        }

        enum CodingKeys: String, CodingKey {
            case processId = "process_id"
            case success
            case errorMessage = "error_message"
        }
    }
}

// MARK: - Codable

extension TransportMessage: Codable {
    private enum DiscriminatorKey: String, CodingKey { case type }
    private enum BodyKey: String, CodingKey {
        case processId = "process_id"
        case state, timestamp
        case processes
        case success
        case errorMessage = "error_message"
    }

    private enum Kind: String, Codable {
        case stateUpdate = "state_update"
        case snapshotRequest = "snapshot_request"
        case snapshot
        case switchTo = "switch_to"
        case switchResult = "switch_result"
        case unpairNotification = "unpair_notification"
    }

    public init(from decoder: Decoder) throws {
        let header = try decoder.container(keyedBy: DiscriminatorKey.self)
        let kind = try header.decode(Kind.self, forKey: .type)
        // 整个对象再当一个扁平结构去解 — 各 message 字段就是顶层 key
        switch kind {
        case .stateUpdate:
            self = .stateUpdate(try StateUpdate(from: decoder))
        case .snapshotRequest:
            self = .snapshotRequest
        case .snapshot:
            self = .snapshot(try Snapshot(from: decoder))
        case .switchTo:
            self = .switchTo(try SwitchTo(from: decoder))
        case .switchResult:
            self = .switchResult(try SwitchResult(from: decoder))
        case .unpairNotification:
            self = .unpairNotification
        }
    }

    public func encode(to encoder: Encoder) throws {
        var header = encoder.container(keyedBy: DiscriminatorKey.self)
        switch self {
        case .stateUpdate(let payload):
            try header.encode(Kind.stateUpdate, forKey: .type)
            try payload.encode(to: encoder)
        case .snapshotRequest:
            try header.encode(Kind.snapshotRequest, forKey: .type)
        case .snapshot(let payload):
            try header.encode(Kind.snapshot, forKey: .type)
            try payload.encode(to: encoder)
        case .switchTo(let payload):
            try header.encode(Kind.switchTo, forKey: .type)
            try payload.encode(to: encoder)
        case .switchResult(let payload):
            try header.encode(Kind.switchResult, forKey: .type)
            try payload.encode(to: encoder)
        case .unpairNotification:
            try header.encode(Kind.unpairNotification, forKey: .type)
        }
    }
}

// MARK: - JSON Helpers

public enum TransportCoding {
    /// 统一的编/解码器: timestamp 用 unix seconds (PRD 协议示例就是这个形态).
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public static func encode(_ message: TransportMessage) throws -> Data {
        try encoder.encode(message)
    }

    public static func decode(_ data: Data) throws -> TransportMessage {
        try decoder.decode(TransportMessage.self, from: data)
    }
}

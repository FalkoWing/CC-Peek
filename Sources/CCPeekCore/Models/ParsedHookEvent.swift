import Foundation

public struct ParsedHookEvent: Sendable {
    public let eventName: String
    public let sessionId: String
    public let cwd: String?
    public let message: String?
    public let notificationType: String?
    public let claudePID: Int32?
    public let pidChain: [Int32]?
    public let shellTTY: String?
    public let timestamp: Date

    public init(
        eventName: String,
        sessionId: String,
        cwd: String?,
        message: String?,
        notificationType: String? = nil,
        claudePID: Int32? = nil,
        pidChain: [Int32]? = nil,
        shellTTY: String? = nil,
        timestamp: Date
    ) {
        self.eventName = eventName
        self.sessionId = sessionId
        self.cwd = cwd
        self.message = message
        self.notificationType = notificationType
        self.claudePID = claudePID
        self.pidChain = pidChain
        self.shellTTY = shellTTY
        self.timestamp = timestamp
    }
}

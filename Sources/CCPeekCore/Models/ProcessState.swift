import Foundation

public enum ProcessState: String, Codable, Sendable, CaseIterable {
    case active
    case waitingInput = "waiting_input"
    case waitingPermission = "waiting_permission"
    case completed
    case unknown
}

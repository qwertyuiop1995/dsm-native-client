import Foundation

public enum ActivityKind: String, Codable, Sendable {
    case upload
    case download
    case delete
    case restore
}

public enum ActivityState: String, Codable, Sendable {
    case queued
    case running
    case cancelling
    case succeeded
    case failed
    case cancelled
}

public struct ActivityTask: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: ActivityKind
    public let displayName: String
    public let remotePath: String
    public var totalUnits: Int64?
    public var completedUnits: Int64
    public var bytesPerSecond: Double?
    public var estimatedSecondsRemaining: TimeInterval?
    public var state: ActivityState
    public var failureMessage: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: ActivityKind,
        displayName: String,
        remotePath: String,
        totalUnits: Int64? = nil,
        completedUnits: Int64 = 0,
        bytesPerSecond: Double? = nil,
        estimatedSecondsRemaining: TimeInterval? = nil,
        state: ActivityState = .queued,
        failureMessage: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.remotePath = remotePath
        self.totalUnits = totalUnits
        self.completedUnits = completedUnits
        self.bytesPerSecond = bytesPerSecond
        self.estimatedSecondsRemaining = estimatedSecondsRemaining
        self.state = state
        self.failureMessage = failureMessage
        self.createdAt = createdAt
    }
}

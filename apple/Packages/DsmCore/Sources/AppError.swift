import Foundation

public enum AppErrorCategory: String, Codable, Sendable {
    case networkUnavailable
    case timeout
    case tlsUntrusted
    case tlsCertificateChanged
    case authenticationRequired
    case otpRequired
    case permissionDenied
    case apiUnavailable
    case versionUnsupported
    case notFound
    case conflict
    case localStorageFull
    case remoteStorageFull
    case serverBusy
    case partialFailure
    case cancelled
    case invalidResponse
    case unknown
}

public struct AppError: Error, Equatable, Sendable {
    public let category: AppErrorCategory
    public let isRetryable: Bool
    public let safeUserMessage: String
    public let dsmCode: Int?
    public let httpStatus: Int?
    public let requestID: UUID

    public init(
        category: AppErrorCategory,
        isRetryable: Bool,
        safeUserMessage: String,
        dsmCode: Int? = nil,
        httpStatus: Int? = nil,
        requestID: UUID = UUID()
    ) {
        self.category = category
        self.isRetryable = isRetryable
        self.safeUserMessage = safeUserMessage
        self.dsmCode = dsmCode
        self.httpStatus = httpStatus
        self.requestID = requestID
    }
}

extension AppError: LocalizedError {
    public var errorDescription: String? {
        safeUserMessage
    }
}

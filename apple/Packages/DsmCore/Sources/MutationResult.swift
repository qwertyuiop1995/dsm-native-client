import Foundation

public enum MutationResultStatus: String, Codable, CaseIterable, Sendable {
    case confirmedSuccess
    case confirmedFailure
    case submittedButUnverified
    case partialSuccess
    case cancelledBeforeSubmission
    case cancellationRequestedAfterSubmission
    case permissionDenied
    case unsupported
}

public enum MutationErrorCategory: String, Codable, CaseIterable, Sendable {
    case validation
    case authentication
    case permission
    case conflict
    case network
    case server
    case unsupported
    case unknown
}

public struct MutationResultCounts: Codable, Equatable, Sendable {
    public let succeeded: Int
    public let failed: Int
    public let unknown: Int

    public init(succeeded: Int, failed: Int, unknown: Int) throws {
        guard succeeded >= 0, failed >= 0, unknown >= 0 else {
            throw MutationResultValidationError.negativeCount
        }
        self.succeeded = succeeded
        self.failed = failed
        self.unknown = unknown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            succeeded: container.decode(Int.self, forKey: .succeeded),
            failed: container.decode(Int.self, forKey: .failed),
            unknown: container.decode(Int.self, forKey: .unknown)
        )
    }
}

public enum MutationResultValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion
    case invalidOperation
    case invalidSafeTag
    case negativeCount
    case inconsistentState
}

public struct MutationResult: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let status: MutationResultStatus
    public let operation: String
    public let submitted: Bool
    public let requiresRefresh: Bool
    public let counts: MutationResultCounts
    public let errorCategory: MutationErrorCategory?
    public let localizationKey: String?
    public let diagnosticTag: String?

    public init(
        status: MutationResultStatus,
        operation: String,
        submitted: Bool,
        requiresRefresh: Bool,
        counts: MutationResultCounts,
        errorCategory: MutationErrorCategory? = nil,
        localizationKey: String? = nil,
        diagnosticTag: String? = nil
    ) throws {
        try self.init(
            schemaVersion: 1,
            status: status,
            operation: operation,
            submitted: submitted,
            requiresRefresh: requiresRefresh,
            counts: counts,
            errorCategory: errorCategory,
            localizationKey: localizationKey,
            diagnosticTag: diagnosticTag
        )
    }

    private init(
        schemaVersion: Int,
        status: MutationResultStatus,
        operation: String,
        submitted: Bool,
        requiresRefresh: Bool,
        counts: MutationResultCounts,
        errorCategory: MutationErrorCategory?,
        localizationKey: String?,
        diagnosticTag: String?
    ) throws {
        guard schemaVersion == 1 else {
            throw MutationResultValidationError.unsupportedSchemaVersion
        }
        guard Self.isValidOperation(operation) else {
            throw MutationResultValidationError.invalidOperation
        }
        guard Self.isValidSafeTag(localizationKey), Self.isValidSafeTag(diagnosticTag) else {
            throw MutationResultValidationError.invalidSafeTag
        }
        try Self.validateState(
            status: status,
            submitted: submitted,
            requiresRefresh: requiresRefresh,
            counts: counts
        )
        self.schemaVersion = schemaVersion
        self.status = status
        self.operation = operation
        self.submitted = submitted
        self.requiresRefresh = requiresRefresh
        self.counts = counts
        self.errorCategory = errorCategory
        self.localizationKey = localizationKey
        self.diagnosticTag = diagnosticTag
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            status: try container.decode(MutationResultStatus.self, forKey: .status),
            operation: try container.decode(String.self, forKey: .operation),
            submitted: try container.decode(Bool.self, forKey: .submitted),
            requiresRefresh: try container.decode(Bool.self, forKey: .requiresRefresh),
            counts: try container.decode(MutationResultCounts.self, forKey: .counts),
            errorCategory: try container.decodeIfPresent(
                MutationErrorCategory.self,
                forKey: .errorCategory
            ),
            localizationKey: try container.decodeIfPresent(String.self, forKey: .localizationKey),
            diagnosticTag: try container.decodeIfPresent(String.self, forKey: .diagnosticTag)
        )
    }

    private static func validateState(
        status: MutationResultStatus,
        submitted: Bool,
        requiresRefresh: Bool,
        counts: MutationResultCounts
    ) throws {
        switch status {
        case .confirmedSuccess:
            guard submitted, counts.failed == 0, counts.unknown == 0 else {
                throw MutationResultValidationError.inconsistentState
            }
        case .cancelledBeforeSubmission:
            guard !submitted,
                  !requiresRefresh,
                  counts.succeeded == 0,
                  counts.failed == 0,
                  counts.unknown == 0 else {
                throw MutationResultValidationError.inconsistentState
            }
        case .submittedButUnverified, .cancellationRequestedAfterSubmission:
            guard submitted, requiresRefresh else {
                throw MutationResultValidationError.inconsistentState
            }
        case .partialSuccess:
            guard submitted,
                  counts.succeeded > 0,
                  counts.failed + counts.unknown > 0 else {
                throw MutationResultValidationError.inconsistentState
            }
        case .confirmedFailure, .permissionDenied, .unsupported:
            break
        }
    }

    private static func isValidOperation(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              (UnicodeScalar("a")...UnicodeScalar("z")).contains(first) else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            (UnicodeScalar("a")...UnicodeScalar("z")).contains(scalar)
                || (UnicodeScalar("A")...UnicodeScalar("Z")).contains(scalar)
                || (UnicodeScalar("0")...UnicodeScalar("9")).contains(scalar)
        }
    }

    private static func isValidSafeTag(_ value: String?) -> Bool {
        guard let value else {
            return true
        }
        guard !value.isEmpty else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            (UnicodeScalar("a")...UnicodeScalar("z")).contains(scalar)
                || (UnicodeScalar("0")...UnicodeScalar("9")).contains(scalar)
                || scalar == "."
                || scalar == "_"
                || scalar == "-"
        }
    }
}

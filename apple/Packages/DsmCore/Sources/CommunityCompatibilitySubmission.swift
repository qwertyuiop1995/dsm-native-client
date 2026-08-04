import Foundation

public struct CommunityCompatibilitySubmission: Codable, Equatable, Sendable {
    public static let schemaIdentifier =
        "community-compatibility-submission.schema.json"

    public struct App: Codable, Equatable, Sendable {
        public let version: String
        public let commit: String
        public let platform: Platform
        public let platformVersion: String

        public init(
            version: String,
            commit: String,
            platform: Platform,
            platformVersion: String
        ) {
            self.version = version
            self.commit = commit
            self.platform = platform
            self.platformVersion = platformVersion
        }
    }

    public enum Platform: String, Codable, Equatable, Sendable {
        case macOS
        case iPhone
        case iPad
        case android = "Android"
        case windows = "Windows"
    }

    public struct NAS: Codable, Equatable, Sendable {
        public let model: String
        public let architecture: Architecture

        public init(model: String, architecture: Architecture) {
            self.model = model
            self.architecture = architecture
        }
    }

    public enum Architecture: String, Codable, Equatable, Sendable {
        case x86_64
        case aarch64
        case armv7
        case unknown
    }

    public struct DSM: Codable, Equatable, Sendable {
        public let version: String
        public let build: String
        public let update: String

        public init(version: String, build: String, update: String) {
            self.version = version
            self.build = build
            self.update = update
        }
    }

    public struct Package: Codable, Equatable, Sendable {
        public let id: String
        public let version: String

        public init(id: String, version: String) {
            self.id = id
            self.version = version
        }
    }

    public enum ConnectionType: String, Codable, Equatable, Sendable {
        case lan
        case quickConnectDirect = "quickconnect-direct"
        case quickConnectRelay = "quickconnect-relay"
        case reverseProxy = "reverse-proxy"
        case unknown
    }

    public enum AccountRole: String, Codable, Equatable, Sendable {
        case standard
        case administrator
        case unknown
    }

    public enum CertificateType: String, Codable, Equatable, Sendable {
        case publicCA = "public-ca"
        case privateCA = "private-ca"
        case selfSigned = "self-signed"
        case unknown
    }

    public enum TestSuiteVersion: Int, Codable, Equatable, Sendable {
        case version1 = 1
        case version2 = 2
    }

    public struct Result: Codable, Equatable, Sendable {
        public let capabilityId: String
        public let status: Status
        public let failure: Failure?

        public init(
            capabilityId: String,
            status: Status,
            failure: Failure? = nil
        ) {
            self.capabilityId = capabilityId
            self.status = status
            self.failure = failure
        }
    }

    public enum Status: String, Codable, Equatable, Sendable {
        case passed
        case failed
        case partial
        case skipped
        case notSupported = "not-supported"
    }

    public struct Failure: Codable, Equatable, Sendable {
        public let stage: FailureStage
        public let errorCategory: ErrorCategory
        public let apiName: String
        public let apiVersion: APIVersion
        public let httpStatus: Int?
        public let retryPerformed: Bool
        public let rawResponseIncluded: Bool

        public init(
            stage: FailureStage,
            errorCategory: ErrorCategory,
            apiName: String,
            apiVersion: APIVersion,
            httpStatus: Int?,
            retryPerformed: Bool,
            rawResponseIncluded: Bool = false
        ) {
            self.stage = stage
            self.errorCategory = errorCategory
            self.apiName = apiName
            self.apiVersion = apiVersion
            self.httpStatus = httpStatus
            self.retryPerformed = retryPerformed
            self.rawResponseIncluded = rawResponseIncluded
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stage = try container.decode(FailureStage.self, forKey: .stage)
            errorCategory = try container.decode(
                ErrorCategory.self,
                forKey: .errorCategory
            )
            apiName = try container.decode(String.self, forKey: .apiName)
            apiVersion = try container.decode(APIVersion.self, forKey: .apiVersion)
            httpStatus = try container.decodeIfPresent(Int.self, forKey: .httpStatus)
            retryPerformed = try container.decode(Bool.self, forKey: .retryPerformed)
            rawResponseIncluded = try container.decode(
                Bool.self,
                forKey: .rawResponseIncluded
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(stage, forKey: .stage)
            try container.encode(errorCategory, forKey: .errorCategory)
            try container.encode(apiName, forKey: .apiName)
            try container.encode(apiVersion, forKey: .apiVersion)
            if let httpStatus {
                try container.encode(httpStatus, forKey: .httpStatus)
            } else {
                try container.encodeNil(forKey: .httpStatus)
            }
            try container.encode(retryPerformed, forKey: .retryPerformed)
            try container.encode(
                rawResponseIncluded,
                forKey: .rawResponseIncluded
            )
        }

        private enum CodingKeys: String, CodingKey {
            case stage
            case errorCategory
            case apiName
            case apiVersion
            case httpStatus
            case retryPerformed
            case rawResponseIncluded
        }
    }

    public enum FailureStage: String, Codable, Equatable, Sendable {
        case setup
        case discovery
        case authentication
        case request
        case submission
        case readback
        case finalState = "final-state"
        case cleanup
        case unknown
    }

    public enum ErrorCategory: String, Codable, Equatable, Sendable {
        case permissionDenied = "permission-denied"
        case operationFailed = "operation-failed"
        case connectionFailed = "connection-failed"
        case unexpectedResult = "unexpected-result"
        case appCrashed = "app-crashed"
        case unknown
    }

    public enum APIVersion: Codable, Equatable, Sendable {
        case version(Int)
        case unknown

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Int.self) {
                self = .version(value)
            } else if try container.decode(String.self) == "unknown" {
                self = .unknown
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "API version must be an integer or unknown"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .version(let value):
                try container.encode(value)
            case .unknown:
                try container.encode("unknown")
            }
        }
    }

    public let schema: String
    public let submissionSchemaVersion: Int
    public let reportSchemaVersion: Int
    public let generatedAt: Date
    public let app: App
    public let nas: NAS
    public let dsm: DSM
    public let packages: [Package]
    public let connectionType: ConnectionType
    public let accountRole: AccountRole
    public let certificateType: CertificateType
    public let testSuiteVersion: TestSuiteVersion
    public let results: [Result]
    public let privacyAttestation: Bool

    public init(
        schema: String = CommunityCompatibilitySubmission.schemaIdentifier,
        submissionSchemaVersion: Int = 1,
        reportSchemaVersion: Int = 2,
        generatedAt: Date,
        app: App,
        nas: NAS,
        dsm: DSM,
        packages: [Package],
        connectionType: ConnectionType,
        accountRole: AccountRole,
        certificateType: CertificateType,
        testSuiteVersion: TestSuiteVersion,
        results: [Result],
        privacyAttestation: Bool
    ) {
        self.schema = schema
        self.submissionSchemaVersion = submissionSchemaVersion
        self.reportSchemaVersion = reportSchemaVersion
        self.generatedAt = generatedAt
        self.app = app
        self.nas = nas
        self.dsm = dsm
        self.packages = packages
        self.connectionType = connectionType
        self.accountRole = accountRole
        self.certificateType = certificateType
        self.testSuiteVersion = testSuiteVersion
        self.results = results
        self.privacyAttestation = privacyAttestation
    }

    private enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case submissionSchemaVersion
        case reportSchemaVersion
        case generatedAt
        case app
        case nas
        case dsm
        case packages
        case connectionType
        case accountRole
        case certificateType
        case testSuiteVersion
        case results
        case privacyAttestation
    }
}

public enum CommunityCompatibilitySubmissionValidationError:
    Error, Equatable, Sendable {
    case invalidField(String)
    case missingCapabilities([String])
    case unexpectedCapabilities([String])
    case duplicateCapability(String)
    case invalidFailure(String)
    case privacyAttestationRequired
    case sensitiveValue(String)
}

public enum CommunityCompatibilitySubmissionValidator {
    public static let version1CapabilityIDs = [
        "connection.resolve",
        "authentication.password",
        "authentication.otp",
        "authentication.restore-session",
        "files.list-shares",
        "files.browse",
        "files.search",
        "files.download",
        "files.upload",
        "files.create-folder",
        "files.rename",
        "files.copy-move",
        "files.recycle",
        "files.restore",
    ]

    public static let version2CapabilityIDs = version1CapabilityIDs + [
        "desktop-drive.mount",
        "desktop-drive.browse",
        "desktop-drive.download-resume",
        "desktop-drive.keep-offline",
        "desktop-drive.upgrade-restore",
    ]

    public static func validate(
        _ submission: CommunityCompatibilitySubmission
    ) throws {
        guard submission.schema
            == CommunityCompatibilitySubmission.schemaIdentifier else {
            throw CommunityCompatibilitySubmissionValidationError.invalidField(
                "$schema"
            )
        }
        guard submission.submissionSchemaVersion == 1 else {
            throw CommunityCompatibilitySubmissionValidationError.invalidField(
                "submissionSchemaVersion"
            )
        }
        guard submission.reportSchemaVersion == 2 else {
            throw CommunityCompatibilitySubmissionValidationError.invalidField(
                "reportSchemaVersion"
            )
        }
        guard submission.privacyAttestation else {
            throw CommunityCompatibilitySubmissionValidationError
                .privacyAttestationRequired
        }
        try validateApp(submission.app)
        try validateNAS(submission.nas)
        try validateDSM(submission.dsm)
        try validatePackages(submission.packages)
        try validateResults(
            submission.results,
            testSuiteVersion: submission.testSuiteVersion,
            platform: submission.app.platform
        )
        try validatePrivacy(submission)
    }

    private static func validateApp(
        _ app: CommunityCompatibilitySubmission.App
    ) throws {
        try requireLength(app.version, field: "app.version", maximum: 40)
        try requirePattern(
            app.commit,
            field: "app.commit",
            pattern: "^(?:[0-9a-fA-F]{7,40}|unknown)$"
        )
        try requireLength(
            app.platformVersion,
            field: "app.platformVersion",
            maximum: 40
        )
    }

    private static func validateNAS(
        _ nas: CommunityCompatibilitySubmission.NAS
    ) throws {
        try requirePattern(
            nas.model,
            field: "nas.model",
            pattern: "^[A-Za-z0-9][A-Za-z0-9+._-]{1,39}$"
        )
    }

    private static func validateDSM(
        _ dsm: CommunityCompatibilitySubmission.DSM
    ) throws {
        try requirePattern(
            dsm.version,
            field: "dsm.version",
            pattern: "^[0-9]+(?:\\.[0-9]+){1,3}$"
        )
        try requirePattern(
            dsm.build,
            field: "dsm.build",
            pattern: "^[0-9]{4,8}$"
        )
        try requirePattern(
            dsm.update,
            field: "dsm.update",
            pattern: "^(?:[0-9]{1,3}|none|unknown)$"
        )
    }

    private static func validatePackages(
        _ packages: [CommunityCompatibilitySubmission.Package]
    ) throws {
        var identifiers = Set<String>()
        for package in packages {
            try requirePattern(
                package.id,
                field: "packages.id",
                pattern: "^[a-z0-9]+(?:-[a-z0-9]+)*$"
            )
            try requireLength(
                package.version,
                field: "packages.version",
                maximum: 60
            )
            guard identifiers.insert(package.id).inserted else {
                throw CommunityCompatibilitySubmissionValidationError
                    .invalidField("packages.id")
            }
        }
    }

    private static func validateResults(
        _ results: [CommunityCompatibilitySubmission.Result],
        testSuiteVersion: CommunityCompatibilitySubmission.TestSuiteVersion,
        platform: CommunityCompatibilitySubmission.Platform
    ) throws {
        let expected = testSuiteVersion == .version1
            ? version1CapabilityIDs
            : version2CapabilityIDs
        var identifiers = Set<String>()
        for result in results {
            guard identifiers.insert(result.capabilityId).inserted else {
                throw CommunityCompatibilitySubmissionValidationError
                    .duplicateCapability(result.capabilityId)
            }
            let requiresFailure = result.status == .failed
                || result.status == .partial
            guard requiresFailure == (result.failure != nil) else {
                throw CommunityCompatibilitySubmissionValidationError
                    .invalidFailure(result.capabilityId)
            }
            if let failure = result.failure {
                try validateFailure(failure, capabilityID: result.capabilityId)
            }
        }
        let expectedSet = Set(expected)
        let missing = expectedSet.subtracting(identifiers).sorted()
        guard missing.isEmpty else {
            throw CommunityCompatibilitySubmissionValidationError
                .missingCapabilities(missing)
        }
        let unexpected = identifiers.subtracting(expectedSet).sorted()
        guard unexpected.isEmpty else {
            throw CommunityCompatibilitySubmissionValidationError
                .unexpectedCapabilities(unexpected)
        }
        if platform != .macOS, testSuiteVersion == .version2 {
            let invalid = results.contains {
                $0.capabilityId.hasPrefix("desktop-drive.")
                    && $0.status != .notSupported
            }
            guard !invalid else {
                throw CommunityCompatibilitySubmissionValidationError
                    .invalidField("results.desktop-drive.status")
            }
        }
    }

    private static func validateFailure(
        _ failure: CommunityCompatibilitySubmission.Failure,
        capabilityID: String
    ) throws {
        try requirePattern(
            failure.apiName,
            field: "results.failure.apiName",
            pattern: "^(?:SYNO(?:\\.[A-Za-z0-9_]+)+|unknown)$"
        )
        switch failure.apiVersion {
        case .version(let value) where !(1...99).contains(value):
            throw CommunityCompatibilitySubmissionValidationError
                .invalidFailure(capabilityID)
        case .version, .unknown:
            break
        }
        if let status = failure.httpStatus, !(100...599).contains(status) {
            throw CommunityCompatibilitySubmissionValidationError
                .invalidFailure(capabilityID)
        }
        guard !failure.rawResponseIncluded else {
            throw CommunityCompatibilitySubmissionValidationError
                .invalidFailure(capabilityID)
        }
    }

    private static func requireLength(
        _ value: String,
        field: String,
        maximum: Int
    ) throws {
        guard !value.isEmpty, value.count <= maximum else {
            throw CommunityCompatibilitySubmissionValidationError
                .invalidField(field)
        }
    }

    private static func requirePattern(
        _ value: String,
        field: String,
        pattern: String
    ) throws {
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            throw CommunityCompatibilitySubmissionValidationError
                .invalidField(field)
        }
    }

    private static func rejectSensitive(
        _ value: String,
        field: String
    ) throws {
        let patterns = [
            "https?://",
            "(?<![0-9])(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})(?:\\.(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})){3}(?![0-9])",
            "\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b",
            "(?:/volume[0-9]+/|/homes?/|\\\\\\\\[^\\s]+\\\\)",
            "\\b[A-Z]:\\\\(?:[^\\\\\\r\\n]+\\\\)*",
            "(?:synotoken|cookie|session[_-]?id|sid|did|token)\\s*[:=]",
        ]
        guard !patterns.contains(where: {
            value.range(
                of: $0,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }) else {
            throw CommunityCompatibilitySubmissionValidationError
                .sensitiveValue(field)
        }
    }

    private static func validatePrivacy(
        _ submission: CommunityCompatibilitySubmission
    ) throws {
        let values: [(String, String)] = [
            ("$schema", submission.schema),
            ("app.version", submission.app.version),
            ("app.commit", submission.app.commit),
            ("app.platformVersion", submission.app.platformVersion),
            ("nas.model", submission.nas.model),
            ("dsm.version", submission.dsm.version),
            ("dsm.build", submission.dsm.build),
            ("dsm.update", submission.dsm.update),
        ] + submission.packages.flatMap {
            [("packages.id", $0.id), ("packages.version", $0.version)]
        } + submission.results.flatMap { result in
            var resultValues = [("results.capabilityId", result.capabilityId)]
            if let failure = result.failure {
                resultValues.append(("results.failure.apiName", failure.apiName))
            }
            return resultValues
        }
        for (field, value) in values {
            try rejectSensitive(value, field: field)
        }
    }
}

public enum CommunityCompatibilitySubmissionExporter {
    public static func makeData(
        _ submission: CommunityCompatibilitySubmission
    ) throws -> Data {
        try CommunityCompatibilitySubmissionValidator.validate(submission)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        var data = try encoder.encode(submission)
        data.append(0x0A)
        return data
    }
}

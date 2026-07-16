import Foundation

public enum DsmRequestFormat: String, Codable, Sendable {
    case form = "FORM"
    case json = "JSON"
}

public enum CapabilitySelectionError: Error, Equatable, Sendable {
    case unsupported(apiName: String)
}

public struct ApiCapability: Codable, Equatable, Sendable {
    public let name: String
    public let path: String
    public let minVersion: Int
    public let maxVersion: Int
    public let requestFormat: DsmRequestFormat
    public let selectedVersion: Int?
    public let verified: Bool

    public init(
        name: String,
        path: String,
        minVersion: Int,
        maxVersion: Int,
        requestFormat: DsmRequestFormat,
        selectedVersion: Int? = nil,
        verified: Bool = false
    ) {
        self.name = name
        self.path = path
        self.minVersion = minVersion
        self.maxVersion = maxVersion
        self.requestFormat = requestFormat
        self.selectedVersion = selectedVersion
        self.verified = verified
    }

    public func selectingVersion(in supportedRange: ClosedRange<Int>) throws -> ApiCapability {
        let lower = max(minVersion, supportedRange.lowerBound)
        let upper = min(maxVersion, supportedRange.upperBound)
        guard lower <= upper else {
            throw CapabilitySelectionError.unsupported(apiName: name)
        }

        return ApiCapability(
            name: name,
            path: path,
            minVersion: minVersion,
            maxVersion: maxVersion,
            requestFormat: requestFormat,
            selectedVersion: upper,
            verified: verified
        )
    }
}

public struct CapabilitySet: Equatable, Sendable {
    private let values: [String: ApiCapability]

    public init(_ values: [String: ApiCapability]) {
        self.values = values
    }

    public var count: Int {
        values.count
    }

    public subscript(apiName: String) -> ApiCapability? {
        values[apiName]
    }

    public var all: [ApiCapability] {
        values.values.sorted { $0.name < $1.name }
    }
}

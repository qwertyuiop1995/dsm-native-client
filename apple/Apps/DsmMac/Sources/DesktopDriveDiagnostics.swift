import DsmCore
import Foundation

struct DesktopDriveDiagnosticSummary: Codable, Equatable {
    struct App: Codable, Equatable {
        let version: String
        let build: String
    }

    struct System: Codable, Equatable {
        let platform: String
        let version: String
        let architecture: String
    }

    struct Drive: Codable, Equatable {
        let providerAvailable: Bool
        let mappingCount: Int
        let stateCounts: [String: Int]
        let manuallyPausedCount: Int
        let activeOfflineOperationCount: Int
        let cacheLocationCounts: [String: Int]
        let temporaryCacheItemCount: Int
        let temporaryCacheBytes: Int64
        let keptOfflineItemCount: Int
        let keptOfflineBytes: Int64
    }

    let schemaVersion: Int
    let generatedAt: Date
    let app: App
    let system: System
    let desktopDrive: Drive
}

enum DesktopDriveDiagnosticExporter {
    static func makeData(
        isProviderAvailable: Bool,
        mappings: [DesktopDriveMapping],
        runtimes: [UUID: DesktopDriveMappingRuntime],
        activeOfflineOperationCount: Int,
        generatedAt: Date = Date(),
        appVersion: String? = nil,
        appBuild: String? = nil,
        systemVersion: String? = nil,
        architecture: String? = nil
    ) throws -> Data {
        var stateCounts: [String: Int] = [:]
        var cacheLocationCounts: [String: Int] = [:]
        var manuallyPausedCount = 0
        var temporaryItemCount = 0
        var temporaryBytes: Int64 = 0
        var keptOfflineItemCount = 0
        var keptOfflineBytes: Int64 = 0

        for mapping in mappings {
            let state = runtimes[mapping.id]?.state ?? .preparing
            stateCounts[state.rawValue, default: 0] += 1
            switch mapping.cachePolicy.location {
            case .systemDefault:
                cacheLocationCounts["systemDefault", default: 0] += 1
            case .eligibleVolume:
                cacheLocationCounts["eligibleVolume", default: 0] += 1
            }
            guard let runtime = runtimes[mapping.id] else { continue }
            if runtime.isManuallyPaused {
                manuallyPausedCount += 1
            }
            for entry in runtime.cacheEntries.values {
                switch entry.kind {
                case .temporary:
                    temporaryItemCount += 1
                    temporaryBytes = addingWithoutOverflow(
                        temporaryBytes,
                        entry.allocatedSizeBytes
                    )
                case .keptOffline:
                    keptOfflineItemCount += 1
                    keptOfflineBytes = addingWithoutOverflow(
                        keptOfflineBytes,
                        entry.allocatedSizeBytes
                    )
                }
            }
        }

        let info = Bundle.main.infoDictionary ?? [:]
        let summary = DesktopDriveDiagnosticSummary(
            schemaVersion: 1,
            generatedAt: generatedAt,
            app: .init(
                version: appVersion
                    ?? info["CFBundleShortVersionString"] as? String
                    ?? "unknown",
                build: appBuild
                    ?? info["CFBundleVersion"] as? String
                    ?? "unknown"
            ),
            system: .init(
                platform: "macOS",
                version: systemVersion
                    ?? ProcessInfo.processInfo.operatingSystemVersionString,
                architecture: architecture ?? hostArchitecture
            ),
            desktopDrive: .init(
                providerAvailable: isProviderAvailable,
                mappingCount: mappings.count,
                stateCounts: stateCounts,
                manuallyPausedCount: manuallyPausedCount,
                activeOfflineOperationCount: activeOfflineOperationCount,
                cacheLocationCounts: cacheLocationCounts,
                temporaryCacheItemCount: temporaryItemCount,
                temporaryCacheBytes: temporaryBytes,
                keptOfflineItemCount: keptOfflineItemCount,
                keptOfflineBytes: keptOfflineBytes
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(summary)
        data.append(0x0A)
        return data
    }

    private static var hostArchitecture: String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "unknown"
#endif
    }

    private static func addingWithoutOverflow(
        _ left: Int64,
        _ right: Int64
    ) -> Int64 {
        let result = left.addingReportingOverflow(max(right, 0))
        return result.overflow ? .max : result.partialValue
    }
}

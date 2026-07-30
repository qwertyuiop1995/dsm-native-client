import CryptoKit
import Foundation

public struct DesktopDriveMetadataCacheSnapshot: Equatable, Sendable {
    public let itemCount: Int
    public let pageCount: Int
    public let cacheHits: Int
    public let cacheMisses: Int
    public let coalescedRequests: Int

    public init(
        itemCount: Int,
        pageCount: Int,
        cacheHits: Int,
        cacheMisses: Int,
        coalescedRequests: Int
    ) {
        self.itemCount = itemCount
        self.pageCount = pageCount
        self.cacheHits = cacheHits
        self.cacheMisses = cacheMisses
        self.coalescedRequests = coalescedRequests
    }
}

public actor DesktopDriveMetadataCoordinator {
    public struct PageKey: Hashable, Sendable {
        public let containerIdentifier: String
        public let offset: Int
        public let limit: Int

        public init(
            containerIdentifier: String,
            offset: Int,
            limit: Int
        ) {
            self.containerIdentifier = containerIdentifier
            self.offset = offset
            self.limit = limit
        }
    }

    private struct ItemEntry: Sendable {
        let value: FileItem?
        let storedAt: Date
    }

    private struct PageEntry: Sendable {
        let value: FilePage
        let storedAt: Date
    }

    private var items: [String: ItemEntry] = [:]
    private var pages: [PageKey: PageEntry] = [:]
    private var itemRequests: [String: Task<FileItem?, Error>] = [:]
    private var pageRequests: [PageKey: Task<FilePage, Error>] = [:]
    private var cacheHits = 0
    private var cacheMisses = 0
    private var coalescedRequests = 0

    public init() {}

    public func item(
        path: String,
        now: Date = Date(),
        ttl: TimeInterval = 5,
        staleIfErrorTTL: TimeInterval = 60,
        loader: @escaping @Sendable () async throws -> FileItem?
    ) async throws -> FileItem? {
        if let entry = items[path],
           now.timeIntervalSince(entry.storedAt) <= max(ttl, 0) {
            cacheHits += 1
            return entry.value
        }
        if let request = itemRequests[path] {
            coalescedRequests += 1
            return try await request.value
        }
        cacheMisses += 1
        let request = Task {
            try await loader()
        }
        itemRequests[path] = request
        do {
            let value = try await request.value
            itemRequests[path] = nil
            items[path] = ItemEntry(value: value, storedAt: now)
            return value
        } catch {
            itemRequests[path] = nil
            if let entry = items[path],
               now.timeIntervalSince(entry.storedAt) <= max(staleIfErrorTTL, 0) {
                return entry.value
            }
            throw error
        }
    }

    public func page(
        key: PageKey,
        now: Date = Date(),
        ttl: TimeInterval = 3,
        staleIfErrorTTL: TimeInterval = 30,
        loader: @escaping @Sendable () async throws -> FilePage
    ) async throws -> FilePage {
        if let entry = pages[key],
           now.timeIntervalSince(entry.storedAt) <= max(ttl, 0) {
            cacheHits += 1
            return entry.value
        }
        if let request = pageRequests[key] {
            coalescedRequests += 1
            return try await request.value
        }
        cacheMisses += 1
        let request = Task {
            try await loader()
        }
        pageRequests[key] = request
        do {
            let value = try await request.value
            pageRequests[key] = nil
            pages[key] = PageEntry(value: value, storedAt: now)
            remember(value.items, now: now)
            return value
        } catch {
            pageRequests[key] = nil
            if let entry = pages[key],
               now.timeIntervalSince(entry.storedAt) <= max(staleIfErrorTTL, 0) {
                return entry.value
            }
            throw error
        }
    }

    public func remember(_ values: [FileItem], now: Date = Date()) {
        for value in values {
            items[value.path] = ItemEntry(value: value, storedAt: now)
        }
    }

    public func invalidate(
        paths: [String]? = nil,
        cancelInFlight: Bool = false
    ) {
        if let paths {
            let normalized = Set(paths.compactMap(DesktopDrivePath.normalized))
            items = items.filter { path, _ in
                !normalized.contains {
                    DesktopDrivePath.isAncestorOrSame($0, of: path)
                        || DesktopDrivePath.isAncestorOrSame(path, of: $0)
                }
            }
            pages.removeAll()
        } else {
            items.removeAll()
            pages.removeAll()
        }
        guard cancelInFlight else { return }
        itemRequests.values.forEach { $0.cancel() }
        pageRequests.values.forEach { $0.cancel() }
        itemRequests.removeAll()
        pageRequests.removeAll()
    }

    public func snapshot() -> DesktopDriveMetadataCacheSnapshot {
        DesktopDriveMetadataCacheSnapshot(
            itemCount: items.count,
            pageCount: pages.count,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            coalescedRequests: coalescedRequests
        )
    }
}

public struct DesktopDriveItemVersionValue: Equatable, Sendable {
    public let content: Data
    public let metadata: Data

    public init(content: Data, metadata: Data) {
        self.content = content
        self.metadata = metadata
    }
}

public enum DesktopDriveItemVersionStrategy {
    public static func make(
        path: String,
        sizeBytes: Int64?,
        modifiedAt: Date?,
        stableFileID: String? = nil,
        revision: String? = nil
    ) -> DesktopDriveItemVersionValue {
        let normalizedPath = DesktopDrivePath.normalized(path) ?? path
        let contentBasis = [
            stableFileID ?? "",
            revision ?? "",
            String(sizeBytes ?? -1),
            String(modifiedAt?.timeIntervalSince1970 ?? 0),
        ].joined(separator: "\u{0}")
        let metadataBasis = [
            normalizedPath,
            contentBasis,
        ].joined(separator: "\u{0}")
        return DesktopDriveItemVersionValue(
            content: digest(contentBasis),
            metadata: digest(metadataBasis)
        )
    }

    private static func digest(_ value: String) -> Data {
        Data(SHA256.hash(data: Data(value.utf8)))
    }
}

import XCTest
@testable import DsmCore

final class DesktopCloudDriveMetadataTests: XCTestCase {
    func test并发相同元数据请求只执行一次() async throws {
        let coordinator = DesktopDriveMetadataCoordinator()
        let loader = MetadataLoader()

        async let first = coordinator.item(path: "/share/item.bin") {
            try await loader.load()
        }
        async let second = coordinator.item(path: "/share/item.bin") {
            try await loader.load()
        }

        let values = try await [first, second]
        XCTAssertEqual(values.compactMap(\.self).count, 2)
        let loadCount = await loader.count
        XCTAssertEqual(loadCount, 1)
        let snapshot = await coordinator.snapshot()
        XCTAssertEqual(snapshot.coalescedRequests, 1)
    }

    func test短期缓存命中且过期失败时返回最近数据() async throws {
        let coordinator = DesktopDriveMetadataCoordinator()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let item = Self.file(path: "/share/item.bin", size: 10)

        _ = try await coordinator.item(path: item.path, now: base) {
            item
        }
        let cached = try await coordinator.item(
            path: item.path,
            now: base.addingTimeInterval(2)
        ) {
            XCTFail("TTL 内不应再次读取")
            return nil
        }
        let stale = try await coordinator.item(
            path: item.path,
            now: base.addingTimeInterval(10)
        ) {
            throw URLError(.networkConnectionLost)
        }

        XCTAssertEqual(cached, item)
        XCTAssertEqual(stale, item)
        let snapshot = await coordinator.snapshot()
        XCTAssertEqual(snapshot.cacheHits, 1)
        XCTAssertEqual(snapshot.cacheMisses, 2)
    }

    func test失效会清除祖先后代路径和分页() async throws {
        let coordinator = DesktopDriveMetadataCoordinator()
        let page = FilePage(
            folderPath: "/share",
            items: [
                Self.file(path: "/share/a.bin", size: 1),
                Self.file(path: "/share/sub/b.bin", size: 2),
            ],
            offset: 0,
            total: 2,
            hasMore: false
        )
        let key = DesktopDriveMetadataCoordinator.PageKey(
            containerIdentifier: "root",
            offset: 0,
            limit: 500
        )
        _ = try await coordinator.page(key: key) { page }

        await coordinator.invalidate(paths: ["/share/sub"])

        let snapshot = await coordinator.snapshot()
        XCTAssertEqual(snapshot.itemCount, 1)
        XCTAssertEqual(snapshot.pageCount, 0)
    }

    func test版本策略不暴露路径并区分内容与元数据变化() {
        let base = DesktopDriveItemVersionStrategy.make(
            path: "/share/财务/预算.xlsx",
            sizeBytes: 10,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let renamed = DesktopDriveItemVersionStrategy.make(
            path: "/share/财务/新预算.xlsx",
            sizeBytes: 10,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let changed = DesktopDriveItemVersionStrategy.make(
            path: "/share/财务/预算.xlsx",
            sizeBytes: 11,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(base.content, renamed.content)
        XCTAssertNotEqual(base.metadata, renamed.metadata)
        XCTAssertNotEqual(base.content, changed.content)
        XCTAssertEqual(base.content.count, 32)
        XCTAssertFalse(String(data: base.metadata, encoding: .utf8)?.contains("财务") == true)
    }

    private static func file(path: String, size: Int64) -> FileItem {
        FileItem(
            profileID: Self.profileID,
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            kind: .file,
            sizeBytes: size
        )
    }

    private static let profileID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000"
    )!
}

private actor MetadataLoader {
    private(set) var count = 0

    func load() async throws -> FileItem {
        count += 1
        try await Task.sleep(for: .milliseconds(20))
        return FileItem(
            profileID: UUID(
                uuidString: "00000000-0000-0000-0000-000000000000"
            )!,
            name: "item.bin",
            path: "/share/item.bin",
            kind: .file,
            sizeBytes: 10
        )
    }
}

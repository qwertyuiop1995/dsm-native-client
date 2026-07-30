import XCTest
@testable import DsmCore

final class DesktopCloudDriveTests: XCTestCase {
    private let gibibyte: Int64 = 1_024 * 1_024 * 1_024

    func test同一NAS的父子目录映射会被识别为重叠() {
        let profileID = UUID()
        let parent = DesktopDriveMapping(
            profileID: profileID,
            displayName: "Parent",
            scope: .folder(path: "/share/projects")
        )
        let child = DesktopDriveMapping(
            profileID: profileID,
            displayName: "Child",
            scope: .folder(path: "//share/projects/design/")
        )

        XCTAssertTrue(parent.overlaps(child))
    }

    func test不同NAS或相邻目录映射不重叠() {
        let first = DesktopDriveMapping(
            profileID: UUID(),
            displayName: "First",
            scope: .folder(path: "/share/project")
        )
        let differentProfile = DesktopDriveMapping(
            profileID: UUID(),
            displayName: "Second",
            scope: .folder(path: "/share/project")
        )
        let sibling = DesktopDriveMapping(
            profileID: first.profileID,
            displayName: "Sibling",
            scope: .folder(path: "/share/project-archive")
        )

        XCTAssertFalse(first.overlaps(differentProfile))
        XCTAssertFalse(first.overlaps(sibling))
    }

    func test全部共享文件夹与同一NAS的任意目录重叠() {
        let profileID = UUID()
        let allShares = DesktopDriveMapping(
            profileID: profileID,
            displayName: "All",
            scope: .allShares
        )
        let folder = DesktopDriveMapping(
            profileID: profileID,
            displayName: "Folder",
            scope: .folder(path: "/share/folder")
        )

        XCTAssertTrue(allShares.overlaps(folder))
    }

    func test空间决策只计算尚未缓存的字节并包含峰值与安全余量() {
        let decision = DesktopDriveCacheSpaceCalculator.evaluate(
            candidates: [
                .init(sizeBytes: 8 * gibibyte, locallyAvailableBytes: 3 * gibibyte),
                .init(sizeBytes: 2 * gibibyte, locallyAvailableBytes: 2 * gibibyte),
            ],
            volumeCapacityBytes: 100 * gibibyte,
            availableCapacityBytes: 20 * gibibyte
        )

        XCTAssertEqual(
            decision,
            .allowed(requiredBytes: 15 * gibibyte, availableBytes: 20 * gibibyte)
        )
    }

    func test空间不足返回明确差额() {
        let decision = DesktopDriveCacheSpaceCalculator.evaluate(
            candidates: [.init(sizeBytes: 8 * gibibyte)],
            volumeCapacityBytes: 100 * gibibyte,
            availableCapacityBytes: 10 * gibibyte
        )

        XCTAssertEqual(
            decision,
            .insufficient(
                requiredBytes: 21 * gibibyte,
                availableBytes: 10 * gibibyte,
                shortageBytes: 11 * gibibyte
            )
        )
    }

    func test未知文件大小时拒绝缓存决策() {
        XCTAssertEqual(
            DesktopDriveCacheSpaceCalculator.evaluate(
                candidates: [.init(sizeBytes: nil)],
                volumeCapacityBytes: 100 * gibibyte,
                availableCapacityBytes: 50 * gibibyte
            ),
            .unknownSize
        )
    }

    func test暂停状态只能检查移除或失败() {
        XCTAssertTrue(DesktopDriveMappingState.paused.canTransition(to: .checking))
        XCTAssertTrue(DesktopDriveMappingState.paused.canTransition(to: .removing))
        XCTAssertFalse(DesktopDriveMappingState.paused.canTransition(to: .available))
        XCTAssertFalse(DesktopDriveMappingState.paused.canTransition(to: .offline))
    }

    func test共享配置按连接保存并可恢复映射() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let store = DesktopDriveConfigurationStore(directoryURL: directoryURL)
        let profile = try NasProfile(
            displayName: "NAS",
            host: "nas.example.test",
            port: 5001
        )
        let capability = ApiCapability(
            name: "SYNO.FileStation.List",
            path: "entry.cgi",
            minVersion: 1,
            maxVersion: 2,
            requestFormat: .form,
            selectedVersion: 2,
            verified: true
        )
        let mapping = DesktopDriveMapping(
            profileID: profile.id,
            displayName: "Projects",
            scope: .folder(path: "/share/projects")
        )

        try await store.saveConnection(
            profile: profile,
            capabilities: CapabilitySet([capability.name: capability])
        )
        try await store.saveMapping(mapping)

        let restored = try await store.configuration(mappingID: mapping.id)
        XCTAssertEqual(restored?.mapping, mapping)
        XCTAssertEqual(restored?.connection.profile, profile)
        XCTAssertEqual(restored?.connection.capabilitySet[capability.name], capability)
    }

    func test损坏配置读取失败时不会覆盖原始文件() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let fileURL = directoryURL.appendingPathComponent(
            "desktop-drive-config-v1.json"
        )
        let originalData = Data(
            #"{"version":2,"connections":{},"mappings":"damaged"}"#.utf8
        )
        try originalData.write(to: fileURL)
        let store = DesktopDriveConfigurationStore(
            directoryURL: directoryURL
        )

        do {
            _ = try await store.mappings()
            XCTFail("损坏配置不应被当作空配置读取。")
        } catch {}

        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
    }

    func test目录缓存规划递归分页并汇总可信大小() async {
        let rootItems = [
            Self.file(path: "/share/root.txt", size: 3),
            Self.folder(path: "/share/sub"),
        ]
        let subItems = [
            Self.file(path: "/share/sub/a.bin", size: 5),
            Self.file(path: "/share/sub/b.bin", size: 7),
        ]

        let plan = await DesktopDriveTreePlanner.build(
            rootFolders: ["/share"],
            pageSize: 1
        ) { path, offset, limit in
            let source = path == "/share" ? rootItems : subItems
            let items = Array(source.dropFirst(offset).prefix(limit))
            return FilePage(
                folderPath: path,
                items: items,
                offset: offset,
                total: source.count,
                hasMore: offset + items.count < source.count
            )
        }

        XCTAssertTrue(plan.isComplete)
        XCTAssertEqual(plan.files.map(\.remotePath), [
            "/share/root.txt",
            "/share/sub/a.bin",
            "/share/sub/b.bin",
        ])
        XCTAssertEqual(plan.totalBytes, 15)
        XCTAssertEqual(plan.largestFileBytes, 7)
        XCTAssertEqual(plan.folderCount, 2)
    }

    func test目录缓存规划遇到未知大小和无权目录时不可确认() async {
        let plan = await DesktopDriveTreePlanner.build(
            rootFolders: ["/share"]
        ) { path, _, _ in
            if path == "/share/private" {
                throw CocoaError(.fileReadNoPermission)
            }
            return FilePage(
                folderPath: path,
                items: [
                    Self.file(path: "/share/unknown.bin", size: nil),
                    Self.folder(path: "/share/private"),
                ],
                offset: 0,
                total: 2,
                hasMore: false
            )
        }

        XCTAssertFalse(plan.isComplete)
        XCTAssertEqual(
            Set(plan.issues.map(\.kind)),
            [.unknownFileSize, .inaccessibleFolder]
        )
    }

    func test缓存规划可合并直接文件与目录并去重() async {
        let direct = DesktopDrivePlannedFile(
            remotePath: "/share/direct.bin",
            sizeBytes: 7,
            modifiedAt: nil
        )
        let plan = await DesktopDriveTreePlanner.build(
            rootFolders: ["/share"],
            rootFiles: [direct, direct]
        ) { path, _, _ in
            FilePage(
                folderPath: path,
                items: [
                    Self.file(path: "/share/direct.bin", size: 7),
                    Self.file(path: "/share/nested.bin", size: 5),
                ],
                offset: 0,
                total: 2,
                hasMore: false
            )
        }

        XCTAssertTrue(plan.isComplete)
        XCTAssertEqual(plan.files.map(\.remotePath), [
            "/share/direct.bin",
            "/share/nested.bin",
        ])
        XCTAssertEqual(plan.totalBytes, 12)
        XCTAssertEqual(plan.largestFileBytes, 7)
    }

    func test项目身份稳定且不包含远端路径() {
        let mappingID = UUID()
        let first = DesktopDriveItemIdentity.identifier(
            mappingID: mappingID,
            remotePath: "/share/财务/预算.xlsx"
        )
        let second = DesktopDriveItemIdentity.identifier(
            mappingID: mappingID,
            remotePath: "//share/财务/预算.xlsx"
        )

        XCTAssertEqual(first, second)
        XCTAssertTrue(first?.hasPrefix("item:") == true)
        XCTAssertFalse(first?.contains("share") == true)
        XCTAssertFalse(first?.contains("预算") == true)
    }

    func test暂存文件身份对同一版本稳定且不暴露路径() {
        let mappingID = UUID()
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let first = DesktopDriveStagingIdentity.contentFileName(
            mappingID: mappingID,
            remotePath: "/share/财务/预算.xlsx",
            sizeBytes: 8_192,
            modifiedAt: modifiedAt
        )
        let second = DesktopDriveStagingIdentity.contentFileName(
            mappingID: mappingID,
            remotePath: "//share/财务/预算.xlsx",
            sizeBytes: 8_192,
            modifiedAt: modifiedAt
        )
        let changed = DesktopDriveStagingIdentity.contentFileName(
            mappingID: mappingID,
            remotePath: "/share/财务/预算.xlsx",
            sizeBytes: 8_193,
            modifiedAt: modifiedAt
        )

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, changed)
        XCTAssertTrue(first?.hasSuffix(".content") == true)
        XCTAssertFalse(first?.contains("share") == true)
        XCTAssertFalse(first?.contains("预算") == true)
    }

    func test离线保留目录覆盖全部后代但不覆盖相邻目录() {
        let runtime = DesktopDriveMappingRuntime(
            pinnedPaths: ["/share/projects"]
        )

        XCTAssertTrue(runtime.keepsOffline("/share/projects/readme.md"))
        XCTAssertTrue(runtime.keepsOffline("/share/projects/sub/a.bin"))
        XCTAssertFalse(runtime.keepsOffline("/share/projects-old/a.bin"))
    }

    func test临时缓存按最久未访问顺序清理且不影响离线文件() {
        let now = Date()
        let entries = [
            DesktopDriveCacheEntry(
                remotePath: "/old.bin",
                kind: .temporary,
                logicalSizeBytes: 4,
                allocatedSizeBytes: 4,
                lastAccessedAt: now.addingTimeInterval(-30)
            ),
            DesktopDriveCacheEntry(
                remotePath: "/new.bin",
                kind: .temporary,
                logicalSizeBytes: 6,
                allocatedSizeBytes: 6,
                lastAccessedAt: now
            ),
            DesktopDriveCacheEntry(
                remotePath: "/offline.bin",
                kind: .keptOffline,
                logicalSizeBytes: 100,
                allocatedSizeBytes: 100,
                lastAccessedAt: now.addingTimeInterval(-60)
            ),
        ]

        XCTAssertEqual(
            DesktopDriveCacheEvictionPlanner.temporaryPathsToEvict(
                entries: entries,
                limitBytes: 6
            ),
            ["/old.bin"]
        )
    }

    func test共享配置并发更新不会丢失缓存记录() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let profile = try NasProfile(
            id: UUID(),
            displayName: "Test",
            host: "nas.test",
            port: 5001,
            usernameHint: "user",
            pinnedCertificateSHA256: nil
        )
        let mapping = DesktopDriveMapping(
            profileID: profile.id,
            displayName: "Test",
            scope: .folder(path: "/share")
        )
        let firstStore = DesktopDriveConfigurationStore(directoryURL: directoryURL)
        let secondStore = DesktopDriveConfigurationStore(directoryURL: directoryURL)
        try await firstStore.saveConnection(
            profile: profile,
            capabilities: .init([:])
        )
        try await firstStore.saveMapping(mapping)

        async let firstBatch = Self.recordEntries(
            range: 0..<20,
            store: firstStore,
            mappingID: mapping.id
        )
        async let secondBatch = Self.recordEntries(
            range: 20..<40,
            store: secondStore,
            mappingID: mapping.id
        )
        try await firstBatch
        try await secondBatch

        let runtime = try await firstStore.runtime(mappingID: mapping.id)
        XCTAssertEqual(runtime.cacheEntries.count, 40)
    }

    private static func file(path: String, size: Int64?) -> FileItem {
        FileItem(
            profileID: UUID.zero,
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            kind: .file,
            sizeBytes: size
        )
    }

    private static func folder(path: String) -> FileItem {
        FileItem(
            profileID: UUID.zero,
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            kind: .directory
        )
    }

    private static func recordEntries(
        range: Range<Int>,
        store: DesktopDriveConfigurationStore,
        mappingID: UUID
    ) async throws {
        for index in range {
            let path = "/share/\(index).bin"
            try await store.recordCacheEntry(
                DesktopDriveCacheEntry(
                    remotePath: path,
                    kind: .temporary,
                    logicalSizeBytes: 1,
                    allocatedSizeBytes: 1
                ),
                mappingID: mappingID
            )
        }
    }
}

private extension UUID {
    static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}

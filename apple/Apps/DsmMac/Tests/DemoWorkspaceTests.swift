import DsmCore
import XCTest
@testable import DsmMacExecutable

final class DemoWorkspaceTests: XCTestCase {
    @MainActor
    func test跨NAS复制任务记录文件大小和总传输字节() async throws {
        let sourceProfile = try NasProfile(
            displayName: "来源",
            host: "source.example.invalid",
            port: 5_001
        )
        let destinationProfile = try NasProfile(
            displayName: "目标",
            host: "destination.example.invalid",
            port: 5_001
        )
        let source = WorkspaceModel(
            profile: sourceProfile,
            repository: DemoFileRepository(profileID: sourceProfile.id)
        )
        let destination = WorkspaceModel(
            profile: destinationProfile,
            repository: DemoFileRepository(profileID: destinationProfile.id)
        )
        await source.load()
        await destination.load()
        let file = try XCTUnwrap(source.items.first(where: { !$0.isDirectory && $0.sizeBytes != nil }))

        destination.enqueueCrossNASOperation(
            from: source,
            targets: [file],
            to: destination.currentPath,
            moveSource: false
        )

        let task = try XCTUnwrap(destination.transfers.first)
        XCTAssertEqual(task.fileSizeBytes, file.sizeBytes)
        XCTAssertEqual(task.totalUnits, (file.sizeBytes ?? 0) * 2)
        destination.cancelAllWork()
    }

    func test演示仓库可以新建文件夹和空白文件() async throws {
        let profileID = UUID()
        let repository = DemoFileRepository(profileID: profileID)
        try await repository.createFolder(parentPath: "/home", name: "新目录")
        let emptyFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("DemoWorkspaceTests-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: emptyFile) }
        try Data().write(to: emptyFile)
        try await repository.upload(localURL: emptyFile, to: "/home", overwrite: false) { _, _ in }

        let page = try await repository.listFolder(path: "/home", offset: 0, limit: 100)
        XCTAssertTrue(page.items.contains(where: { $0.name == "新目录" && $0.isDirectory }))
        XCTAssertTrue(page.items.contains(where: { $0.name == emptyFile.lastPathComponent && !$0.isDirectory }))
    }

    @MainActor
    func test演示工作区加载共享和首个目录() async throws {
        let profile = try NasProfile(
            displayName: "演示",
            host: "demo.example.invalid",
            port: 5_001
        )
        let model = WorkspaceModel(
            profile: profile,
            repository: DemoFileRepository(profileID: profile.id)
        )

        await model.load()

        XCTAssertEqual(model.shares.count, 3)
        XCTAssertEqual(model.currentPath, "/home")
        XCTAssertFalse(model.items.isEmpty)
        XCTAssertEqual(model.recycleRoots.count, 3)
    }

    func test演示删除进入回收站并可移动恢复() async throws {
        let profileID = UUID()
        let repository = DemoFileRepository(profileID: profileID)
        let home = try await repository.listFolder(path: "/home", offset: 0, limit: 100)
        let file = try XCTUnwrap(home.items.first(where: { $0.name == "欢迎使用岚仓.txt" }))

        try await repository.delete(paths: [file.path]) { _, _ in }
        let recycle = try await repository.listFolder(path: "/home/#recycle", offset: 0, limit: 100)
        let recycled = try XCTUnwrap(recycle.items.first(where: { $0.name == file.name }))

        try await repository.move(paths: [recycled.path], to: "/home", overwrite: false) { _, _ in }
        let restored = try await repository.listFolder(path: "/home", offset: 0, limit: 100)
        XCTAssertTrue(restored.items.contains(where: { $0.name == file.name }))
    }

    @MainActor
    func test切换页面不会取消下载() async throws {
        let profile = try NasProfile(
            displayName: "演示",
            host: "demo.example.invalid",
            port: 5_001
        )
        let model = WorkspaceModel(
            profile: profile,
            repository: DemoFileRepository(profileID: profile.id)
        )
        await model.load()
        let file = try XCTUnwrap(model.items.first(where: { !$0.isDirectory }))
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("DemoWorkspaceTests-\(UUID().uuidString)-\(file.name)")
        defer { try? FileManager.default.removeItem(at: destination) }

        model.enqueueDownload(file, to: destination)
        model.section = .transfers
        model.section = .files(model.currentPath)

        for _ in 0..<40 {
            if model.transfers.first?.state == .succeeded {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(model.transfers.first?.state, .succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func test传输速度和剩余时间估算() throws {
        var estimator = TransferProgressEstimator()
        let start = Date(timeIntervalSince1970: 1_000)

        _ = estimator.update(completed: 0, total: 3_000_000, at: start)
        let metrics = estimator.update(
            completed: 1_000_000,
            total: 3_000_000,
            at: start.addingTimeInterval(1)
        )

        XCTAssertEqual(try XCTUnwrap(metrics.speed), 1_000_000, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(metrics.remaining), 2, accuracy: 0.1)
    }

    func test高频进度回调仍可计算速度() throws {
        var estimator = TransferProgressEstimator()
        let start = Date(timeIntervalSince1970: 2_000)

        _ = estimator.update(completed: 0, total: 1_000_000, at: start)
        _ = estimator.update(
            completed: 100_000,
            total: 1_000_000,
            at: start.addingTimeInterval(0.1)
        )
        let metrics = estimator.update(
            completed: 300_000,
            total: 1_000_000,
            at: start.addingTimeInterval(0.3)
        )

        XCTAssertEqual(try XCTUnwrap(metrics.speed), 1_000_000, accuracy: 1)
    }
}

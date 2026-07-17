import DsmCore
import CryptoKit
import Foundation
import XCTest
@testable import DsmNetwork

final class DsmFileRepositoryTests: XCTestCase {
    func test解析共享文件夹与附加信息() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"offset":0,"total":1,"shares":[{"name":"projects","path":"/projects","isdir":true,"additional":{"size":4096,"type":"dir","owner":{"user":"tester","group":"users"},"time":{"mtime":1700000000,"crtime":1690000000,"atime":1700000100},"perm":{"posix":493,"adv_right":{"read":true,"write":true,"delete":true}}}}]}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationList: capability(DsmAPIName.fileStationList, version: 2)
            ]),
            transport: transport
        )

        let page = try await repository.listShares(offset: 0, limit: 100)

        XCTAssertEqual(page.total, 1)
        let share = try XCTUnwrap(page.items.first)
        XCTAssertEqual(share.path, "/projects")
        XCTAssertTrue(share.isDirectory)
        XCTAssertEqual(share.owner, "tester")
        XCTAssertEqual(share.permissions?.canWrite, true)
    }

    func test二进制下载写入目标且凭据在URL中() async throws {
        let response = DsmHTTPResponse(
            data: Data("hello".utf8),
            statusCode: 200,
            headers: ["content-type": "application/octet-stream"]
        )
        let transport = MockHTTPTransport(responses: [response])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDownload: capability(DsmAPIName.fileStationDownload, version: 2)
            ]),
            transport: transport
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("DsmFileRepositoryTests-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: destination) }

        try await repository.download(
            remotePath: "/projects/a.txt",
            to: destination,
            expectedSize: 5
        ) { _, _ in }

        XCTAssertEqual(try Data(contentsOf: destination), Data("hello".utf8))
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNotNil(request.url?.query)
        XCTAssertTrue(request.url?.absoluteString.contains("api=SYNO.FileStation.Download") == true)
    }

    func test下载返回错误JSON时抛出异常() async throws {
        let response = DsmHTTPResponse(
            data: Data(#"{"success":false,"error":{"code":119}}"#.utf8),
            statusCode: 200,
            headers: ["content-type": "application/json"]
        )
        let transport = MockHTTPTransport(responses: [response])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDownload: capability(DsmAPIName.fileStationDownload, version: 2)
            ]),
            transport: transport
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("DsmFileRepositoryTests-Error-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: destination) }

        do {
            try await repository.download(
                remotePath: "/projects/a.txt",
                to: destination,
                expectedSize: nil
            ) { _, _ in }
            XCTFail("应该抛出错误，但下载却被判定为成功")
        } catch let error as AppError {
            XCTAssertEqual(error.dsmCode, 119)
            XCTAssertEqual(error.category, .authenticationRequired)
            XCTAssertTrue(error.safeUserMessage.contains("登录已过期"))
        }
    }

    func test下载从已有分片继续() async throws {
        let response = DsmHTTPResponse(
            data: Data("llo".utf8),
            statusCode: 206,
            headers: ["content-type": "application/octet-stream"]
        )
        let transport = MockHTTPTransport(responses: [response])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDownload: capability(DsmAPIName.fileStationDownload, version: 2)
            ]),
            transport: transport
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("DsmFileRepositoryTests-Resume-\(UUID().uuidString).txt")
        let identity = "\(repository.profileID.uuidString)|/projects/a.txt|5"
        let digest = SHA256.hash(data: Data(identity.utf8))
        let suffix = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        let partURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(suffix).lanstash.part")
        try Data("he".utf8).write(to: partURL)

        try await repository.download(
            remotePath: "/projects/a.txt",
            to: destination,
            expectedSize: 5
        ) { _, _ in }

        XCTAssertEqual(try Data(contentsOf: destination), Data("hello".utf8))
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=2-4")
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.removeItem(at: partURL)
    }

    func test删除下载任务会清理对应分片() async throws {
        let transport = MockHTTPTransport(responses: [])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDownload: capability(DsmAPIName.fileStationDownload, version: 2)
            ]),
            transport: transport
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DsmFileRepositoryTests-Cleanup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("archive.zip")
        let legacyPart = directory.appendingPathComponent(".archive.zip.lanstash.part")
        let isolatedPart = directory.appendingPathComponent(".archive.zip.0123456789abcdef.lanstash.part")
        let unrelatedPart = directory.appendingPathComponent(".other.zip.0123456789abcdef.lanstash.part")
        try Data("legacy".utf8).write(to: legacyPart)
        try Data("isolated".utf8).write(to: isolatedPart)
        try Data("keep".utf8).write(to: unrelatedPart)

        await repository.removePartialDownload(to: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPart.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: isolatedPart.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedPart.path))
    }

    func test媒体流使用认证请求头且会话不进入URL() async throws {
        let transport = MockHTTPTransport(responses: [])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDownload: capability(DsmAPIName.fileStationDownload, version: 2)
            ]),
            transport: transport
        )

        let source = try await repository.mediaStreamSource(
            remotePath: "/projects/movie.mp4",
            fileExtension: "mp4",
            expectedContentLength: 2_500_000_000
        )

        let components = URLComponents(
            url: try XCTUnwrap(source.request.url),
            resolvingAgainstBaseURL: false
        )
        let query = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        XCTAssertEqual(query["api"], DsmAPIName.fileStationDownload)
        let encodedPath = try XCTUnwrap(query["path"]?.data(using: .utf8))
        XCTAssertEqual(
            try JSONDecoder().decode([String].self, from: encodedPath),
            ["/projects/movie.mp4"]
        )
        XCTAssertNil(query["_sid"])
        XCTAssertNil(query["SynoToken"])
        XCTAssertEqual(source.request.value(forHTTPHeaderField: "Cookie"), "id=REDACTED_SESSION")
        XCTAssertEqual(source.request.value(forHTTPHeaderField: "X-SYNO-TOKEN"), "REDACTED_SESSION")
        XCTAssertEqual(source.expectedContentLength, 2_500_000_000)
    }

    func test二进制上传包含CSRF头() async throws {
        let response1 = DsmHTTPResponse(
            data: Data(#"{"success":true}"#.utf8),
            statusCode: 200
        )
        let response2 = DsmHTTPResponse(
            data: Data(#"{"success":true}"#.utf8),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response1, response2])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationUpload: capability(DsmAPIName.fileStationUpload, version: 2),
                DsmAPIName.fileStationCheckPermission: capability(DsmAPIName.fileStationCheckPermission, version: 1)
            ]),
            transport: transport
        )
        let localFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("DsmFileRepositoryTests-Upload-\(UUID().uuidString).txt")
        try Data("test upload data".utf8).write(to: localFile)
        defer { try? FileManager.default.removeItem(at: localFile) }

        try await repository.upload(
            localURL: localFile,
            to: "/projects",
            overwrite: true
        ) { _, _ in }

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)

        let checkPermRequest = requests[0]
        XCTAssertEqual(checkPermRequest.value(forHTTPHeaderField: "X-SYNO-TOKEN"), "REDACTED_SESSION")
        XCTAssertEqual(checkPermRequest.value(forHTTPHeaderField: "Cookie"), "id=REDACTED_SESSION")

        let uploadRequest = requests[1]
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "X-SYNO-TOKEN"), "REDACTED_SESSION")
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "Cookie"), "id=REDACTED_SESSION")

        let uploadURLComponents = URLComponents(url: try XCTUnwrap(uploadRequest.url), resolvingAgainstBaseURL: false)
        let uploadQuery = Dictionary(uniqueKeysWithValues: (uploadURLComponents?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(uploadQuery["api"], "SYNO.FileStation.Upload")
        XCTAssertEqual(uploadQuery["version"], "2")
        XCTAssertEqual(uploadQuery["method"], "upload")
        XCTAssertEqual(uploadQuery["_sid"], "REDACTED_SESSION")
        XCTAssertEqual(uploadQuery["SynoToken"], "REDACTED_SESSION")
        XCTAssertEqual(uploadQuery["synotoken"], "REDACTED_SESSION")
    }

    func test上传同名冲突显示可执行提示() async throws {
        let permissionResponse = DsmHTTPResponse(
            data: Data(#"{"success":true}"#.utf8),
            statusCode: 200
        )
        let uploadResponse = DsmHTTPResponse(
            data: Data(#"{"success":false,"error":{"code":1805}}"#.utf8),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [permissionResponse, uploadResponse])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationUpload: capability(DsmAPIName.fileStationUpload, version: 2),
                DsmAPIName.fileStationCheckPermission: capability(DsmAPIName.fileStationCheckPermission, version: 1)
            ]),
            transport: transport
        )
        let localFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("DsmFileRepositoryTests-Conflict-\(UUID().uuidString).txt")
        try Data("test upload data".utf8).write(to: localFile)
        defer { try? FileManager.default.removeItem(at: localFile) }

        do {
            try await repository.upload(
                localURL: localFile,
                to: "/projects",
                overwrite: false
            ) { _, _ in }
            XCTFail("预期上传失败")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .conflict)
            XCTAssertEqual(error.dsmCode, 1805)
            XCTAssertTrue(error.safeUserMessage.contains("同名文件"))
        }
    }

    func test上传空间满或被拒错误映射() async throws {
        // 测试 108 (上传失败)
        let permissionResponse = DsmHTTPResponse(
            data: Data(#"{"success":true}"#.utf8),
            statusCode: 200
        )
        let uploadResponse108 = DsmHTTPResponse(
            data: Data(#"{"success":false,"error":{"code":108}}"#.utf8),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [permissionResponse, uploadResponse108])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationUpload: capability(DsmAPIName.fileStationUpload, version: 2),
                DsmAPIName.fileStationCheckPermission: capability(DsmAPIName.fileStationCheckPermission, version: 1)
            ]),
            transport: transport
        )
        let localFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("DsmFileRepositoryTests-Error-\(UUID().uuidString).txt")
        try Data("test upload data".utf8).write(to: localFile)
        defer { try? FileManager.default.removeItem(at: localFile) }

        do {
            try await repository.upload(
                localURL: localFile,
                to: "/projects",
                overwrite: true
            ) { _, _ in }
            XCTFail("预期上传失败")
        } catch let error as AppError {
            XCTAssertEqual(error.dsmCode, 108)
            XCTAssertTrue(error.safeUserMessage.contains("空间或传输状态"))
        }

        // 测试 115 (不允许上传)
        let uploadResponse115 = DsmHTTPResponse(
            data: Data(#"{"success":false,"error":{"code":115}}"#.utf8),
            statusCode: 200
        )
        let transport2 = MockHTTPTransport(responses: [permissionResponse, uploadResponse115])
        let repository2 = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationUpload: capability(DsmAPIName.fileStationUpload, version: 2),
                DsmAPIName.fileStationCheckPermission: capability(DsmAPIName.fileStationCheckPermission, version: 1)
            ]),
            transport: transport2
        )

        do {
            try await repository2.upload(
                localURL: localFile,
                to: "/projects",
                overwrite: true
            ) { _, _ in }
            XCTFail("预期上传失败")
        } catch let error as AppError {
            XCTAssertEqual(error.dsmCode, 115)
            XCTAssertEqual(error.category, .permissionDenied)
            XCTAssertTrue(error.safeUserMessage.contains("不允许上传"))
        }
    }

    private func makeRepository(
        capabilities: CapabilitySet,
        transport: MockHTTPTransport
    ) throws -> DsmFileRepository {
        let profile = try NasProfile(
            displayName: "测试设备",
            host: "nas.example.invalid",
            port: 5_001
        )
        return try DsmFileRepository(
            profile: profile,
            capabilities: capabilities,
            session: AuthSession(
                sid: "REDACTED_SESSION",
                synoToken: "REDACTED_SESSION",
                did: nil,
                isPortalPort: false
            ),
            transport: transport
        )
    }

    private func capability(_ name: String, version: Int) -> ApiCapability {
        ApiCapability(
            name: name,
            path: "entry.cgi",
            minVersion: 1,
            maxVersion: version,
            requestFormat: .form,
            selectedVersion: version
        )
    }
}

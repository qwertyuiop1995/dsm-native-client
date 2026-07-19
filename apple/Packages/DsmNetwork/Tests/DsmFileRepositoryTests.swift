import DsmCore
import CryptoKit
import Foundation
import XCTest
@testable import DsmNetwork

final class DsmFileRepositoryTests: XCTestCase {
    func test解析共享文件夹与附加信息() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"offset":0,"total":1,"shares":[{"name":"projects","path":"/projects","isdir":true,"additional":{"size":4096,"type":"dir","mount_point_type":"cifs","owner":{"user":"tester","group":"users"},"time":{"mtime":1700000000,"crtime":1690000000,"atime":1700000100},"perm":{"posix":493,"adv_right":{"read":true,"write":true,"delete":true}}}}]}}"#.utf8
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
        XCTAssertEqual(share.mountPointType, "cifs")
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

    func test读取文件头使用Range且凭据不进入URL() async throws {
        let payload = Data(repeating: 0x47, count: 4_096)
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(
                data: payload,
                statusCode: 206,
                headers: ["content-type": "application/octet-stream"]
            )
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDownload: capability(DsmAPIName.fileStationDownload, version: 2)
            ]),
            transport: transport
        )

        let prefix = try await repository.readPrefix(
            remotePath: "/projects/ambiguous.ts",
            maximumLength: 4_096
        )

        XCTAssertEqual(prefix, payload)
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-4095")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "id=REDACTED_SESSION")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-SYNO-TOKEN"), "REDACTED_SESSION")
        XCTAssertFalse(request.url?.absoluteString.contains("REDACTED_SESSION") == true)
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
        let checkPermBody = try XCTUnwrap(checkPermRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(checkPermBody.contains("create_only=true"))
        XCTAssertTrue(checkPermBody.contains("LanStash-Write-Check-"))

        let uploadRequest = requests[1]
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "X-SYNO-TOKEN"), "REDACTED_SESSION")
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "Cookie"), "id=REDACTED_SESSION")
        XCTAssertNotNil(uploadRequest.value(forHTTPHeaderField: "Content-Length"))

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

    func test批量下载把所有路径交给NAS生成压缩包() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(data: Data("PK".utf8), statusCode: 200, headers: ["content-type": "application/zip"])
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDownload: capability(DsmAPIName.fileStationDownload, version: 2)
            ]),
            transport: transport
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: destination) }

        try await repository.downloadArchive(
            remotePaths: ["/home/a.txt", "/home/folder"],
            to: destination
        ) { _, _ in }

        let recordedRequests = await transport.recordedRequests()
        let request = try XCTUnwrap(recordedRequests.first)
        let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        let pathValue = try XCTUnwrap(components?.queryItems?.first(where: { $0.name == "path" })?.value)
        XCTAssertEqual(
            try JSONDecoder().decode([String].self, from: Data(pathValue.utf8)),
            ["/home/a.txt", "/home/folder"]
        )
    }

    func test重命名使用公开接口并把名称放在请求正文() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(data: Data(#"{"success":true}"#.utf8), statusCode: 200)
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationRename: capability(DsmAPIName.fileStationRename, version: 2)
            ]),
            transport: transport
        )

        try await repository.rename(path: "/home/旧名称.txt", newName: "新名称.txt")

        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let queryItems = URLComponents(string: "?\(body)")?.queryItems
        XCTAssertEqual(queryItems?.first(where: { $0.name == "api" })?.value, DsmAPIName.fileStationRename)
        XCTAssertEqual(queryItems?.first(where: { $0.name == "method" })?.value, "rename")
        let pathValue = try XCTUnwrap(queryItems?.first(where: { $0.name == "path" })?.value)
        let nameValue = try XCTUnwrap(queryItems?.first(where: { $0.name == "name" })?.value)
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: Data(pathValue.utf8)), ["/home/旧名称.txt"])
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: Data(nameValue.utf8)), ["新名称.txt"])
    }

    func test压缩使用NAS任务并把选项放在请求正文() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(data: Data(#"{"success":true,"data":{"taskid":"compress-1"}}"#.utf8), statusCode: 200),
            DsmHTTPResponse(data: Data(#"{"success":true,"data":{"finished":true}}"#.utf8), statusCode: 200)
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationCompress: capability(DsmAPIName.fileStationCompress, version: 3)
            ]),
            transport: transport
        )

        try await repository.compress(
            paths: ["/home/图片", "/home/说明.txt"],
            destinationFilePath: "/home/资料.7z",
            format: .sevenZip,
            level: .best,
            password: "REDACTED_ARCHIVE_PASSWORD"
        ) { _, _ in }

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertFalse(request.url?.absoluteString.contains("REDACTED_ARCHIVE_PASSWORD") == true)
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let queryItems = URLComponents(string: "?\(body)")?.queryItems
        XCTAssertEqual(queryItems?.first(where: { $0.name == "api" })?.value, DsmAPIName.fileStationCompress)
        XCTAssertEqual(queryItems?.first(where: { $0.name == "method" })?.value, "start")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "dest_file_path" })?.value, "/home/资料.7z")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "format" })?.value, "7z")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "level" })?.value, "best")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "password" })?.value, "REDACTED_ARCHIVE_PASSWORD")
        let pathValue = try XCTUnwrap(queryItems?.first(where: { $0.name == "path" })?.value)
        XCTAssertEqual(
            try JSONDecoder().decode([String].self, from: Data(pathValue.utf8)),
            ["/home/图片", "/home/说明.txt"]
        )
    }

    func test解压缩使用NAS任务并兼容小数进度() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(data: Data(#"{"success":true,"data":{"taskid":"extract-1"}}"#.utf8), statusCode: 200),
            DsmHTTPResponse(data: Data(#"{"success":true,"data":{"finished":true,"progress":0.75}}"#.utf8), statusCode: 200)
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationExtract: capability(DsmAPIName.fileStationExtract, version: 2)
            ]),
            transport: transport
        )
        let progressRecorder = TestProgressRecorder()

        try await repository.extract(
            filePath: "/home/资料.zip",
            destinationFolder: "/home",
            overwrite: false,
            keepDirectoryStructure: true,
            createSubfolder: true,
            codepage: "chs",
            password: nil
        ) { value, _ in
            progressRecorder.record(value)
        }

        XCTAssertEqual(progressRecorder.value, 75)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let queryItems = URLComponents(string: "?\(body)")?.queryItems
        XCTAssertEqual(queryItems?.first(where: { $0.name == "api" })?.value, DsmAPIName.fileStationExtract)
        XCTAssertEqual(queryItems?.first(where: { $0.name == "file_path" })?.value, "/home/资料.zip")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "dest_folder_path" })?.value, "/home")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "overwrite" })?.value, "false")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "keep_dir" })?.value, "true")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "create_subfolder" })?.value, "true")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "codepage" })?.value, "chs")
    }

    func test读取压缩包内容用于密码与文件名检测() async throws {
        let response = DsmHTTPResponse(
            data: Data(#"{"success":true,"data":{"items":[{"itemid":7,"name":"存档","path":"/存档","size":0,"pack_size":0,"mtime":"0","is_dir":true}]}}"#.utf8),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationExtract: capability(DsmAPIName.fileStationExtract, version: 2)
            ]),
            transport: transport
        )

        let items = try await repository.listArchiveItems(
            filePath: "/home/存档.zip",
            codepage: "chs",
            password: "REDACTED_ARCHIVE_PASSWORD"
        )

        XCTAssertEqual(items, [ArchiveItem(id: 7, name: "存档", path: "/存档", isDirectory: true)])
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let queryItems = URLComponents(string: "?\(body)")?.queryItems
        XCTAssertEqual(queryItems?.first(where: { $0.name == "method" })?.value, "list")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "codepage" })?.value, "chs")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "password" })?.value, "REDACTED_ARCHIVE_PASSWORD")
    }

    func test递归搜索会清理NAS上的搜索任务() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(data: Data(#"{"success":true,"data":{"taskid":"task-1"}}"#.utf8), statusCode: 200),
            DsmHTTPResponse(data: Data(#"{"success":true,"data":{"offset":0,"total":1,"finished":true,"files":[{"name":"说明.txt","path":"/home/docs/说明.txt","isdir":false}]}}"#.utf8), statusCode: 200),
            DsmHTTPResponse(data: Data(#"{"success":true}"#.utf8), statusCode: 200)
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationSearch: capability(DsmAPIName.fileStationSearch, version: 2)
            ]),
            transport: transport
        )

        let results = try await repository.search(folderPath: "/home", query: "说明")

        XCTAssertEqual(results.map(\.path), ["/home/docs/说明.txt"])
        let methods = await transport.recordedRequests().compactMap { request in
            if let value = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "method" })?.value {
                return value
            }
            guard let body = request.httpBody.flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
            return URLComponents(string: "?\(body)")?.queryItems?.first(where: { $0.name == "method" })?.value
        }
        XCTAssertEqual(methods, ["start", "list", "clean"])
    }

    func test收藏和分享链接可以创建列出并取消() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(data: Data(#"{"success":true}"#.utf8), statusCode: 200),
            DsmHTTPResponse(data: Data(#"{"success":true,"data":{"favorites":[{"name":"文档","path":"/home/docs"}]}}"#.utf8), statusCode: 200),
            DsmHTTPResponse(data: Data(#"{"success":true}"#.utf8), statusCode: 200),
            DsmHTTPResponse(data: Data(#"{"success":true,"data":{"links":[{"id":"link-1","name":"说明.txt","path":"/home/说明.txt","url":"https://share.example.invalid/x","has_password":true,"date_expired":"2026-08-01"}]}}"#.utf8), statusCode: 200),
            DsmHTTPResponse(data: Data(#"{"success":true,"data":{"links":[{"id":"link-1","name":"说明.txt","path":"/home/说明.txt","url":"https://share.example.invalid/x","has_password":true,"date_expired":"2026-08-01"}]}}"#.utf8), statusCode: 200),
            DsmHTTPResponse(data: Data(#"{"success":true}"#.utf8), statusCode: 200)
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationFavorite: capability(DsmAPIName.fileStationFavorite, version: 2),
                DsmAPIName.fileStationSharing: capability(DsmAPIName.fileStationSharing, version: 3)
            ]),
            transport: transport
        )

        try await repository.addFavorite(path: "/home/docs", name: "文档")
        let favorites = try await repository.listFavorites()
        XCTAssertEqual(favorites.map(\.path), ["/home/docs"])
        try await repository.removeFavorite(path: "/home/docs")
        let created = try await repository.createShareLink(
            paths: ["/home/说明.txt"],
            password: "REDACTED_PASSWORD",
            expiresAt: "2026-08-01"
        )
        XCTAssertEqual(created.id, "link-1")
        let links = try await repository.listShareLinks()
        XCTAssertEqual(links.map(\.id), ["link-1"])
        try await repository.deleteShareLinks(ids: ["link-1"])
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

private final class TestProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Int64 = 0

    var value: Int64 {
        lock.withLock { storedValue }
    }

    func record(_ value: Int64) {
        lock.withLock { storedValue = value }
    }
}

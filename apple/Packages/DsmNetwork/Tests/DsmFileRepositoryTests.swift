import DsmCore
import DsmLocalization
import CryptoKit
import Foundation
import XCTest
@testable import DsmNetwork

final class DsmFileRepositoryTests: XCTestCase {
    func test目录大小使用官方V2任务且只保留安全汇总字段() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"taskid":"dirsize-task"}}"#),
            response(#"{"success":true,"data":{"finished":false,"path":"/home/private","password":"PRIVATE_PASSWORD"}}"#),
            response(#"{"success":true,"data":{"finished":true,"total_size":"4096","num_file":"3","num_dir":"2","processing_path":"/home/private/current"}}"#),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDirSize: capability(DsmAPIName.fileStationDirSize, version: 2)
            ]),
            transport: transport,
            directorySizePollingPolicy: .init(
                maxAttempts: 3,
                initialDelayNanoseconds: 0,
                maximumDelayNanoseconds: 0
            )
        )

        let summary = try await repository.calculateDirectorySize(path: "/home//private/")

        XCTAssertEqual(summary.totalBytes, 4_096)
        XCTAssertEqual(summary.fileCount, 3)
        XCTAssertEqual(summary.directoryCount, 2)
        XCTAssertFalse(String(describing: summary).contains("/home/private"))
        XCTAssertFalse(String(describing: summary).contains("PRIVATE_PASSWORD"))
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.compactMap { requestParameter("method", in: $0) }, ["start", "status", "status"])
        XCTAssertTrue(requests.allSatisfy { requestParameter("version", in: $0) == "2" })
        let encodedPaths = try XCTUnwrap(requestParameter("path", in: requests[0]))
        XCTAssertEqual(
            try JSONDecoder().decode([String].self, from: Data(encodedPaths.utf8)),
            ["/home/private"]
        )
        XCTAssertEqual(requestParameter("taskid", in: requests[1]), "dirsize-task")
        XCTAssertFalse(requests.contains { $0.url?.absoluteString.contains("private") == true })
    }

    func test目录大小缺少能力或路径无效时不发请求() async throws {
        let missingTransport = MockHTTPTransport(responses: [])
        let missingRepository = try makeRepository(
            capabilities: CapabilitySet([:]),
            transport: missingTransport
        )
        do {
            _ = try await missingRepository.calculateDirectorySize(path: "/home/docs")
            XCTFail("缺少能力时不应继续")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .apiUnavailable)
        }
        let missingRequests = await missingTransport.recordedRequests()
        XCTAssertTrue(missingRequests.isEmpty)

        for invalidPath in ["", "home/docs", "/home/../private"] {
            let transport = MockHTTPTransport(responses: [])
            let repository = try makeRepository(
                capabilities: CapabilitySet([
                    DsmAPIName.fileStationDirSize: capability(DsmAPIName.fileStationDirSize, version: 2)
                ]),
                transport: transport
            )
            do {
                _ = try await repository.calculateDirectorySize(path: invalidPath)
                XCTFail("无效路径不应继续")
            } catch let error as AppError {
                XCTAssertFalse(error.isRetryable)
            }
            let requests = await transport.recordedRequests()
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func test目录大小轮询超时会停止任务且不会重放启动() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"taskid":"dirsize-timeout"}}"#),
            response(#"{"success":true,"data":{"finished":false}}"#),
            response(#"{"success":true,"data":{"finished":false}}"#),
            response(#"{"success":true}"#),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDirSize: capability(DsmAPIName.fileStationDirSize, version: 2)
            ]),
            transport: transport,
            directorySizePollingPolicy: .init(
                maxAttempts: 2,
                initialDelayNanoseconds: 0,
                maximumDelayNanoseconds: 0
            )
        )

        do {
            _ = try await repository.calculateDirectorySize(path: "/home/docs")
            XCTFail("达到轮询上限后应报告超时")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .timeout)
        }

        let methods = await transport.recordedRequests().compactMap {
            requestParameter("method", in: $0)
        }
        XCTAssertEqual(methods, ["start", "status", "status", "stop"])
        XCTAssertEqual(methods.filter { $0 == "start" }.count, 1)
    }

    func test目录大小提交后取消会停止远端任务() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"taskid":"dirsize-cancel"}}"#)),
            .waitUntilCancelled,
            .response(response(#"{"success":true}"#)),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDirSize: capability(DsmAPIName.fileStationDirSize, version: 2)
            ]),
            transport: transport,
            directorySizePollingPolicy: .init(
                maxAttempts: 2,
                initialDelayNanoseconds: 0,
                maximumDelayNanoseconds: 0
            )
        )
        let task = Task {
            try await repository.calculateDirectorySize(path: "/home/docs")
        }
        while await transport.recordedRequests().count < 2 {
            await Task.yield()
        }

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("取消后不应返回结果")
        } catch is CancellationError {
            // 预期取消。
        }

        let methods = await transport.recordedRequests().compactMap {
            requestParameter("method", in: $0)
        }
        XCTAssertEqual(methods, ["start", "status", "stop"])
    }

    func test目录大小拒绝重复规范化路径并在结束后释放占用() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"taskid":"dirsize-active"}}"#)),
            .waitUntilCancelled,
            .response(response(#"{"success":true}"#)),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDirSize: capability(DsmAPIName.fileStationDirSize, version: 2)
            ]),
            transport: transport,
            directorySizePollingPolicy: .init(
                maxAttempts: 2,
                initialDelayNanoseconds: 0,
                maximumDelayNanoseconds: 0
            )
        )
        let firstTask = Task {
            try await repository.calculateDirectorySize(path: "/home/docs/")
        }
        while await transport.recordedRequests().count < 2 {
            await Task.yield()
        }

        do {
            _ = try await repository.calculateDirectorySize(path: "/home//docs")
            XCTFail("相同规范化路径不应重复提交")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .conflict)
        }
        firstTask.cancel()
        _ = try? await firstTask.value

        let methods = await transport.recordedRequests().compactMap {
            requestParameter("method", in: $0)
        }
        XCTAssertEqual(methods, ["start", "status", "stop"])
    }

    func test目录大小完成响应缺字段时不再停止已完成任务() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"taskid":"dirsize-finished"}}"#),
            response(#"{"success":true,"data":{"finished":true,"total_size":4096,"num_file":-1}}"#),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDirSize: capability(DsmAPIName.fileStationDirSize, version: 2)
            ]),
            transport: transport
        )

        do {
            _ = try await repository.calculateDirectorySize(path: "/home/docs")
            XCTFail("完成响应缺少有效汇总时应失败")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .invalidResponse)
        }

        let methods = await transport.recordedRequests().compactMap {
            requestParameter("method", in: $0)
        }
        XCTAssertEqual(methods, ["start", "status"])
    }

    func test后台任务列表使用有界官方V3请求() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"offset":0,"total":0,"tasks":[]}}"#)
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationBackgroundTask: capability(
                    DsmAPIName.fileStationBackgroundTask,
                    version: 3
                )
            ]),
            transport: transport
        )

        let page = try await repository.listBackgroundTasks(offset: -20, limit: 5_000)

        XCTAssertTrue(page.tasks.isEmpty)
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requestParameter("api", in: request), DsmAPIName.fileStationBackgroundTask)
        XCTAssertEqual(requestParameter("version", in: request), "3")
        XCTAssertEqual(requestParameter("method", in: request), "list")
        XCTAssertEqual(requestParameter("offset", in: request), "0")
        XCTAssertEqual(requestParameter("limit", in: request), "100")
        XCTAssertEqual(requestParameter("sort_by", in: request), "crtime")
        XCTAssertEqual(requestParameter("sort_direction", in: request), "desc")
        XCTAssertEqual(
            requestParameter("api_filter", in: request),
            #"["SYNO.FileStation.CopyMove","SYNO.FileStation.Delete","SYNO.FileStation.Extract","SYNO.FileStation.Compress"]"#
        )
        XCTAssertNil(requestParameter("path", in: request))
    }

    func test缺少后台任务能力时零请求降级() async throws {
        let transport = MockHTTPTransport(responses: [])
        let repository = try makeRepository(
            capabilities: CapabilitySet([:]),
            transport: transport
        )

        do {
            _ = try await repository.listBackgroundTasks(offset: 0, limit: 100)
            XCTFail("缺少能力时不应发起请求")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .apiUnavailable)
        }

        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func test后台任务只保留白名单字段且已结束不等于成功() async throws {
        let body = #"{"success":true,"data":{"offset":0,"total":2,"tasks":[{"api":"SYNO.FileStation.CopyMove","taskid":"copy-1","finished":false,"progress":0.25,"crtime":1700000000,"processed_num":2,"processed_size":1024,"total":4096,"params":{"password":"PRIVATE_PASSWORD"},"path":"/volume1/private/source.txt","processing_path":"/volume1/private/current.txt","message":"PRIVATE_MESSAGE"},{"api":"SYNO.FileStation.Compress","taskid":"compress-1","finished":true,"progress":1,"processed_num":3,"processed_size":2048,"total":99,"params":{"password":"PRIVATE_ARCHIVE_PASSWORD"}}]}}"#
        let transport = MockHTTPTransport(responses: [response(body)])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationBackgroundTask: capability(
                    DsmAPIName.fileStationBackgroundTask,
                    version: 3
                )
            ]),
            transport: transport
        )

        let page = try await repository.listBackgroundTasks(offset: 0, limit: 100)

        XCTAssertEqual(page.tasks.map(\.id), ["copy-1", "compress-1"])
        XCTAssertEqual(page.tasks[0].kind, .copyOrMove)
        XCTAssertEqual(page.tasks[0].state, .active)
        XCTAssertEqual(page.tasks[0].progress, 0.25)
        XCTAssertEqual(page.tasks[0].totalBytes, 4_096)
        XCTAssertEqual(page.tasks[1].kind, .compress)
        XCTAssertEqual(page.tasks[1].state, .finished)
        XCTAssertNil(page.tasks[1].totalBytes)
        XCTAssertNil(page.tasks[1].totalItemCount)
        let description = String(describing: page)
        XCTAssertFalse(description.contains("/volume1"))
        XCTAssertFalse(description.contains("PRIVATE_PASSWORD"))
        XCTAssertFalse(description.contains("PRIVATE_ARCHIVE_PASSWORD"))
        XCTAssertFalse(description.contains("PRIVATE_MESSAGE"))
    }

    func test后台任务按原始行推进并丢弃未知类型坏ID和重复ID() async throws {
        let body = #"{"success":true,"data":{"offset":10,"total":15,"tasks":[{"api":"SYNO.FileStation.CopyMove","taskid":"safe-1","finished":false},{"api":"SYNO.FileStation.Future","taskid":"future-1","finished":false},{"api":"SYNO.FileStation.Delete","taskid":"/volume1/private/task","finished":false},{"api":"SYNO.FileStation.CopyMove","taskid":"safe-1","finished":true},{"api":"SYNO.FileStation.Delete","taskid":"safe-2","finished":false,"processed_num":4,"total":9}]}}"#
        let transport = MockHTTPTransport(responses: [response(body)])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationBackgroundTask: capability(
                    DsmAPIName.fileStationBackgroundTask,
                    version: 3
                )
            ]),
            transport: transport
        )

        let page = try await repository.listBackgroundTasks(offset: 10, limit: 100)

        XCTAssertEqual(page.tasks.map(\.id), ["safe-1", "safe-2"])
        XCTAssertEqual(page.tasks.last?.totalItemCount, 9)
        XCTAssertEqual(page.nextOffset, 15)
        XCTAssertFalse(page.hasMore)
        XCTAssertFalse(String(describing: page).contains("/volume1/private/task"))
    }

    func test后台任务空页停止继续分页() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"offset":20,"total":100,"tasks":[]}}"#)
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationBackgroundTask: capability(
                    DsmAPIName.fileStationBackgroundTask,
                    version: 3
                )
            ]),
            transport: transport
        )

        let page = try await repository.listBackgroundTasks(offset: 20, limit: 100)

        XCTAssertEqual(page.nextOffset, 20)
        XCTAssertFalse(page.hasMore)
    }

    func test三端共享Fixture兼容字符串数字和异常附加信息() async throws {
        let stringNumbers = try await pageFromFixture("synthetic-string-numbers")
        XCTAssertEqual(stringNumbers.total, 2)
        XCTAssertEqual(stringNumbers.items.count, 2)
        XCTAssertEqual(stringNumbers.items.first?.sizeBytes, 5)
        XCTAssertEqual(
            stringNumbers.items.first?.times?.modifiedAt,
            Date(timeIntervalSince1970: 1_700_000_000)
        )

        let missingAdditional = try await pageFromFixture("synthetic-missing-additional")
        XCTAssertEqual(missingAdditional.items.count, 1)
        XCTAssertEqual(missingAdditional.items.first?.isDirectory, false)

        let malformedAdditional = try await pageFromFixture("synthetic-malformed-additional")
        XCTAssertEqual(malformedAdditional.items.count, 2)
    }

    func test使用官方接口计算文件校验值且不在地址暴露路径() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(
                data: Data(#"{"success":true,"data":{"taskid":"md5-task"}}"#.utf8),
                statusCode: 200
            ),
            DsmHTTPResponse(
                data: Data(#"{"success":true,"data":{"finished":false}}"#.utf8),
                statusCode: 200
            ),
            DsmHTTPResponse(
                data: Data(#"{"success":true,"data":{"finished":true,"md5":"6336C5A59AA63DD2042783F88E15410A"}}"#.utf8),
                statusCode: 200
            )
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationMD5: capability(DsmAPIName.fileStationMD5, version: 2)
            ]),
            transport: transport
        )

        let checksum = try await repository.fileMD5(remotePath: "/共享/示例.zip")

        XCTAssertEqual(checksum, "6336c5a59aa63dd2042783f88e15410a")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requestParameter("method", in: requests[0]), "start")
        XCTAssertEqual(requestParameter("file_path", in: requests[0]), "/共享/示例.zip")
        XCTAssertEqual(requestParameter("method", in: requests[1]), "status")
        XCTAssertFalse(requests.contains { $0.url?.absoluteString.contains("/共享/示例.zip") == true })
    }

    private func pageFromFixture(_ fixtureID: String) async throws -> FilePage {
        var repositoryRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            repositoryRoot.deleteLastPathComponent()
        }
        let responseURL = repositoryRoot
            .appendingPathComponent("contracts/fixtures-redacted/file-station/list-folder")
            .appendingPathComponent(fixtureID)
            .appendingPathComponent("response.json")
        let response = DsmHTTPResponse(
            data: try Data(contentsOf: responseURL),
            statusCode: 200
        )
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationList: capability(DsmAPIName.fileStationList, version: 2)
            ]),
            transport: MockHTTPTransport(responses: [response])
        )
        return try await repository.listFolder(path: "/fixture", offset: 0, limit: 500)
    }

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

    func test当前账号共享访问分页去重并排除远程挂载() async throws {
        let transport = MockHTTPTransport(responses: [
            response(
                #"{"success":true,"data":{"offset":0,"total":4,"shares":[{"name":"资料","path":"/data","isdir":true,"additional":{"mount_point_type":"normal","perm":{"adv_right":{"read":true,"write":false,"delete":false}}}},{"name":"项目","path":"/projects","isdir":true,"additional":{"mount_point_type":"normal","perm":{"adv_right":{"read":true,"write":true,"delete":true}}}},{"name":"远程位置","path":"/remote","isdir":true,"additional":{"mount_point_type":"cifs","perm":{"adv_right":{"read":true,"write":true,"delete":true}}}}]}}"#
            ),
            response(
                #"{"success":true,"data":{"offset":3,"total":4,"shares":[{"name":"资料","path":"/data","isdir":true,"additional":{"mount_point_type":"normal","perm":{"adv_right":{"read":true,"write":true,"delete":false}}}}]}}"#
            )
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationList: capability(DsmAPIName.fileStationList, version: 2)
            ]),
            transport: transport
        )
        let accessRepository = FileStationShareAccessRepository(repository: repository)

        let directory = try await accessRepository.loadShareAccess()

        XCTAssertEqual(Set(directory.shares.map(\.name)), Set(["资料", "项目"]))
        XCTAssertEqual(directory.shares.count, 2)
        let dataShare = try XCTUnwrap(directory.shares.first { $0.name == "资料" })
        XCTAssertEqual(dataShare.accessLevel, .readWrite)
        XCTAssertFalse(dataShare.canDelete)
        let projectShare = try XCTUnwrap(directory.shares.first { $0.name == "项目" })
        XCTAssertEqual(projectShare.accessLevel, .readWrite)
        XCTAssertTrue(projectShare.canDelete)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requestParameter("method", in: requests[0]), "list_share")
        XCTAssertEqual(requestParameter("offset", in: requests[1]), "3")
    }

    func test目录列表容忍字符串分页字段和异常附加信息() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"offset":"0","total":"2","files":[{"name":"正常.jpg","path":"/photo/正常.jpg","isdir":false,"additional":[]},{"name":"视频.mp4","path":"/photo/视频.mp4","isdir":"0"}]}}"#.utf8
            ),
            statusCode: 200
        )
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationList: capability(DsmAPIName.fileStationList, version: 2)
            ]),
            transport: MockHTTPTransport(responses: [response])
        )

        let page = try await repository.listFolder(path: "/photo", offset: 0, limit: 100)

        XCTAssertEqual(page.items.map(\.name), ["正常.jpg", "视频.mp4"])
        XCTAssertEqual(page.offset, 0)
        XCTAssertEqual(page.total, 2)
    }

    func test虚拟文件夹先读取协议并按CIFSNFSISO分别请求() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"support_virtual_protocol":" cifs, NFS,iso,unknown "}}"#),
            response(#"{"success":true,"data":{"offset":0,"total":1,"folders":[{"name":"CIFS 资料","path":"/remote/shared","isdir":true,"additional":{"mount_point_type":"cifs"}}]}}"#),
            response(#"{"success":true,"data":{"offset":0,"total":1,"folders":[{"name":"NFS 资料","path":"/remote/shared","isdir":true,"additional":{"mount_point_type":"nfs"}}]}}"#),
            response(#"{"success":true,"data":{"offset":0,"total":1,"folders":[{"name":"ISO 映像","path":"/remote/shared","isdir":true,"additional":{"mount_point_type":"iso"}}]}}"#),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationInfo: capability(DsmAPIName.fileStationInfo, version: 2),
                DsmAPIName.fileStationVirtualFolder: capability(DsmAPIName.fileStationVirtualFolder, version: 2)
            ]),
            transport: transport
        )

        let page = try await repository.listVirtualFolders(offset: 0, limit: 100)

        XCTAssertEqual(page.total, 3)
        XCTAssertEqual(page.folders.count, 3)
        XCTAssertEqual(Set(page.folders.map(\.id)).count, 3)
        XCTAssertEqual(Set(page.folders.map(\.protocolType)), Set(FileVirtualProtocol.allCases))
        XCTAssertTrue(page.unavailableProtocols.isEmpty)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requestParameter("api", in: requests[0]), DsmAPIName.fileStationInfo)
        XCTAssertEqual(requestParameter("method", in: requests[0]), "get")
        XCTAssertEqual(requestParameter("version", in: requests[0]), "2")
        XCTAssertNil(requestParameter("additional", in: requests[0]))
        XCTAssertEqual(requests.dropFirst().compactMap { requestParameter("type", in: $0) }, ["cifs", "nfs", "iso"])
        XCTAssertFalse(requests.contains { requestParameter("type", in: $0) == "all" })
        for request in requests.dropFirst() {
            XCTAssertEqual(requestParameter("api", in: request), DsmAPIName.fileStationVirtualFolder)
            XCTAssertEqual(requestParameter("method", in: request), "list")
            XCTAssertEqual(requestParameter("version", in: request), "2")
            let encodedAdditional = try XCTUnwrap(requestParameter("additional", in: request))
            XCTAssertEqual(
                try JSONDecoder().decode([String].self, from: Data(encodedAdditional.utf8)),
                ["mount_point_type", "perm"]
            )
        }
    }

    func test虚拟文件夹非正分页大小会收敛为一条() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"support_virtual_protocol":"cifs"}}"#),
            response(#"{"success":true,"data":{"offset":0,"total":2,"folders":[{"name":"位置一","path":"/remote/one","isdir":true}]}}"#),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationInfo: capability(DsmAPIName.fileStationInfo, version: 2),
                DsmAPIName.fileStationVirtualFolder: capability(DsmAPIName.fileStationVirtualFolder, version: 2)
            ]),
            transport: transport
        )

        let page = try await repository.listVirtualFolders(offset: 0, limit: 0)

        XCTAssertEqual(page.folders.map(\.item.path), ["/remote/one"])
        XCTAssertTrue(page.hasMore)
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(requestParameter("limit", in: request), "1")
    }

    func test虚拟文件夹合并分页超过单次上限后仍能继续() async throws {
        let folderJSON: (Int) -> String = { index in
            let number = String(format: "%03d", index)
            return #"{"name":"位置 \#(number)","path":"/remote/item-\#(number)","isdir":true}"#
        }
        let firstPage = (0..<500).map(folderJSON).joined(separator: ",")
        let secondPage = (500..<502).map(folderJSON).joined(separator: ",")
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"support_virtual_protocol":"cifs"}}"#),
            response(#"{"success":true,"data":{"offset":0,"total":502,"folders":[\#(firstPage)]}}"#),
            response(#"{"success":true,"data":{"offset":500,"total":502,"folders":[\#(secondPage)]}}"#),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationInfo: capability(DsmAPIName.fileStationInfo, version: 2),
                DsmAPIName.fileStationVirtualFolder: capability(DsmAPIName.fileStationVirtualFolder, version: 2)
            ]),
            transport: transport
        )

        let page = try await repository.listVirtualFolders(offset: 501, limit: 1)

        XCTAssertEqual(page.folders.map(\.item.path), ["/remote/item-501"])
        XCTAssertEqual(page.total, 502)
        XCTAssertFalse(page.hasMore)
        XCTAssertFalse(page.isTruncated)
        let requests = await transport.recordedRequests().dropFirst()
        XCTAssertEqual(requests.compactMap { requestParameter("offset", in: $0) }, ["0", "500"])
        XCTAssertEqual(requests.compactMap { requestParameter("limit", in: $0) }, ["500", "2"])
    }

    func test虚拟文件夹部分协议失败仍返回成功结果() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"support_virtual_protocol":["cifs","nfs"]}}"#),
            response(#"{"success":false,"error":{"code":408}}"#),
            response(#"{"success":true,"data":{"offset":0,"total":1,"folders":[{"name":"NFS 资料","path":"/remote/nfs","isdir":true}]}}"#),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationInfo: capability(DsmAPIName.fileStationInfo, version: 2),
                DsmAPIName.fileStationVirtualFolder: capability(DsmAPIName.fileStationVirtualFolder, version: 2)
            ]),
            transport: transport
        )

        let page = try await repository.listVirtualFolders(offset: 0, limit: 100)

        XCTAssertEqual(page.folders.map(\.item.path), ["/remote/nfs"])
        XCTAssertEqual(page.folders.map(\.protocolType), [.nfs])
        XCTAssertEqual(page.unavailableProtocols, [.cifs])
    }

    func test虚拟文件夹全部协议失败时抛错() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"support_virtual_protocol":"cifs,nfs"}}"#),
            response(#"{"success":false,"error":{"code":408}}"#),
            response(#"{"success":false,"error":{"code":408}}"#),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationInfo: capability(DsmAPIName.fileStationInfo, version: 2),
                DsmAPIName.fileStationVirtualFolder: capability(DsmAPIName.fileStationVirtualFolder, version: 2)
            ]),
            transport: transport
        )

        do {
            _ = try await repository.listVirtualFolders(offset: 0, limit: 100)
            XCTFail("所有已宣告协议失败时不应返回空页")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.dropFirst().compactMap { requestParameter("type", in: $0) }, ["cifs", "nfs"])
    }

    func test批量详情使用V2百条分块去重并按首次输入顺序返回() async throws {
        let paths = (0...101).map { "/home/item-\($0)" }
        let input = [paths[2], paths[0], paths[2], paths[1]] + Array(paths[3...])
        let orderedUnique = [paths[2], paths[0], paths[1]] + Array(paths[3...])
        let firstChunk = Array(orderedUnique.prefix(100))
        let secondChunk = Array(orderedUnique.dropFirst(100))
        let fileJSON: (String) -> String = { path in
            let name = String(path.split(separator: "/").last ?? "")
            return #"{"name":"\#(name)","path":"\#(path)","isdir":false}"#
        }
        let firstResponseItems = firstChunk.reversed()
            .filter { $0 != paths[1] }
            .map(fileJSON)
            + [fileJSON("/home/foreign")]
        let secondResponseItems = secondChunk.reversed().map(fileJSON)
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"files":[\#(firstResponseItems.joined(separator: ","))]}}"#),
            response(#"{"success":true,"data":{"files":[\#(secondResponseItems.joined(separator: ","))]}}"#),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationList: capability(DsmAPIName.fileStationList, version: 2)
            ]),
            transport: transport
        )

        let items = try await repository.getInfo(paths: input)

        XCTAssertEqual(items.map(\.path), orderedUnique.filter { $0 != paths[1] })
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { requestParameter("method", in: $0) == "getinfo" })
        XCTAssertTrue(requests.allSatisfy { requestParameter("version", in: $0) == "2" })
        let requestedChunks = try requests.map { request -> [String] in
            let encodedPaths = try XCTUnwrap(requestParameter("path", in: request))
            return try JSONDecoder().decode([String].self, from: Data(encodedPaths.utf8))
        }
        XCTAssertEqual(requestedChunks.map(\.count), [100, 2])
        XCTAssertEqual(requestedChunks.flatMap { $0 }, orderedUnique)
        XCTAssertFalse(requestedChunks.flatMap { $0 }.contains("/home/foreign"))
        for request in requests {
            let encodedAdditional = try XCTUnwrap(requestParameter("additional", in: request))
            XCTAssertEqual(
                try JSONDecoder().decode([String].self, from: Data(encodedAdditional.utf8)),
                ["size", "owner", "time", "perm", "type", "mount_point_type"]
            )
        }
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
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-4")
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
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("shared.18b4f39557c377e4")
            )
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

    func test分段下载失败后保留已完成分片供下次续传() async throws {
        let chunkSize = 8 * 1_024 * 1_024
        let response = DsmHTTPResponse(
            data: Data(repeating: 0x41, count: chunkSize),
            statusCode: 206,
            headers: ["content-type": "application/octet-stream"]
        )
        let transport = MockHTTPTransport(responses: [response])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDownload: capability(
                    DsmAPIName.fileStationDownload,
                    version: 2
                )
            ]),
            transport: transport
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "DsmFileRepositoryTests-Interrupted-\(UUID().uuidString).bin"
            )
        let expectedSize = Int64(chunkSize + 1)
        let identity = "\(repository.profileID.uuidString)|/projects/large.bin|\(expectedSize)"
        let digest = SHA256.hash(data: Data(identity.utf8))
        let suffix = digest.prefix(8).map {
            String(format: "%02x", $0)
        }.joined()
        let partURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                ".\(destination.lastPathComponent).\(suffix).lanstash.part"
            )
        defer {
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.removeItem(at: partURL)
        }

        do {
            try await repository.download(
                remotePath: "/projects/large.bin",
                to: destination,
                expectedSize: expectedSize
            ) { _, _ in }
            XCTFail("第二个分段没有响应时应失败")
        } catch {
            XCTAssertEqual(
                try partURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                chunkSize
            )
        }

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests[0].value(forHTTPHeaderField: "Range"),
            "bytes=0-\(chunkSize - 1)"
        )
        XCTAssertEqual(
            requests[1].value(forHTTPHeaderField: "Range"),
            "bytes=\(chunkSize)-\(chunkSize)"
        )
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
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("shared.6c7c8cc0b215216b")
            )
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
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("shared.074152c919ec8351")
            )
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
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("shared.71de0e6207d12dc7")
            )
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

    func test递归搜索完成后继续读取剩余分页() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(data: Data(#"{"success":true,"data":{"taskid":"task-2"}}"#.utf8), statusCode: 200),
            DsmHTTPResponse(data: Data(#"{"success":true,"data":{"offset":0,"total":2,"finished":true,"files":[{"name":"一.jpg","path":"/photo/一.jpg","isdir":false}]}}"#.utf8), statusCode: 200),
            DsmHTTPResponse(data: Data(#"{"success":true,"data":{"offset":1,"total":2,"finished":true,"files":[{"name":"二.jpg","path":"/photo/二.jpg","isdir":false}]}}"#.utf8), statusCode: 200),
            DsmHTTPResponse(data: Data(#"{"success":true}"#.utf8), statusCode: 200)
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationSearch: capability(DsmAPIName.fileStationSearch, version: 2)
            ]),
            transport: transport
        )

        let results = try await repository.search(folderPath: "/photo", query: "*")

        XCTAssertEqual(results.map(\.name), ["一.jpg", "二.jpg"])
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestParameter("offset", in: requests[2]), "1")
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

    func test收藏结果在写后回读一致时确认成功() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(
                data: Data(#"{"success":true}"#.utf8),
                statusCode: 200
            ),
            DsmHTTPResponse(
                data: Data(
                    #"{"success":true,"data":{"favorites":[{"name":"文档","path":"/home/docs"}]}}"#
                        .utf8
                ),
                statusCode: 200
            ),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationFavorite: capability(
                    DsmAPIName.fileStationFavorite,
                    version: 2
                ),
            ]),
            transport: transport
        )

        let result = try await repository.addFavoriteResult(
            path: "/home/docs",
            name: "文档"
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertTrue(result.submitted)
        XCTAssertFalse(result.requiresRefresh)
        XCTAssertEqual(result.counts.succeeded, 1)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(
            requests.compactMap { requestParameter("method", in: $0) },
            ["add", "list"]
        )
    }

    func test收藏被服务明确拒绝时返回权限不足() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(
                data: Data(#"{"success":false,"error":{"code":105}}"#.utf8),
                statusCode: 200
            ),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationFavorite: capability(
                    DsmAPIName.fileStationFavorite,
                    version: 2
                ),
            ]),
            transport: transport
        )

        let result = try await repository.addFavoriteResult(
            path: "/home/docs",
            name: "文档"
        )

        XCTAssertEqual(result.status, .permissionDenied)
        XCTAssertTrue(result.submitted)
        XCTAssertEqual(result.counts.failed, 1)
        XCTAssertEqual(result.errorCategory, .permission)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func test收藏提交时网络中断不会伪装成明确失败() async throws {
        let transport = MockHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationFavorite: capability(
                    DsmAPIName.fileStationFavorite,
                    version: 2
                ),
            ]),
            transport: transport
        )

        let result = try await repository.addFavoriteResult(
            path: "/home/docs",
            name: "文档"
        )

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.submitted)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.counts.unknown, 1)
        XCTAssertEqual(result.errorCategory, .network)
    }

    func test收藏提交成功但回读失败时要求刷新而不自动重试() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(
                DsmHTTPResponse(
                    data: Data(#"{"success":true}"#.utf8),
                    statusCode: 200
                )
            ),
            .urlError(.timedOut),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationFavorite: capability(
                    DsmAPIName.fileStationFavorite,
                    version: 2
                ),
            ]),
            transport: transport
        )

        let result = try await repository.addFavoriteResult(
            path: "/home/docs",
            name: "文档"
        )

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.counts.unknown, 1)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
    }

    func test收藏回读明确缺少目标时返回确认失败() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(
                data: Data(#"{"success":true}"#.utf8),
                statusCode: 200
            ),
            DsmHTTPResponse(
                data: Data(#"{"success":true,"data":{"favorites":[]}}"#.utf8),
                statusCode: 200
            ),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationFavorite: capability(
                    DsmAPIName.fileStationFavorite,
                    version: 2
                ),
            ]),
            transport: transport
        )

        let result = try await repository.addFavoriteResult(
            path: "/home/docs",
            name: "文档"
        )

        XCTAssertEqual(result.status, .confirmedFailure)
        XCTAssertEqual(result.counts.failed, 1)
        XCTAssertFalse(result.requiresRefresh)
    }

    func test收藏在提交前取消时不发出请求() async throws {
        let transport = MockHTTPTransport(responses: [])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationFavorite: capability(
                    DsmAPIName.fileStationFavorite,
                    version: 2
                ),
            ]),
            transport: transport
        )

        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await repository.addFavoriteResult(
                path: "/home/docs",
                name: "文档"
            )
        }
        let result = try await task.value

        XCTAssertEqual(result.status, .cancelledBeforeSubmission)
        XCTAssertFalse(result.submitted)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 0)
    }

    func test删除任务完成且逐项回读不存在时确认成功() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"taskid":"delete-task"}}"#),
            response(#"{"success":true,"data":{"finished":true}}"#),
            response(#"{"success":true,"data":{"files":[]}}"#),
        ])
        let repository = try makeDeleteRepository(transport: transport)

        let result = try await repository.deleteResult(
            paths: ["/home/docs/a.txt"],
            progress: { _, _ in }
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertEqual(result.counts.succeeded, 1)
        XCTAssertFalse(result.requiresRefresh)
        let methods = await transport.recordedRequests().compactMap {
            requestParameter("method", in: $0)
        }
        XCTAssertEqual(methods, ["start", "status", "getinfo"])
    }

    func test删除被服务明确拒绝时返回权限不足() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":false,"error":{"code":105}}"#),
        ])
        let repository = try makeDeleteRepository(transport: transport)

        let result = try await repository.deleteResult(
            paths: ["/home/docs/a.txt"],
            progress: { _, _ in }
        )

        XCTAssertEqual(result.status, .permissionDenied)
        XCTAssertEqual(result.counts.failed, 1)
        XCTAssertEqual(result.errorCategory, .permission)
        XCTAssertFalse(result.requiresRefresh)
    }

    func test删除提交时连接中断保留未确认语义() async throws {
        let transport = MockHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let repository = try makeDeleteRepository(transport: transport)

        let result = try await repository.deleteResult(
            paths: ["/home/docs/a.txt"],
            progress: { _, _ in }
        )

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertEqual(result.counts.unknown, 1)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.errorCategory, .network)
    }

    func test删除任务完成但回读超时时要求刷新() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"taskid":"delete-task"}}"#)),
            .response(response(#"{"success":true,"data":{"finished":true}}"#)),
            .urlError(.timedOut),
        ])
        let repository = try makeDeleteRepository(transport: transport)

        let result = try await repository.deleteResult(
            paths: ["/home/docs/a.txt"],
            progress: { _, _ in }
        )

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertEqual(result.counts.unknown, 1)
        XCTAssertTrue(result.requiresRefresh)
    }

    func test批量删除逐项回读不一致时返回部分成功() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"taskid":"delete-task"}}"#),
            response(#"{"success":true,"data":{"finished":true}}"#),
            response(#"{"success":true,"data":{"files":[]}}"#),
            response(
                #"{"success":true,"data":{"files":[{"name":"b.txt","path":"/home/docs/b.txt","isdir":false}]}}"#
            ),
        ])
        let repository = try makeDeleteRepository(transport: transport)

        let result = try await repository.deleteResult(
            paths: ["/home/docs/a.txt", "/home/docs/b.txt"],
            progress: { _, _ in }
        )

        XCTAssertEqual(result.status, .partialSuccess)
        XCTAssertEqual(result.counts.succeeded, 1)
        XCTAssertEqual(result.counts.failed, 1)
        XCTAssertEqual(result.counts.unknown, 0)
        XCTAssertTrue(result.requiresRefresh)
    }

    func test删除在提交前取消时不发出请求() async throws {
        let transport = MockHTTPTransport(responses: [])
        let repository = try makeDeleteRepository(transport: transport)

        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await repository.deleteResult(
                paths: ["/home/docs/a.txt"],
                progress: { _, _ in }
            )
        }
        let result = try await task.value

        XCTAssertEqual(result.status, .cancelledBeforeSubmission)
        XCTAssertFalse(result.submitted)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 0)
    }

    func test删除提交后取消会请求停止并要求刷新() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"taskid":"delete-task"}}"#)),
            .waitUntilCancelled,
            .response(response(#"{"success":true}"#)),
        ])
        let repository = try makeDeleteRepository(transport: transport)
        let task = Task {
            try await repository.deleteResult(
                paths: ["/home/docs/a.txt"],
                progress: { _, _ in }
            )
        }
        while await transport.recordedRequests().count < 2 {
            await Task.yield()
        }

        task.cancel()
        let result = try await task.value

        XCTAssertEqual(result.status, .cancellationRequestedAfterSubmission)
        XCTAssertEqual(result.counts.unknown, 1)
        XCTAssertTrue(result.requiresRefresh)
        let methods = await transport.recordedRequests().compactMap {
            requestParameter("method", in: $0)
        }
        XCTAssertEqual(methods, ["start", "status", "stop"])
    }

    func test父目录删除进行中时拒绝子路径重复提交() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"taskid":"delete-task"}}"#)),
            .waitUntilCancelled,
            .response(response(#"{"success":true}"#)),
        ])
        let repository = try makeDeleteRepository(transport: transport)
        let firstTask = Task {
            try await repository.deleteResult(
                paths: ["/home/docs"],
                progress: { _, _ in }
            )
        }
        while await transport.recordedRequests().count < 2 {
            await Task.yield()
        }

        let duplicate = try await repository.deleteResult(
            paths: ["/home/docs/a.txt"],
            progress: { _, _ in }
        )
        firstTask.cancel()
        _ = try await firstTask.value

        XCTAssertEqual(duplicate.status, .confirmedFailure)
        XCTAssertFalse(duplicate.submitted)
        XCTAssertEqual(duplicate.errorCategory, .conflict)
    }

    func test删除拒绝根目录和上级路径且不发出请求() async throws {
        let transport = MockHTTPTransport(responses: [])
        let repository = try makeDeleteRepository(transport: transport)

        let result = try await repository.deleteResult(
            paths: ["/home/../"],
            progress: { _, _ in }
        )

        XCTAssertEqual(result.status, .confirmedFailure)
        XCTAssertFalse(result.submitted)
        XCTAssertEqual(result.errorCategory, .validation)
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func test容量只汇总当前账号可见卷并去除重复共享() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"shares":[{"name":"home","path":"/home","isdir":true,"additional":{"real_path":"/volume1/homes/tester","volume_status":{"totalspace":"1000","freespace":"250"}}},{"name":"projects","path":"/projects","isdir":true,"additional":{"real_path":"/volume1/projects","volume_status":{"total_space":1000,"free_space":250}}},{"name":"archive","path":"/archive","isdir":true,"additional":{"real_path":"/volume2/archive","volume_status":{"total":2000,"available":800}}}]}}"#.utf8
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

        let loadedSummary = try await repository.storageSpaceSummary()
        let summary = try XCTUnwrap(loadedSummary)

        XCTAssertEqual(summary.totalBytes, 3_000)
        XCTAssertEqual(summary.remainingBytes, 1_050)
        XCTAssertEqual(summary.usedBytes, 1_950)
        XCTAssertEqual(summary.volumeCount, 2)
    }

    func test远程挂载创建后复查结果且密码不进入URL() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(data: Data(#"{"success":true}"#.utf8), statusCode: 200),
            mountedInfo(path: "/home/远程资料", type: "cifs")
        ])
        let repository = try makeRemoteMountRepository(transport: transport)

        try await repository.createRemoteMount(
            RemoteMountConfiguration(
                protocolType: .smb,
                server: "192.0.2.20",
                remotePath: "资料",
                mountPoint: "/home/远程资料",
                username: "tester",
                password: "REDACTED_PASSWORD",
                domain: "WORKGROUP",
                readOnly: true
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map { requestParameter("method", in: $0) }, ["mount_remote", "getinfo"])
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requestParameter("mount_point", in: request), "/home/远程资料")
        XCTAssertEqual(requestParameter("read_only", in: request), "true")
        XCTAssertEqual(requestParameter("password", in: request), "REDACTED_PASSWORD")
        XCTAssertFalse(request.url?.absoluteString.contains("REDACTED_PASSWORD") == true)
    }

    func test远程挂载修改会先确认新位置再断开旧位置() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(data: Data(#"{"success":true}"#.utf8), statusCode: 200),
            mountedInfo(path: "/home/新远程资料", type: "nfs"),
            DsmHTTPResponse(data: Data(#"{"success":true}"#.utf8), statusCode: 200),
            mountedInfo(path: "/home/旧远程资料", type: "normal")
        ])
        let repository = try makeRemoteMountRepository(transport: transport)

        try await repository.updateRemoteMount(
            existingMountPoint: "/home/旧远程资料",
            configuration: RemoteMountConfiguration(
                protocolType: .nfs,
                server: "192.0.2.30",
                remotePath: "exports/media",
                mountPoint: "/home/新远程资料"
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(
            requests.map { requestParameter("method", in: $0) },
            ["mount_remote", "getinfo", "unmount", "getinfo"]
        )
    }

    func test删除远程挂载只断开并复查结果() async throws {
        let transport = MockHTTPTransport(responses: [
            DsmHTTPResponse(data: Data(#"{"success":true}"#.utf8), statusCode: 200),
            mountedInfo(path: "/home/远程资料", type: "normal")
        ])
        let repository = try makeRemoteMountRepository(transport: transport)

        try await repository.removeRemoteMount(mountPoint: "/home/远程资料")

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map { requestParameter("method", in: $0) }, ["unmount", "getinfo"])
        XCTAssertEqual(requestParameter("mount_point", in: try XCTUnwrap(requests.first)), "/home/远程资料")
    }

    private func mountedInfo(path: String, type: String) -> DsmHTTPResponse {
        let body = """
        {"success":true,"data":{"files":[{"name":"\(URL(fileURLWithPath: path).lastPathComponent)","path":"\(path)","isdir":true,"additional":{"mount_point_type":"\(type)"}}]}}
        """
        return DsmHTTPResponse(data: Data(body.utf8), statusCode: 200)
    }

    private func requestParameter(_ name: String, in request: URLRequest) -> String? {
        if let url = request.url,
           let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value {
            return value
        }
        guard let body = request.httpBody.flatMap({ String(data: $0, encoding: .utf8) }) else {
            return nil
        }
        return URLComponents(string: "?\(body)")?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    private func makeRemoteMountRepository(transport: MockHTTPTransport) throws -> DsmFileRepository {
        try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationList: capability(DsmAPIName.fileStationList, version: 2),
                DsmAPIName.fileStationMount: capability(DsmAPIName.fileStationMount, version: 1)
            ]),
            transport: transport
        )
    }

    private func makeDeleteRepository(
        transport: MockHTTPTransport
    ) throws -> DsmFileRepository {
        try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationDelete: capability(
                    DsmAPIName.fileStationDelete,
                    version: 2
                ),
                DsmAPIName.fileStationList: capability(
                    DsmAPIName.fileStationList,
                    version: 2
                ),
            ]),
            transport: transport
        )
    }

    private func response(_ body: String) -> DsmHTTPResponse {
        DsmHTTPResponse(data: Data(body.utf8), statusCode: 200)
    }

    private func makeRepository(
        capabilities: CapabilitySet,
        transport: MockHTTPTransport,
        directorySizePollingPolicy: DirectorySizePollingPolicy = .production
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
            transport: transport,
            directorySizePollingPolicy: directorySizePollingPolicy
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

import DsmCore
import Foundation
import XCTest
@testable import DsmNetwork

final class DsmCapabilityDiscoveryTests: XCTestCase {
    func test发现并协商登录能力() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.API.Auth":{"path":"/webapi/entry.cgi","minVersion":3,"maxVersion":7,"requestFormat":"FORM"}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        let result = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [DsmAPIName.authentication]
        ).discover()

        let auth = try XCTUnwrap(result[DsmAPIName.authentication])
        XCTAssertEqual(auth.path, "entry.cgi")
        XCTAssertEqual(auth.selectedVersion, 6)
        XCTAssertFalse(auth.verified)
    }

    func test入口明确不存在时回退旧查询入口() async throws {
        let success = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.API.Auth":{"path":"auth.cgi","minVersion":3,"maxVersion":6}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(
            responses: [DsmHTTPResponse(data: Data(), statusCode: 404), success]
        )
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        _ = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [DsmAPIName.authentication]
        ).discover()

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.url?.lastPathComponent, "query.cgi")
    }

    func test系统进程接口仅协商保守的V1范围() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.Core.System.Process":{"path":"entry.cgi","minVersion":1,"maxVersion":3},"SYNO.Core.System.ProcessGroup":{"path":"entry.cgi","minVersion":2,"maxVersion":3}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        let result = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [
                DsmAPIName.coreSystemProcess,
                DsmAPIName.coreSystemProcessGroup
            ]
        ).discover()

        XCTAssertEqual(result[DsmAPIName.coreSystemProcess]?.selectedVersion, 1)
        XCTAssertNil(result[DsmAPIName.coreSystemProcessGroup]?.selectedVersion)
    }

    func test电源计划接口仅协商保守的V1范围() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.Core.Hardware.PowerSchedule":{"path":"entry.cgi","minVersion":1,"maxVersion":3}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        let result = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [DsmAPIName.coreHardwarePowerSchedule]
        ).discover()

        XCTAssertEqual(
            result[DsmAPIName.coreHardwarePowerSchedule]?.selectedVersion,
            1
        )
    }

    func test外接存储接口仅协商保守的V1范围() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.Core.ExternalDevice.Storage.USB":{"path":"entry.cgi","minVersion":1,"maxVersion":3},"SYNO.Core.ExternalDevice.Storage.eSATA":{"path":"entry.cgi","minVersion":2,"maxVersion":3}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        let result = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [
                DsmAPIName.coreExternalStorageUSB,
                DsmAPIName.coreExternalStorageESATA
            ]
        ).discover()

        XCTAssertEqual(result[DsmAPIName.coreExternalStorageUSB]?.selectedVersion, 1)
        XCTAssertNil(result[DsmAPIName.coreExternalStorageESATA]?.selectedVersion)
    }

    func testZRAM接口仅协商保守的V1范围() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.Core.Hardware.ZRAM":{"path":"entry.cgi","minVersion":1,"maxVersion":3}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        let result = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [DsmAPIName.coreHardwareZRAM]
        ).discover()

        XCTAssertEqual(result[DsmAPIName.coreHardwareZRAM]?.selectedVersion, 1)
    }

    func testFileStation后台任务接口仅协商V3范围() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.FileStation.BackgroundTask":{"path":"entry.cgi","minVersion":1,"maxVersion":4}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        let result = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [DsmAPIName.fileStationBackgroundTask]
        ).discover()

        XCTAssertEqual(result[DsmAPIName.fileStationBackgroundTask]?.selectedVersion, 3)
    }

    func testFileStation后台任务接口拒绝不含V3的版本范围() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.FileStation.BackgroundTask":{"path":"entry.cgi","minVersion":1,"maxVersion":2}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        let result = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [DsmAPIName.fileStationBackgroundTask]
        ).discover()

        XCTAssertNil(result[DsmAPIName.fileStationBackgroundTask]?.selectedVersion)
    }

    func testFileStation目录大小接口仅协商V2范围() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.FileStation.DirSize":{"path":"entry.cgi","minVersion":1,"maxVersion":4}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        let result = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [DsmAPIName.fileStationDirSize]
        ).discover()

        XCTAssertEqual(result[DsmAPIName.fileStationDirSize]?.selectedVersion, 2)
    }

    func testFileStation目录大小接口拒绝不含V2的版本范围() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.FileStation.DirSize":{"path":"entry.cgi","minVersion":3,"maxVersion":4}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        let result = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [DsmAPIName.fileStationDirSize]
        ).discover()

        XCTAssertNil(result[DsmAPIName.fileStationDirSize]?.selectedVersion)
    }

    func testFileStation虚拟文件夹接口仅协商V2范围() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.FileStation.VirtualFolder":{"path":"entry.cgi","minVersion":1,"maxVersion":4}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        let result = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [DsmAPIName.fileStationVirtualFolder]
        ).discover()

        XCTAssertEqual(result[DsmAPIName.fileStationVirtualFolder]?.selectedVersion, 2)
    }

    func testFileStation虚拟文件夹接口拒绝不含V2的版本范围() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.FileStation.VirtualFolder":{"path":"entry.cgi","minVersion":1,"maxVersion":1}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        let result = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [DsmAPIName.fileStationVirtualFolder]
        ).discover()

        XCTAssertNil(result[DsmAPIName.fileStationVirtualFolder]?.selectedVersion)
    }
}

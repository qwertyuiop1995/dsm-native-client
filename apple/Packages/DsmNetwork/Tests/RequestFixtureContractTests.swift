import DsmCore
import Foundation
import XCTest
@testable import DsmNetwork

final class RequestFixtureContractTests: XCTestCase {
    func test删除请求与共享Fixture一致() throws {
        let fixture = try loadFixture(
            "file-station/delete/synthetic-task/request.json"
        )
        let request = try DsmRequestBuilder.build(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            path: fixture.api.resolvedPath,
            api: fixture.api.name,
            version: fixture.api.resolvedVersion,
            method: fixture.api.method,
            requestFormat: .form,
            parameters: [
                "path": .stringArray(["<synthetic-path>"]),
                "recursive": .boolean(true),
                "accurate_progress": .boolean(true),
            ],
            credential: testCredential
        )

        try assertFormRequest(request, matches: fixture)
    }

    func test移动请求与共享Fixture一致() throws {
        let fixture = try loadFixture(
            "file-station/move/synthetic-task/request.json"
        )
        let request = try DsmRequestBuilder.build(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            path: fixture.api.resolvedPath,
            api: fixture.api.name,
            version: fixture.api.resolvedVersion,
            method: fixture.api.method,
            requestFormat: .form,
            parameters: [
                "path": .stringArray(["<synthetic-path>"]),
                "dest_folder_path": .string("<synthetic-destination>"),
                "remove_src": .boolean(true),
                "overwrite": .boolean(true),
                "accurate_progress": .boolean(true),
            ],
            credential: testCredential
        )

        try assertFormRequest(request, matches: fixture)
    }

    func test覆盖上传请求与共享Fixture一致() async throws {
        let fixture = try loadFixture(
            "file-station/upload/synthetic-overwrite/request.json"
        )
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
        ])
        let repository = try makeRepository(
            capabilities: CapabilitySet([
                DsmAPIName.fileStationUpload: capability(
                    DsmAPIName.fileStationUpload,
                    version: 2
                ),
                DsmAPIName.fileStationCheckPermission: capability(
                    DsmAPIName.fileStationCheckPermission,
                    version: 1
                ),
            ]),
            transport: transport
        )
        let localFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("synthetic-upload.bin")
        try Data("synthetic".utf8).write(to: localFile)
        defer { try? FileManager.default.removeItem(at: localFile) }

        try await repository.upload(
            localURL: localFile,
            to: "<synthetic-destination>",
            overwrite: true
        ) { _, _ in }

        let requests = await transport.recordedRequests()
        let uploadRequest = try XCTUnwrap(requests.last)
        let bodies = await transport.recordedUploadBodies()
        let uploadBody = try XCTUnwrap(bodies.last)
        try assertMultipartRequest(
            uploadRequest,
            body: uploadBody,
            matches: fixture
        )
    }

    func test账号创建请求与共享Fixture一致且不保存密码值() async throws {
        let fixture = try loadFixture(
            "users/create/synthetic-account/request.json"
        )
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true}"#),
        ])
        let repository = try makeAdministrationRepository(transport: transport)

        try await repository.saveAccount(
            NasAccountDraft(
                name: "<synthetic-account>",
                description: "<synthetic-description>",
                email: "<synthetic-email>",
                password: "SYNTHETIC_EPHEMERAL_SECRET",
                passwordConfirmation: "SYNTHETIC_EPHEMERAL_SECRET"
            )
        )

        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        try assertFormRequest(request, matches: fixture)
        XCTAssertFalse(
            request.url?.absoluteString.contains("SYNTHETIC_EPHEMERAL_SECRET")
                == true
        )
    }

    func test账号删除请求与共享Fixture一致() async throws {
        let fixture = try loadFixture(
            "users/delete/synthetic-account/request.json"
        )
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true}"#),
        ])
        let repository = try makeAdministrationRepository(transport: transport)

        try await repository.deleteAccount(name: "<synthetic-account>")

        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        try assertFormRequest(request, matches: fixture)
    }

    func test群组删除请求与共享Fixture一致() async throws {
        let fixture = try loadFixture(
            "groups/delete/synthetic-group/request.json"
        )
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true}"#),
        ])
        let repository = try makeAdministrationRepository(
            apiNames: [DsmAPIName.coreGroup],
            transport: transport
        )

        try await repository.deleteGroup(name: "<synthetic-group>")

        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        try assertFormRequest(request, matches: fixture)
    }

    func test套件卸载请求与共享Fixture一致() async throws {
        let fixture = try loadFixture(
            "packages/uninstall/synthetic-package/request.json"
        )
        let transport = MockHTTPTransport(responses: [
            response(
                #"{"success":true,"data":{"packages":[{"id":"<synthetic-package>","name":"Synthetic Package","version":"1.0","additional":{"status":"stopped","dsm_apps":"<synthetic-app-one> <synthetic-app-two>","ctl_uninstall":true,"available_operation":["uninstall"]}}]}}"#
            ),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
        ])
        let repository = try makePackageAdministrationRepository(
            transport: transport
        )
        _ = try await repository.loadPackages()

        try await repository.controlPackage(
            id: "<synthetic-package>",
            action: .uninstall
        )

        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.last)
        try assertFormRequest(request, matches: fixture)
    }

    func test容器删除请求与共享Fixture一致() async throws {
        let fixture = try loadFixture(
            "container-manager/delete/synthetic-container/request.json"
        )
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"containers":[]}}"#),
        ])
        let repository = try makeServiceManagementRepository(
            apiNames: [DsmAPIName.dockerContainer],
            transport: transport
        )

        try await repository.deleteContainers(ids: ["<synthetic-container>"])

        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        try assertFormRequest(request, matches: fixture)
    }

    func test虚拟机删除请求与共享Fixture一致() async throws {
        let fixture = try loadFixture(
            "vmm/delete/synthetic-virtual-machine/request.json"
        )
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"guests":[]}}"#),
        ])
        let repository = try makeServiceManagementRepository(
            apiNames: [DsmAPIName.virtualizationAPIGuest],
            transport: transport
        )

        try await repository.deleteVirtualMachines(
            ids: ["<synthetic-virtual-machine>"]
        )

        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        try assertFormRequest(request, matches: fixture)
    }

    func test服务子资源删除请求与共享Fixture一致() throws {
        let cases: [
            (
                path: String,
                format: DsmRequestFormat,
                parameters: [String: DsmParameterValue]
            )
        ] = [
            (
                "download-station/delete/synthetic-task/request.json",
                .form,
                [
                    "id": .string("<synthetic-download-task>"),
                    "force_complete": .boolean(true),
                ]
            ),
            (
                "container-manager/delete-image/synthetic-image/request.json",
                .form,
                ["id": .string("<synthetic-container-image>")]
            ),
            (
                "container-manager/delete-network/synthetic-network/request.json",
                .form,
                ["id": .string("<synthetic-container-network>")]
            ),
            (
                "vmm/delete-image/synthetic-image/request.json",
                .form,
                ["image_id": .string("<synthetic-virtual-machine-image>")]
            ),
            (
                "vmm/delete-network/synthetic-network/request.json",
                .json,
                ["network_id": .string("<synthetic-virtual-machine-network>")]
            ),
        ]

        for item in cases {
            let fixture = try loadFixture(item.path)
            let request = try DsmRequestBuilder.build(
                baseURL: try XCTUnwrap(
                    URL(string: "https://nas.example.invalid:5001")
                ),
                path: fixture.api.resolvedPath,
                api: fixture.api.name,
                version: fixture.api.resolvedVersion,
                method: fixture.api.method,
                requestFormat: item.format,
                parameters: item.parameters,
                credential: testCredential
            )

            try assertFormRequest(request, matches: fixture)
        }
    }

    func test远程访问复合请求与共享Fixture一致() async throws {
        let fixtures = try [
            loadFixture("network/set-relay/synthetic-setting/request.json"),
            loadFixture(
                "network/set-router-configuration/synthetic-setting/request.json"
            )
        ]
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"relay_enabled":true}}"#),
            response(#"{"success":true,"data":{"enabled":false}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"relay_enabled":false}}"#),
            response(#"{"success":true,"data":{"enabled":true}}"#)
        ])
        let repository = try makeAdministrationRepository(
            apiNames: [
                DsmAPIName.coreQuickConnect,
                DsmAPIName.coreQuickConnectUPnP
            ],
            transport: transport
        )

        let result = try await repository.saveRemoteAccessSettingsResult(
            NasRemoteAccessSettings(
                isRelayEnabled: false,
                isRouterConfigurationEnabled: true,
                canDisableRelay: true
            )
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 6)
        for (request, fixture) in zip(requests[2...3], fixtures) {
            try assertFormRequest(request, matches: fixture)
        }
    }

    func test文件服务复合请求与共享Fixture一致() async throws {
        let fixtures = try [
            loadFixture(
                "file-services/set-smb/synthetic-settings/request.json"
            ),
            loadFixture(
                "file-services/set-nfs/synthetic-settings/request.json"
            ),
            loadFixture(
                "file-services/set-ftp/synthetic-settings/request.json"
            ),
            loadFixture(
                "file-services/set-sftp/synthetic-settings/request.json"
            ),
            loadFixture(
                "file-services/set-web-discovery/synthetic-settings/request.json"
            ),
            loadFixture(
                "file-services/set-time-machine/synthetic-settings/request.json"
            )
        ]
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"enable_samba":false}}"#),
            response(#"{"success":true,"data":{"enable_nfs":false}}"#),
            response(#"{"success":true,"data":{"enable_ftp":false,"enable_ftps":false,"portnum":21}}"#),
            response(#"{"success":true,"data":{"enable":false,"portnum":22}}"#),
            response(#"{"success":true,"data":{"enable_ssdp":false,"enable_avahi":true}}"#),
            response(#"{"success":true,"data":{"enable_smb_time_machine":false}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"enable_samba":true}}"#),
            response(#"{"success":true,"data":{"enable_nfs":true}}"#),
            response(#"{"success":true,"data":{"enable_ftp":true,"enable_ftps":true,"portnum":2121}}"#),
            response(#"{"success":true,"data":{"enable":true,"portnum":2222}}"#),
            response(#"{"success":true,"data":{"enable_ssdp":true,"enable_avahi":false}}"#),
            response(#"{"success":true,"data":{"enable_smb_time_machine":true}}"#)
        ])
        let repository = try makeAdministrationRepository(
            apiNames: [
                DsmAPIName.coreFileServiceSMB,
                DsmAPIName.coreFileServiceNFS,
                DsmAPIName.coreFileServiceFTP,
                DsmAPIName.coreFileServiceSFTP,
                DsmAPIName.coreWebDSM,
                DsmAPIName.coreFileServiceDiscovery
            ],
            transport: transport
        )

        let result = try await repository.saveFileServiceSettingsResult(
            NasFileServiceSettings(
                isSMBEnabled: true,
                isNFSEnabled: true,
                isFTPEnabled: true,
                isFTPSEnabled: true,
                ftpPort: 2_121,
                isSFTPEnabled: true,
                sftpPort: 2_222,
                isSSDPEnabled: true,
                isBonjourEnabled: false,
                isSMBTimeMachineEnabled: true
            )
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertEqual(
            result.counts,
            try MutationResultCounts(succeeded: 6, failed: 0, unknown: 0)
        )
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 18)
        for (request, fixture) in zip(requests[6...11], fixtures) {
            try assertFormRequest(request, matches: fixture)
        }
    }

    func test远程终端请求与共享Fixture一致() async throws {
        let fixture = try loadFixture(
            "terminal/set-settings/synthetic-settings/request.json"
        )
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"enable_ssh":false,"enable_telnet":false,"ssh_port":22}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"enable_ssh":true,"enable_telnet":true,"ssh_port":2222}}"#)
        ])
        let repository = try makeAdministrationRepository(
            apiNames: [DsmAPIName.coreTerminal],
            transport: transport
        )

        let result = try await repository.saveTerminalSettingsResult(
            NasTerminalSettings(
                isSSHEnabled: true,
                isTelnetEnabled: true,
                sshPort: 2_222
            )
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        try assertFormRequest(requests[1], matches: fixture)
    }

    func test互联网代理请求与共享Fixture一致() async throws {
        let fixture = try loadFixture(
            "network/set-proxy/synthetic-settings/request.json"
        )
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"enable":false,"http_host":"","http_port":8080}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"enable":true,"http_host":"proxy.example.invalid","http_port":3128}}"#)
        ])
        let repository = try makeAdministrationRepository(
            apiNames: [DsmAPIName.coreNetworkProxy],
            transport: transport
        )

        let result = try await repository.saveProxySettingsResult(
            NasProxySettings(
                isEnabled: true,
                host: "proxy.example.invalid",
                port: 3_128
            )
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        try assertFormRequest(requests[1], matches: fixture)
    }

    func test物理网卡设置请求与共享Fixture一致() async throws {
        let fixture = try loadFixture(
            "network/set-ethernet/synthetic-interface/request.json"
        )
        let transport = MockHTTPTransport(responses: [
            response(
                #"{"success":true,"data":{"interfaces":[{"ifname":"eth0","title":"Synthetic Interface","status":"connected"}]}}"#
            ),
            response(
                #"{"success":true,"data":{"ifname":"eth0","title":"Synthetic Interface","status":"connected","use_dhcp":false,"ip":"192.0.2.10","mask":"255.255.255.0","gateway":"192.0.2.1","dns":"192.0.2.1","is_default_gateway":true,"mtu":1500,"enable_vlan":true,"vlan_id":20}}"#
            ),
            response(#"{"success":true}"#),
            response(
                #"{"success":true,"data":{"ifname":"eth0","title":"Synthetic Interface","status":"connected","use_dhcp":true,"ip":"","mask":"","gateway":"","dns":"","is_default_gateway":false,"mtu":1500,"enable_vlan":false,"vlan_id":0}}"#
            )
        ])
        let repository = try makeAdministrationRepository(
            apiNames: [DsmAPIName.coreNetworkEthernet],
            transport: transport
        )

        let result = try await repository.saveEthernetInterfaceResult(
            NasEthernetInterface(
                id: "eth0",
                displayName: "Synthetic Interface",
                status: "connected",
                usesDHCP: true,
                address: "",
                subnetMask: "",
                gateway: "",
                dnsServers: "",
                isDefaultGateway: false,
                mtu: 1_500,
                isVLANEnabled: false,
                vlanID: nil
            )
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 4)
        let request = try XCTUnwrap(requests.dropFirst(2).first)
        try assertFormRequest(request, matches: fixture)
    }

    func test安全设置复合请求与共享Fixture一致() async throws {
        let fixtures = try [
            loadFixture("security/set-auto-block/synthetic-settings/request.json"),
            loadFixture("security/set-dos/synthetic-interface/request.json"),
            loadFixture("security/set-port-scan/synthetic-settings/request.json"),
            loadFixture("security/disable-firewall/synthetic-settings/request.json")
        ]
        let currentAutoBlock =
            #"{"success":true,"data":{"enable":false,"attempts":10,"within_mins":5,"expire_day":0}}"#
        let updatedAutoBlock =
            #"{"success":true,"data":{"enable":true,"attempts":5,"within_mins":10,"expire_day":7}}"#
        let ethernet =
            #"{"success":true,"data":{"interfaces":[{"id":"eth-synthetic","display":"Synthetic LAN"}]}}"#
        let transport = MockHTTPTransport(responses: [
            response(currentAutoBlock),
            response(
                #"{"success":true,"data":{"enable_firewall":true,"profile_name":"synthetic-profile"}}"#
            ),
            response(#"{"success":true,"data":{"enable_port_check":false}}"#),
            response(ethernet),
            response(
                #"{"success":true,"data":{"configs":[{"adapter":"eth-synthetic","dos_protect_enable":false}]}}"#
            ),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(updatedAutoBlock),
            response(
                #"{"success":true,"data":{"enable_firewall":false,"profile_name":"synthetic-profile"}}"#
            ),
            response(#"{"success":true,"data":{"enable_port_check":true}}"#),
            response(ethernet),
            response(
                #"{"success":true,"data":{"configs":[{"adapter":"eth-synthetic","dos_protect_enable":true}]}}"#
            )
        ])
        let repository = try makeAdministrationRepository(
            apiNames: [
                DsmAPIName.coreSecurityAutoBlock,
                DsmAPIName.coreNetworkEthernet,
                DsmAPIName.coreSecurityDoS,
                DsmAPIName.coreSecurityFirewall,
                DsmAPIName.coreSecurityFirewallConf
            ],
            transport: transport
        )

        let result = try await repository.saveSecuritySettingsResult(
            NasSecuritySettings(
                isAutoBlockEnabled: true,
                failedAttempts: 5,
                withinMinutes: 10,
                expirationDays: 7,
                dosProtection: [
                    NasDoSProtectionSetting(
                        id: "eth-synthetic",
                        displayName: "Synthetic LAN",
                        isEnabled: true
                    )
                ],
                isFirewallEnabled: false,
                firewallProfileName: "synthetic-profile",
                isPortScanProtectionEnabled: true
            )
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 14)
        for (request, fixture) in zip(requests[5...8], fixtures) {
            try assertFormRequest(request, matches: fixture)
        }
    }

    func test防火墙配置档应用请求与共享Fixture一致() async throws {
        let fixture = try loadFixture(
            "security/apply-firewall-profile/synthetic-profile/request.json"
        )
        let autoBlock =
            #"{"success":true,"data":{"enable":true,"attempts":5,"within_mins":10,"expire_day":0}}"#
        let transport = MockHTTPTransport(responses: [
            response(autoBlock),
            response(
                #"{"success":true,"data":{"enable_firewall":false,"profile_name":"synthetic-profile"}}"#
            ),
            response(#"{"success":true,"data":{"task_id":"synthetic-task"}}"#),
            response(#"{"success":true,"data":{"success":true}}"#),
            response(#"{"success":true}"#),
            response(autoBlock),
            response(
                #"{"success":true,"data":{"enable_firewall":true,"profile_name":"synthetic-profile"}}"#
            )
        ])
        let repository = try makeAdministrationRepository(
            apiNames: [
                DsmAPIName.coreSecurityAutoBlock,
                DsmAPIName.coreSecurityFirewall,
                DsmAPIName.coreSecurityFirewallProfileApply
            ],
            transport: transport
        )

        let result = try await repository.saveSecuritySettingsResult(
            NasSecuritySettings(
                isAutoBlockEnabled: true,
                failedAttempts: 5,
                withinMinutes: 10,
                expirationDays: nil,
                isFirewallEnabled: true,
                firewallProfileName: "synthetic-profile"
            )
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 7)
        try assertFormRequest(requests[2], matches: fixture)
    }

    func test硬件设置复合请求与共享Fixture一致() async throws {
        let fixtures = try [
            loadFixture(
                "hardware/set-power-recovery/synthetic-settings/request.json"
            ),
            loadFixture(
                "hardware/set-led-brightness/synthetic-settings/request.json"
            ),
            loadFixture("hardware/set-fan-mode/synthetic-settings/request.json"),
            loadFixture("hardware/set-beep/synthetic-settings/request.json"),
            loadFixture(
                "hardware/set-hibernation/synthetic-settings/request.json"
            ),
            loadFixture("hardware/set-ups/synthetic-settings/request.json")
        ]
        let powerBefore =
            #"{"success":true,"data":{"rc_power_config":false}}"#
        let powerAfter =
            #"{"success":true,"data":{"rc_power_config":true}}"#
        let ledBefore =
            #"{"success":true,"data":{"led_brightness":3}}"#
        let ledAfter =
            #"{"success":true,"data":{"led_brightness":5}}"#
        let ledRange =
            #"{"success":true,"data":{"min":0,"max":7}}"#
        let fanBefore =
            #"{"success":true,"data":{"dual_fan_speed":"quietfan"}}"#
        let fanAfter =
            #"{"success":true,"data":{"dual_fan_speed":"coolfan"}}"#
        let beepBefore =
            #"{"success":true,"data":{"fan_fail":true,"volume_or_cache_crash":true,"poweron_beep":false,"poweroff_beep":false,"reset_beep":true}}"#
        let beepAfter =
            #"{"success":true,"data":{"fan_fail":true,"volume_or_cache_crash":true,"poweron_beep":true,"poweroff_beep":false,"reset_beep":true}}"#
        let hibernationBefore =
            #"{"success":true,"data":{"eunit_deep_sleep":false,"enable_log":true,"sata_deep_sleep":true,"ignore_netbios_broadcast":false,"auto_poweroff_enable":false}}"#
        let hibernationAfter =
            #"{"success":true,"data":{"eunit_deep_sleep":true,"enable_log":true,"sata_deep_sleep":true,"ignore_netbios_broadcast":true,"auto_poweroff_enable":false}}"#
        let upsBefore =
            #"{"success":true,"data":{"enable":false,"mode":"USB","delay_time":60,"ups_set_safemode_until_lowbatt":false,"shutdown_device":false}}"#
        let upsAfter =
            #"{"success":true,"data":{"enable":true,"mode":"SLAVE","delay_time":120,"ups_set_safemode_until_lowbatt":false,"shutdown_device":true,"net_server_ip":"<synthetic-ups-server>"}}"#
        let transport = MockHTTPTransport(responses: [
            response(powerBefore),
            response(ledBefore),
            response(ledRange),
            response(fanBefore),
            response(beepBefore),
            response(hibernationBefore),
            response(upsBefore),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(powerAfter),
            response(ledAfter),
            response(ledRange),
            response(fanAfter),
            response(beepAfter),
            response(hibernationAfter),
            response(upsAfter)
        ])
        let repository = try makeAdministrationRepository(
            apiNames: [
                DsmAPIName.coreHardwarePowerRecovery,
                DsmAPIName.coreHardwareLEDBrightness,
                DsmAPIName.coreHardwareFanSpeed,
                DsmAPIName.coreHardwareBeepControl,
                DsmAPIName.coreHardwareHibernation,
                DsmAPIName.coreExternalDeviceUPS
            ],
            transport: transport
        )

        let result = try await repository.saveHardwareSettingsResult(
            NasHardwareSettings(
                restartsAfterPowerFailure: true,
                ledBrightness: 5,
                ledBrightnessRange: 0...7,
                fanMode: "coolfan",
                isFanFailureAlertEnabled: true,
                isVolumeFailureAlertEnabled: true,
                isPowerOnSoundEnabled: true,
                isPowerOffSoundEnabled: false,
                isResetSoundEnabled: true,
                isExternalDriveDeepSleepEnabled: true,
                isWakeUpLogEnabled: true,
                isSATASleepEnabled: true,
                ignoresNetworkDiscoveryDuringSleep: true,
                isAutomaticPowerOffEnabled: false,
                ups: NasUPSSettings(
                    isEnabled: true,
                    mode: "SLAVE",
                    safeModeDelaySeconds: 120,
                    waitsUntilLowBattery: false,
                    shutsDownUPSAfterSafeMode: true,
                    networkServerAddress: "<synthetic-ups-server>",
                    snmpServerAddress: nil
                )
            )
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 21)
        let writeIndexes = [7, 8, 10, 11, 12, 13]
        for (index, fixture) in zip(writeIndexes, fixtures) {
            try assertFormRequest(requests[index], matches: fixture)
        }
        XCTAssertEqual(try decodeForm(requests[9].httpBody)["method"], "update")
    }

    func test启动硬盘检测请求与共享Fixture一致() async throws {
        let fixture = try loadFixture(
            "storage/start-smart-test/synthetic-disk/request.json"
        )
        let transport = MockHTTPTransport(responses: [
            response(
                #"{"success":true,"data":{"disks":[{"id":"synthetic-disk","device":"<synthetic-device>","longName":"Synthetic Disk","smart_status":"normal","smart_test_support":true}],"storagePools":[],"volumes":[]}}"#
            ),
            response(
                #"{"success":true,"data":{"testInfo":[{"device":"<synthetic-device>","testing":false,"ihm_testing":false,"perf_testing":false}]}}"#
            ),
            response(#"{"success":true}"#),
            response(
                #"{"success":true,"data":{"testInfo":[{"device":"<synthetic-device>","testing":true,"test_type":"quick"}]}}"#
            ),
        ])
        let repository = try makeAdministrationRepository(
            apiNames: [
                DsmAPIName.storageOverview,
                DsmAPIName.coreStorageDisk,
            ],
            transport: transport
        )
        _ = try await repository.loadStorage()

        let result = try await repository.startDiskTestResult(
            diskID: "synthetic-disk",
            type: .quick
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 4)
        let request = requests[2]
        try assertFormRequest(request, matches: fixture)
    }

    func test停止硬盘检测请求与共享Fixture一致() async throws {
        let fixture = try loadFixture(
            "storage/stop-smart-test/synthetic-disk/request.json"
        )
        let transport = MockHTTPTransport(responses: [
            response(
                #"{"success":true,"data":{"disks":[{"id":"synthetic-disk","device":"<synthetic-device>","longName":"Synthetic Disk","smart_status":"normal","smart_test_support":true}],"storagePools":[],"volumes":[]}}"#
            ),
            response(
                #"{"success":true,"data":{"testInfo":[{"device":"<synthetic-device>","testing":true,"test_type":"quick"}]}}"#
            ),
            response(#"{"success":true}"#),
            response(
                #"{"success":true,"data":{"testInfo":[{"device":"<synthetic-device>","testing":false}]}}"#
            )
        ])
        let repository = try makeAdministrationRepository(
            apiNames: [
                DsmAPIName.storageOverview,
                DsmAPIName.coreStorageDisk
            ],
            transport: transport
        )
        _ = try await repository.loadStorage()

        let result = try await repository.stopDiskTestResult(
            diskID: "synthetic-disk"
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 4)
        try assertFormRequest(requests[2], matches: fixture)
    }

    private var testCredential: DsmSessionCredential {
        DsmSessionCredential(
            sid: "REDACTED_SESSION",
            synoToken: "REDACTED_TOKEN"
        )
    }

    private func assertFormRequest(
        _ request: URLRequest,
        matches fixture: RequestFixture
    ) throws {
        XCTAssertEqual(request.httpMethod, fixture.transport.httpMethod)
        XCTAssertEqual(request.url?.lastPathComponent, fixture.api.resolvedPath)
        let fields = try decodeForm(request.httpBody)
        XCTAssertEqual(fields["api"], fixture.api.name)
        XCTAssertEqual(fields["method"], fixture.api.method)
        XCTAssertEqual(fields["version"], String(fixture.api.resolvedVersion))

        let actualParameters = fields.filter {
            !["api", "method", "version", "_sid", "SynoToken"].contains($0.key)
        }
        XCTAssertEqual(
            Set(actualParameters.keys),
            Set(fixture.parameters.map(\.name))
        )
        for parameter in fixture.parameters {
            guard let expected = parameter.encodedValue,
                  let actual = actualParameters[parameter.name] else {
                continue
            }
            if ["object", "objectArray"].contains(parameter.valueType) {
                XCTAssertTrue(
                    try jsonValuesAreEqual(actual, expected),
                    "参数 \(parameter.name) 的 JSON 结构不一致"
                )
            } else {
                XCTAssertEqual(actual, expected)
            }
        }
        for parameter in fixture.parameters where parameter.redacted == true {
            XCTAssertNotNil(actualParameters[parameter.name])
        }
        let authentication = authenticationLocations(in: request, fields: fields)
        XCTAssertEqual(authentication.required, fixture.authentication.required)
        XCTAssertEqual(
            authentication.synoTokenRequired,
            fixture.authentication.synoTokenRequired
        )
        XCTAssertEqual(
            Set(authentication.sessionLocations),
            Set(fixture.authentication.sessionLocations)
        )
        XCTAssertEqual(
            Set(authentication.synoTokenLocations),
            Set(fixture.authentication.synoTokenLocations)
        )
    }

    private func assertMultipartRequest(
        _ request: URLRequest,
        body: Data,
        matches fixture: RequestFixture
    ) throws {
        XCTAssertEqual(request.httpMethod, fixture.transport.httpMethod)
        XCTAssertEqual(request.url?.lastPathComponent, fixture.api.resolvedPath)
        let query = Dictionary(
            uniqueKeysWithValues: (
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                    .queryItems ?? []
            ).map { ($0.name, $0.value ?? "") }
        )
        XCTAssertEqual(query["api"], fixture.api.name)
        XCTAssertEqual(query["method"], fixture.api.method)
        XCTAssertEqual(query["version"], String(fixture.api.resolvedVersion))

        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try XCTUnwrap(
            contentType.components(separatedBy: "boundary=").last
        )
        var fields = parseMultipartFields(body, boundary: boundary)
        fields["file"] = "<synthetic-binary>"
        let actualParameters = fields.filter {
            ![
                "api",
                "method",
                "version",
                "_sid",
                "SynoToken",
                "synotoken",
            ].contains($0.key)
        }
        XCTAssertEqual(
            Set(actualParameters.keys),
            Set(fixture.parameters.map(\.name))
        )
        for parameter in fixture.parameters {
            guard let expected = parameter.encodedValue,
                  let actual = actualParameters[parameter.name] else {
                continue
            }
            if ["object", "objectArray"].contains(parameter.valueType) {
                XCTAssertTrue(
                    try jsonValuesAreEqual(actual, expected),
                    "参数 \(parameter.name) 的 JSON 结构不一致"
                )
            } else {
                XCTAssertEqual(actual, expected)
            }
        }

        var sessionLocations = Set<String>()
        var tokenLocations = Set<String>()
        if request.value(forHTTPHeaderField: "Cookie") != nil {
            sessionLocations.insert("cookie")
        }
        if query["_sid"] != nil {
            sessionLocations.insert("query")
        }
        if fields["_sid"] != nil {
            sessionLocations.insert("multipart")
        }
        if request.value(forHTTPHeaderField: "X-SYNO-TOKEN") != nil {
            tokenLocations.insert("header")
        }
        if query["SynoToken"] != nil || query["synotoken"] != nil {
            tokenLocations.insert("query")
        }
        if fields["SynoToken"] != nil || fields["synotoken"] != nil {
            tokenLocations.insert("multipart")
        }
        XCTAssertEqual(sessionLocations, Set(fixture.authentication.sessionLocations))
        XCTAssertEqual(tokenLocations, Set(fixture.authentication.synoTokenLocations))
    }

    private func authenticationLocations(
        in request: URLRequest,
        fields: [String: String]
    ) -> RequestFixture.Authentication {
        var sessionLocations = Set<String>()
        var tokenLocations = Set<String>()
        if request.value(forHTTPHeaderField: "Cookie") != nil {
            sessionLocations.insert("cookie")
        }
        if fields["_sid"] != nil {
            sessionLocations.insert("form")
        }
        if request.value(forHTTPHeaderField: "X-SYNO-TOKEN") != nil {
            tokenLocations.insert("header")
        }
        if fields["SynoToken"] != nil {
            tokenLocations.insert("form")
        }
        return RequestFixture.Authentication(
            required: true,
            synoTokenRequired: false,
            sessionLocations: sessionLocations.sorted(),
            synoTokenLocations: tokenLocations.sorted()
        )
    }

    private func decodeForm(_ data: Data?) throws -> [String: String] {
        let body = try XCTUnwrap(data.flatMap { String(data: $0, encoding: .utf8) })
        var components = URLComponents()
        components.percentEncodedQuery = body
        return Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name, $0.value ?? "")
            }
        )
    }

    private func jsonValuesAreEqual(
        _ lhs: String,
        _ rhs: String
    ) throws -> Bool {
        let left = try JSONSerialization.jsonObject(with: Data(lhs.utf8))
        let right = try JSONSerialization.jsonObject(with: Data(rhs.utf8))
        return (left as AnyObject).isEqual(right)
    }

    private func parseMultipartFields(
        _ data: Data,
        boundary: String
    ) -> [String: String] {
        let text = String(decoding: data, as: UTF8.self)
        var result: [String: String] = [:]
        for section in text.components(separatedBy: "--\(boundary)") {
            guard let nameRange = section.range(of: #"name=""#) else {
                continue
            }
            let afterName = section[nameRange.upperBound...]
            guard let endName = afterName.firstIndex(of: "\"") else {
                continue
            }
            let name = String(afterName[..<endName])
            guard name != "file",
                  let separator = section.range(of: "\r\n\r\n") else {
                continue
            }
            result[name] = section[separator.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private func loadFixture(_ relativePath: String) throws -> RequestFixture {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory
                .appendingPathComponent("contracts/request-fixtures")
                .appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try JSONDecoder().decode(
                    RequestFixture.self,
                    from: Data(contentsOf: candidate)
                )
            }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
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
                synoToken: "REDACTED_TOKEN",
                did: nil,
                isPortalPort: false
            ),
            transport: transport
        )
    }

    private func makeAdministrationRepository(
        transport: MockHTTPTransport
    ) throws -> DsmNasAdministrationRepository {
        try makeAdministrationRepository(
            apiNames: [DsmAPIName.coreUser],
            transport: transport
        )
    }

    private func makeAdministrationRepository(
        apiNames: [String],
        transport: MockHTTPTransport
    ) throws -> DsmNasAdministrationRepository {
        let profile = try NasProfile(
            displayName: "测试设备",
            host: "nas.example.invalid",
            port: 5_001
        )
        return try DsmNasAdministrationRepository(
            profile: profile,
            capabilities: CapabilitySet(
                Dictionary(
                    uniqueKeysWithValues: apiNames.map {
                        (
                            $0,
                            capability(
                                $0,
                                version: $0 == DsmAPIName.coreQuickConnect
                                    ? 3
                                    : ($0 == DsmAPIName.coreWebDSM
                                        ? 2
                                        : ([
                                        DsmAPIName.coreNetworkEthernet,
                                        DsmAPIName.coreSecurityDoS
                                        ].contains($0) ? 2 : 1))
                            )
                        )
                    }
                )
            ),
            session: AuthSession(
                sid: "REDACTED_SESSION",
                synoToken: "REDACTED_TOKEN",
                did: nil,
                isPortalPort: false
            ),
            transport: transport
        )
    }

    private func makePackageAdministrationRepository(
        transport: MockHTTPTransport
    ) throws -> DsmNasAdministrationRepository {
        let profile = try NasProfile(
            displayName: "测试设备",
            host: "nas.example.invalid",
            port: 5_001
        )
        let capabilities = [
            DsmAPIName.corePackage,
            DsmAPIName.corePackageUninstallation,
        ]
        return try DsmNasAdministrationRepository(
            profile: profile,
            capabilities: CapabilitySet(
                Dictionary(
                    uniqueKeysWithValues: capabilities.map {
                        ($0, capability($0, version: $0 == DsmAPIName.corePackage ? 2 : 1))
                    }
                )
            ),
            session: AuthSession(
                sid: "REDACTED_SESSION",
                synoToken: "REDACTED_TOKEN",
                did: nil,
                isPortalPort: false
            ),
            transport: transport
        )
    }

    private func makeServiceManagementRepository(
        apiNames: [String],
        transport: MockHTTPTransport
    ) throws -> DsmServiceManagementRepository {
        let profile = try NasProfile(
            displayName: "测试设备",
            host: "nas.example.invalid",
            port: 5_001
        )
        return try DsmServiceManagementRepository(
            profile: profile,
            capabilities: CapabilitySet(
                Dictionary(
                    uniqueKeysWithValues: apiNames.map {
                        ($0, capability($0, version: 1))
                    }
                )
            ),
            session: AuthSession(
                sid: "REDACTED_SESSION",
                synoToken: "REDACTED_TOKEN",
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

    private func response(_ body: String) -> DsmHTTPResponse {
        DsmHTTPResponse(data: Data(body.utf8), statusCode: 200)
    }
}

private struct RequestFixture: Decodable {
    struct API: Decodable {
        let name: String
        let method: String
        let resolvedVersion: Int
        let resolvedPath: String
    }

    struct Transport: Decodable {
        let httpMethod: String
        let requestFormat: String
    }

    struct Parameter: Decodable {
        let name: String
        let valueType: String
        let encodedValue: String?
        let redacted: Bool?
    }

    struct Authentication: Codable, Equatable {
        let required: Bool
        let synoTokenRequired: Bool
        let sessionLocations: [String]
        let synoTokenLocations: [String]
    }

    let api: API
    let transport: Transport
    let parameters: [Parameter]
    let authentication: Authentication
}

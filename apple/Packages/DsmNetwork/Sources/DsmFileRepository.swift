import DsmCore
import CryptoKit
import Foundation

private struct FileListPayload: Decodable, Sendable {
    let offset: Int?
    let total: Int?
    let files: [FilePayload]?
    let shares: [FilePayload]?
}

private struct FileInfoPayload: Decodable, Sendable {
    let files: [FilePayload]
}

private struct FilePayload: Decodable, Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    let additional: FileAdditionalPayload?

    private enum CodingKeys: String, CodingKey {
        case name
        case path
        case isDirectory = "isdir"
        case additional
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        if let value = try? container.decode(Bool.self, forKey: .isDirectory) {
            isDirectory = value
        } else if let value = try? container.decode(Int.self, forKey: .isDirectory) {
            isDirectory = value != 0
        } else if let value = try? container.decode(String.self, forKey: .isDirectory) {
            isDirectory = value == "1" || value.lowercased() == "true"
        } else {
            isDirectory = false
        }
        additional = try container.decodeIfPresent(FileAdditionalPayload.self, forKey: .additional)
    }
}

private struct FileAdditionalPayload: Decodable, Sendable {
    let size: Int64?
    let type: String?
    let time: FileTimePayload?
    let owner: FileOwnerPayload?
    let perm: FilePermissionPayload?

    private enum CodingKeys: String, CodingKey {
        case size
        case type
        case time
        case owner
        case perm
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Int64.self, forKey: .size) {
            size = value
        } else if let value = try? container.decode(String.self, forKey: .size) {
            size = Int64(value)
        } else {
            size = nil
        }
        type = try container.decodeIfPresent(String.self, forKey: .type)
        time = try? container.decodeIfPresent(FileTimePayload.self, forKey: .time)
        owner = try? container.decodeIfPresent(FileOwnerPayload.self, forKey: .owner)
        perm = try? container.decodeIfPresent(FilePermissionPayload.self, forKey: .perm)
    }
}

private struct FileTimePayload: Decodable, Sendable {
    let mtime: Int64?
    let crtime: Int64?
    let atime: Int64?
}

private struct FileOwnerPayload: Decodable, Sendable {
    let user: String?
    let group: String?
}

private struct FilePermissionPayload: Decodable, Sendable {
    let posix: Int?
    let advRight: [String: Bool]?

    private enum CodingKeys: String, CodingKey {
        case posix
        case advRight = "adv_right"
    }
}

private struct TaskStartPayload: Decodable, Sendable {
    let taskid: String
}

private struct TaskStatusPayload: Decodable, Sendable {
    let finished: Bool
    let progress: Int64?
    let total: Int64?
    let processedSize: Int64?

    private enum CodingKeys: String, CodingKey {
        case finished
        case progress
        case total
        case processedSize = "processed_size"
    }
}

private struct BinaryEnvelope: Decodable, Sendable {
    struct ErrorPayload: Decodable, Sendable {
        let code: Int
    }

    let success: Bool
    let error: ErrorPayload?
}

private struct StreamingUploadPlan: @unchecked Sendable {
    var request: URLRequest
    let prefix: Data
    let suffix: Data
}

public actor DsmFileRepository: FileRepository {
    public nonisolated let profileID: UUID
    public nonisolated let isDemo = false
    public nonisolated let allowsVerifiedRestore: Bool

    private let baseURL: URL
    private let expectedHost: String
    private let pinnedCertificateSHA256: String?
    private let capabilities: CapabilitySet
    private let credential: DsmSessionCredential
    private let transport: any DsmBinaryHTTPTransport
    private let client: DsmAPIClient

    public init(
        profile: NasProfile,
        capabilities: CapabilitySet,
        session: AuthSession,
        transport: (any DsmBinaryHTTPTransport)? = nil
    ) throws {
        let resolvedTransport = transport ?? URLSessionTransport(
            expectedHost: profile.host,
            pinnedCertificateSHA256: profile.pinnedCertificateSHA256,
            requiresSystemCertificateTrust: DsmQuickConnectResolver.isTrustedRelayHost(
                profile.host
            )
        )
        let baseURL = try DsmEndpoint.baseURL(for: profile)
        profileID = profile.id
        allowsVerifiedRestore = capabilities[DsmAPIName.fileStationCopyMove]?.verified == true
        self.baseURL = baseURL
        self.expectedHost = profile.host
        self.pinnedCertificateSHA256 = profile.pinnedCertificateSHA256
        self.capabilities = capabilities
        self.credential = DsmSessionCredential(
            sid: session.sid,
            synoToken: session.synoToken
        )
        self.transport = resolvedTransport
        self.client = DsmAPIClient(baseURL: baseURL, transport: resolvedTransport)
    }

    public func listShares(offset: Int = 0, limit: Int = 200) async throws -> FilePage {
        let capability = try requireCapability(DsmAPIName.fileStationList)
        do {
            let payload = try await client.call(
                path: capability.path,
                api: capability.name,
                version: try selectedVersion(capability),
                method: "list_share",
                requestFormat: capability.requestFormat,
                parameters: listParameters(offset: offset, limit: limit),
                credential: credential,
                as: FileListPayload.self
            )
            let items = (payload.shares ?? []).map(makeFileItem)
            let resolvedOffset = payload.offset ?? offset
            let total = payload.total ?? items.count
            return FilePage(
                folderPath: "/",
                items: items,
                offset: resolvedOffset,
                total: total,
                hasMore: resolvedOffset + items.count < total
            )
        } catch let error as DsmNetworkError {
            throw DsmErrorMapper.map(error)
        }
    }

    public func listFolder(path: String, offset: Int = 0, limit: Int = 500) async throws -> FilePage {
        let capability = try requireCapability(DsmAPIName.fileStationList)
        do {
            var parameters = listParameters(offset: offset, limit: limit)
            parameters["folder_path"] = .string(path)
            let payload = try await client.call(
                path: capability.path,
                api: capability.name,
                version: try selectedVersion(capability),
                method: "list",
                requestFormat: capability.requestFormat,
                parameters: parameters,
                credential: credential,
                as: FileListPayload.self
            )
            let items = (payload.files ?? []).map(makeFileItem)
            let resolvedOffset = payload.offset ?? offset
            let total = payload.total ?? items.count
            return FilePage(
                folderPath: path,
                items: items,
                offset: resolvedOffset,
                total: total,
                hasMore: resolvedOffset + items.count < total
            )
        } catch let error as DsmNetworkError {
            throw DsmErrorMapper.map(error)
        }
    }

    public func getInfo(paths: [String]) async throws -> [FileItem] {
        guard !paths.isEmpty else {
            return []
        }
        let capability = try requireCapability(DsmAPIName.fileStationList)
        do {
            let payload = try await client.call(
                path: capability.path,
                api: capability.name,
                version: try selectedVersion(capability),
                method: "getinfo",
                requestFormat: capability.requestFormat,
                parameters: [
                    "path": .stringArray(paths),
                    "additional": .stringArray(Self.additionalFields)
                ],
                credential: credential,
                as: FileInfoPayload.self
            )
            return payload.files.map(makeFileItem)
        } catch let error as DsmNetworkError {
            throw DsmErrorMapper.map(error)
        }
    }

    public func getThumbnail(path: String, size: ThumbnailSize) async throws -> Data {
        let capability = try requireCapability(DsmAPIName.fileStationThumbnail)
        let request = try DsmRequestBuilder.build(
            baseURL: baseURL,
            path: capability.path,
            api: capability.name,
            version: try selectedVersion(capability),
            method: "get",
            requestFormat: capability.requestFormat,
            parameters: [
                "path": .string(path),
                "size": .string(size.rawValue),
                "rotate": .integer(0)
            ],
            credential: credential
        )
        do {
            let response = try await transport.send(request)
            try validateBinaryResponse(response, data: response.data)
            return response.data
        } catch {
            throw translate(error)
        }
    }

    public func checkWritePermission(
        folderPath: String,
        filename: String,
        createOnly: Bool
    ) async throws {
        let capability = try requireCapability(DsmAPIName.fileStationCheckPermission)
        do {
            try await client.callVoid(
                path: capability.path,
                api: capability.name,
                version: try selectedVersion(capability),
                method: "write",
                requestFormat: capability.requestFormat,
                parameters: [
                    "path": .string(folderPath),
                    "filename": .string(filename),
                    "create_only": .boolean(createOnly)
                ],
                credential: credential
            )
        } catch let error as DsmNetworkError {
            throw DsmErrorMapper.map(error)
        }
    }

    public func mediaStreamSource(
        remotePath: String,
        fileExtension: String?,
        expectedContentLength: Int64?
    ) async throws -> MediaStreamSource {
        let capability = try requireCapability(DsmAPIName.fileStationDownload)
        var request = try DsmRequestBuilder.build(
            baseURL: baseURL,
            path: capability.path,
            api: capability.name,
            version: try selectedVersion(capability),
            method: "download",
            requestFormat: capability.requestFormat,
            parameters: [
                "path": .stringArray([remotePath]),
                "mode": .string("download")
            ],
            credential: nil,
            httpMethod: "GET"
        )
        if let cookie = credential.cookieHeaderValue {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let synoToken = credential.synoToken, !synoToken.isEmpty {
            request.setValue(synoToken, forHTTPHeaderField: "X-SYNO-TOKEN")
        }
        return MediaStreamSource(
            request: request,
            fileExtension: fileExtension,
            expectedContentLength: expectedContentLength,
            expectedHost: expectedHost,
            pinnedCertificateSHA256: pinnedCertificateSHA256
        )
    }

    public func download(
        remotePath: String,
        to localURL: URL,
        expectedSize: Int64?,
        progress: @escaping FileTransferProgress
    ) async throws {
        let capability = try requireCapability(DsmAPIName.fileStationDownload)
        let baseRequest = try DsmRequestBuilder.build(
            baseURL: baseURL,
            path: capability.path,
            api: capability.name,
            version: try selectedVersion(capability),
            method: "download",
            requestFormat: capability.requestFormat,
            parameters: [
                "path": .stringArray([remotePath]),
                "mode": .string("download")
            ],
            credential: credential,
            httpMethod: "GET"
        )
        
        let partURL = partialDownloadURL(
            remotePath: remotePath,
            localURL: localURL,
            expectedSize: expectedSize
        )
        
        do {
            try FileManager.default.createDirectory(
                at: localURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw translate(error)
        }
        
        var completed = Self.fileSize(at: partURL)
        if let expectedSize, completed > expectedSize {
            try? FileManager.default.removeItem(at: partURL)
            completed = 0
        }
        
        if completed == 0 {
            // ==================== 直接一次性下载（非续传） ====================
            do {
                let response = try await transport.download(baseRequest, to: partURL, progress: progress)
                let contentType = response.headers["content-type"]?.lowercased() ?? ""
                let needsErrorInspection = contentType.contains("application/json") || contentType.contains("text/html")
                let inspectionData: Data
                if needsErrorInspection {
                    let handle = try FileHandle(forReadingFrom: partURL)
                    inspectionData = try handle.read(upToCount: 1_048_576) ?? Data()
                    try handle.close()
                } else {
                    inspectionData = Data()
                }
                try validateBinaryResponse(response, data: inspectionData)
                
                try Self.safeReplaceFile(from: partURL, to: localURL)
                try? FileManager.default.removeItem(at: partURL)
            } catch {
                try? FileManager.default.removeItem(at: partURL)
                throw translate(error)
            }
        } else {
            // ==================== 分片续传下载（续传） ====================
            let savedChunkSize = UserDefaults.standard.integer(forKey: "LanStash_DownloadChunkSize")
            let chunkSize: Int64 = (savedChunkSize >= 4 && savedChunkSize <= 64)
                ? Int64(savedChunkSize) * 1024 * 1024
                : 8 * 1024 * 1024
            progress(completed, expectedSize)
            
            do {
                repeat {
                    try Task.checkCancellation()
                    let segmentURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(".\(UUID().uuidString).lanstash.segment")
                    defer { try? FileManager.default.removeItem(at: segmentURL) }

                    var request = baseRequest
                    if let expectedSize, expectedSize > 0 {
                        let end = min(expectedSize - 1, completed + chunkSize - 1)
                        request.setValue("bytes=\(completed)-\(end)", forHTTPHeaderField: "Range")
                    }
                    let completedBeforeRequest = completed
                    let response = try await transport.download(request, to: segmentURL) { value, _ in
                        progress(completedBeforeRequest + value, expectedSize)
                    }
                    let inspectionData = try binaryInspectionData(
                        response: response,
                        fileURL: segmentURL
                    )
                    try validateBinaryResponse(response, data: inspectionData)

                    if response.statusCode == 206 {
                        try Self.appendFile(at: segmentURL, to: partURL)
                    } else {
                        // 服务器忽略 Range 时会返回完整文件，直接替换残留片段以避免数据重复。
                        if FileManager.default.fileExists(atPath: partURL.path) {
                            try FileManager.default.removeItem(at: partURL)
                        }
                        try Self.safeReplaceFile(from: segmentURL, to: partURL)
                    }
                    completed = Self.fileSize(at: partURL)
                    progress(completed, expectedSize)

                    if response.statusCode != 206 || expectedSize == nil || expectedSize == 0 {
                        break
                    }
                } while completed < (expectedSize ?? 0)

                if let expectedSize, expectedSize > 0, completed != expectedSize {
                    throw AppError(
                        category: .partialFailure,
                        isRetryable: true,
                        safeUserMessage: "下载暂未完成，可以在传输中心继续。"
                    )
                }
                try Self.safeReplaceFile(from: partURL, to: localURL)
                try? FileManager.default.removeItem(at: partURL)
            } catch {
                throw translate(error)
            }
        }
    }

    public func removePartialDownload(to localURL: URL) async {
        let prefix = ".\(localURL.lastPathComponent)."
        let legacyName = ".\(localURL.lastPathComponent).lanstash.part"
        
        // 1. 清理临时目录下的分片（新逻辑）
        let tempDir = FileManager.default.temporaryDirectory
        let tempUrls = (try? FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in tempUrls where url.lastPathComponent.hasPrefix(prefix)
            && url.lastPathComponent.hasSuffix(".lanstash.part") {
            try? FileManager.default.removeItem(at: url)
        }
        
        // 2. 清理目标目录下的分片（测试和旧版本兼容）
        let targetDir = localURL.deletingLastPathComponent()
        let targetUrls = (try? FileManager.default.contentsOfDirectory(
            at: targetDir,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in targetUrls where url.lastPathComponent == legacyName
            || (url.lastPathComponent.hasPrefix(prefix)
                && url.lastPathComponent.hasSuffix(".lanstash.part")) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func partialDownloadURL(
        remotePath: String,
        localURL: URL,
        expectedSize: Int64?
    ) -> URL {
        let identity = "\(profileID.uuidString)|\(remotePath)|\(expectedSize ?? -1)"
        let digest = SHA256.hash(data: Data(identity.utf8))
        let suffix = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(".\(localURL.lastPathComponent).\(suffix).lanstash.part")
    }

    private func binaryInspectionData(
        response: DsmHTTPResponse,
        fileURL: URL
    ) throws -> Data {
        let contentType = response.headers["content-type"]?.lowercased() ?? ""
        guard contentType.contains("application/json") || contentType.contains("text/html") else {
            return Data()
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        return try handle.read(upToCount: 1_048_576) ?? Data()
    }

    private static func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func appendFile(at sourceURL: URL, to destinationURL: URL) throws {
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let reader = try FileHandle(forReadingFrom: sourceURL)
        let writer = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? reader.close()
            try? writer.close()
        }
        try writer.seekToEnd()
        while let data = try reader.read(upToCount: 1_024 * 1_024), !data.isEmpty {
            try Task.checkCancellation()
            try writer.write(contentsOf: data)
        }
    }

    private static func safeReplaceFile(from sourceURL: URL, to destinationURL: URL) throws {
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        } else {
            let handle = try FileHandle(forWritingTo: destinationURL)
            try handle.truncate(atOffset: 0)
            try handle.close()
        }
        
        let reader = try FileHandle(forReadingFrom: sourceURL)
        let writer = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? reader.close()
            try? writer.close()
        }
        while let data = try reader.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            try writer.write(contentsOf: data)
        }
    }

    public func upload(
        localURL: URL,
        to folderPath: String,
        overwrite: Bool,
        progress: @escaping FileTransferProgress
    ) async throws {
        do {
            let capability = try requireCapability(DsmAPIName.fileStationUpload)
            try await checkWritePermission(
                folderPath: folderPath,
                filename: localURL.lastPathComponent,
                createOnly: !overwrite
            )

            let boundary = "LanStash-\(UUID().uuidString)"
            let bodyURL = try createMultipartBody(
                localURL: localURL,
                boundary: boundary,
                fields: [
                    "api": capability.name,
                    "version": String(try selectedVersion(capability)),
                    "method": "upload",
                    "_sid": credential.sid,
                    "path": folderPath,
                    "create_parents": "false",
                    "overwrite": overwrite ? "true" : "false",
                    "SynoToken": credential.synoToken ?? "",
                    "synotoken": credential.synoToken ?? ""
                ]
            )
            defer { try? FileManager.default.removeItem(at: bodyURL) }

            var uploadURL = apiURL(path: capability.path)
            if var components = URLComponents(url: uploadURL, resolvingAgainstBaseURL: false) {
                var queryItems = components.queryItems ?? []
                queryItems.append(URLQueryItem(name: "api", value: capability.name))
                queryItems.append(URLQueryItem(name: "version", value: String(try selectedVersion(capability))))
                queryItems.append(URLQueryItem(name: "method", value: "upload"))
                queryItems.append(URLQueryItem(name: "_sid", value: credential.sid))
                if let synoToken = credential.synoToken, !synoToken.isEmpty {
                    queryItems.append(URLQueryItem(name: "SynoToken", value: synoToken))
                    queryItems.append(URLQueryItem(name: "synotoken", value: synoToken))
                }
                components.queryItems = queryItems
                if let resolvedURL = components.url {
                    uploadURL = resolvedURL
                }
            }

            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let cookie = credential.cookieHeaderValue {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
            if let synoToken = credential.synoToken, !synoToken.isEmpty {
                request.setValue(synoToken, forHTTPHeaderField: "X-SYNO-TOKEN")
            }

            let response = try await transport.upload(request, from: bodyURL, progress: progress)
            try validateUploadSuccess(response)
        } catch {
            throw translate(error)
        }
    }

    public func streamFileToNAS(
        remotePath: String,
        filename: String,
        expectedSize: Int64,
        target: DsmFileRepository,
        destinationFolder: String,
        progress: @escaping FileTransferProgress
    ) async throws {
        guard expectedSize >= 0 else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: "无法确定文件大小，暂时不能使用内存中转。"
            )
        }
        let downloadCapability = try requireCapability(DsmAPIName.fileStationDownload)
        let baseRequest = try DsmRequestBuilder.build(
            baseURL: baseURL,
            path: downloadCapability.path,
            api: downloadCapability.name,
            version: try selectedVersion(downloadCapability),
            method: "download",
            requestFormat: downloadCapability.requestFormat,
            parameters: [
                "path": .stringArray([remotePath]),
                "mode": .string("download")
            ],
            credential: credential,
            httpMethod: "GET"
        )
        let uploadPlan = try await target.makeStreamingUploadPlan(
            filename: filename,
            fileSize: expectedSize,
            destinationFolder: destinationFolder
        )
        let progressState = CrossNASProgressState(fileSize: expectedSize, progress: progress)
        let pipe = BoundedMemoryPipe(
            capacity: 12 * 1_024 * 1_024,
            onFileBytesRead: { bytes in progressState.didUpload(bytes) }
        )

        let uploadTask = Task {
            do {
                try await target.performStreamingUpload(plan: uploadPlan, pipe: pipe)
            } catch {
                // 目标端提前拒绝上传时立即唤醒可能正在等待缓冲区空间的源端。
                pipe.cancel(with: error)
                throw error
            }
        }
        do {
            try pipe.write(uploadPlan.prefix, countsAsFileData: false)
            var offset: Int64 = 0
            let chunkSize: Int64 = 4 * 1_024 * 1_024
            while offset < expectedSize {
                try Task.checkCancellation()
                let end = min(expectedSize - 1, offset + chunkSize - 1)
                var request = baseRequest
                request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
                let response = try await transport.send(request)
                try validateBinaryResponse(response, data: response.data)
                guard response.statusCode == 206 else {
                    throw AppError(
                        category: .invalidResponse,
                        isRetryable: false,
                        safeUserMessage: "这台 NAS 不支持内存分段读取，跨 NAS 复制已停止。"
                    )
                }
                let expectedChunkSize = Int(end - offset + 1)
                guard response.data.count == expectedChunkSize else {
                    throw AppError(
                        category: .partialFailure,
                        isRetryable: true,
                        safeUserMessage: "源 NAS 返回的数据不完整，请重试跨 NAS 复制。"
                    )
                }
                try pipe.write(response.data, countsAsFileData: true)
                progressState.didDownload(response.data.count)
                offset += Int64(response.data.count)
            }
            try pipe.write(uploadPlan.suffix, countsAsFileData: false)
            pipe.finish()
            try await uploadTask.value
        } catch {
            pipe.cancel(with: error)
            uploadTask.cancel()
            _ = try? await uploadTask.value
            throw translate(error)
        }
    }

    private func makeStreamingUploadPlan(
        filename: String,
        fileSize: Int64,
        destinationFolder: String
    ) async throws -> StreamingUploadPlan {
        let capability = try requireCapability(DsmAPIName.fileStationUpload)
        try await checkWritePermission(
            folderPath: destinationFolder,
            filename: filename,
            createOnly: true
        )
        let boundary = "LanStash-\(UUID().uuidString)"
        let fields = [
            "api": capability.name,
            "version": String(try selectedVersion(capability)),
            "method": "upload",
            "_sid": credential.sid,
            "path": destinationFolder,
            "create_parents": "false",
            "overwrite": "false",
            "SynoToken": credential.synoToken ?? "",
            "synotoken": credential.synoToken ?? ""
        ]
        let safeFilename = filename
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\"", with: "'")
        var prefix = Data()
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) where !value.isEmpty {
            prefix.append(Data("--\(boundary)\r\n".utf8))
            prefix.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            prefix.append(Data("\(value)\r\n".utf8))
        }
        prefix.append(Data("--\(boundary)\r\n".utf8))
        prefix.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\n".utf8))
        prefix.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        let suffix = Data("\r\n--\(boundary)--\r\n".utf8)

        var uploadURL = apiURL(path: capability.path)
        if var components = URLComponents(url: uploadURL, resolvingAgainstBaseURL: false) {
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "api", value: capability.name))
            queryItems.append(URLQueryItem(name: "version", value: String(try selectedVersion(capability))))
            queryItems.append(URLQueryItem(name: "method", value: "upload"))
            queryItems.append(URLQueryItem(name: "_sid", value: credential.sid))
            if let synoToken = credential.synoToken, !synoToken.isEmpty {
                queryItems.append(URLQueryItem(name: "SynoToken", value: synoToken))
                queryItems.append(URLQueryItem(name: "synotoken", value: synoToken))
            }
            components.queryItems = queryItems
            uploadURL = components.url ?? uploadURL
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(String(Int64(prefix.count) + fileSize + Int64(suffix.count)), forHTTPHeaderField: "Content-Length")
        if let cookie = credential.cookieHeaderValue {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let synoToken = credential.synoToken, !synoToken.isEmpty {
            request.setValue(synoToken, forHTTPHeaderField: "X-SYNO-TOKEN")
        }
        return StreamingUploadPlan(request: request, prefix: prefix, suffix: suffix)
    }

    private func performStreamingUpload(
        plan: StreamingUploadPlan,
        pipe: BoundedMemoryPipe
    ) async throws {
        var request = plan.request
        request.httpBodyStream = pipe.makeInputStream()
        let response = try await transport.send(request)
        try validateUploadSuccess(response)
    }

    public func delete(
        paths: [String],
        progress: @escaping FileTransferProgress
    ) async throws {
        guard !paths.isEmpty else {
            return
        }
        let capability = try requireCapability(DsmAPIName.fileStationDelete)
        do {
            let start = try await client.call(
                path: capability.path,
                api: capability.name,
                version: try selectedVersion(capability),
                method: "start",
                requestFormat: capability.requestFormat,
                parameters: [
                    "path": .stringArray(paths),
                    "recursive": .boolean(true),
                    "accurate_progress": .boolean(true)
                ],
                credential: credential,
                as: TaskStartPayload.self
            )
            try await pollTask(capability: capability, taskID: start.taskid, progress: progress)
        } catch let error as DsmNetworkError {
            throw DsmErrorMapper.map(error)
        }
    }

    public func createFolder(parentPath: String, name: String) async throws {
        let capability = try requireCapability(DsmAPIName.fileStationCreateFolder)
        do {
            try await client.callVoid(
                path: capability.path,
                api: capability.name,
                version: try selectedVersion(capability),
                method: "create",
                requestFormat: capability.requestFormat,
                parameters: [
                    "folder_path": .string(parentPath),
                    "name": .string(name),
                    "force_parent": .boolean(false)
                ],
                credential: credential
            )
        } catch let error as DsmNetworkError {
            throw DsmErrorMapper.map(error)
        }
    }

    public func move(
        paths: [String],
        to destinationFolder: String,
        overwrite: Bool,
        progress: @escaping FileTransferProgress
    ) async throws {
        try await copyMove(
            paths: paths,
            to: destinationFolder,
            overwrite: overwrite,
            removeSource: true,
            progress: progress
        )
    }

    public func copy(
        paths: [String],
        to destinationFolder: String,
        overwrite: Bool,
        progress: @escaping FileTransferProgress
    ) async throws {
        try await copyMove(
            paths: paths,
            to: destinationFolder,
            overwrite: overwrite,
            removeSource: false,
            progress: progress
        )
    }

    private func copyMove(
        paths: [String],
        to destinationFolder: String,
        overwrite: Bool,
        removeSource: Bool,
        progress: @escaping FileTransferProgress
    ) async throws {
        guard !paths.isEmpty else {
            return
        }
        let capability = try requireCapability(DsmAPIName.fileStationCopyMove)
        do {
            let start = try await client.call(
                path: capability.path,
                api: capability.name,
                version: try selectedVersion(capability),
                method: "start",
                requestFormat: capability.requestFormat,
                parameters: [
                    "path": .stringArray(paths),
                    "dest_folder_path": .string(destinationFolder),
                    "remove_src": .boolean(removeSource),
                    "overwrite": .boolean(overwrite),
                    "accurate_progress": .boolean(true)
                ],
                credential: credential,
                as: TaskStartPayload.self
            )
            try await pollTask(capability: capability, taskID: start.taskid, progress: progress)
        } catch let error as DsmNetworkError {
            throw DsmErrorMapper.map(error)
        }
    }

    private func pollTask(
        capability: ApiCapability,
        taskID: String,
        progress: @escaping FileTransferProgress
    ) async throws {
        var delay = 500_000_000
        do {
            while true {
                try Task.checkCancellation()
                let status = try await client.call(
                    path: capability.path,
                    api: capability.name,
                    version: try selectedVersion(capability),
                    method: "status",
                    requestFormat: capability.requestFormat,
                    parameters: ["taskid": .string(taskID)],
                    credential: credential,
                    as: TaskStatusPayload.self
                )
                let completed = status.processedSize ?? status.progress ?? 0
                progress(completed, status.total)
                if status.finished {
                    return
                }
                try await Task.sleep(nanoseconds: UInt64(delay))
                delay = min(delay * 2, 2_000_000_000)
            }
        } catch {
            if Task.isCancelled {
                try? await client.callVoid(
                    path: capability.path,
                    api: capability.name,
                    version: try selectedVersion(capability),
                    method: "stop",
                    requestFormat: capability.requestFormat,
                    parameters: ["taskid": .string(taskID)],
                    credential: credential
                )
            }
            throw error
        }
    }

    private func listParameters(offset: Int, limit: Int) -> [String: DsmParameterValue] {
        [
            "offset": .integer(offset),
            "limit": .integer(limit),
            "sort_by": .string("name"),
            "sort_direction": .string("asc"),
            "additional": .stringArray(Self.additionalFields)
        ]
    }

    private func makeFileItem(_ payload: FilePayload) -> FileItem {
        let rawType = payload.additional?.type
        let kind: FileKind
        if rawType?.lowercased().contains("link") == true {
            kind = .symlink
        } else {
            kind = payload.isDirectory ? .directory : .file
        }

        let rights = payload.additional?.perm?.advRight ?? [:]
        let permissions = FilePermissions(
            canRead: rights["read"] ?? rights["download"] ?? true,
            canWrite: rights["write"] ?? rights["upload"] ?? false,
            canDelete: rights["delete"] ?? false,
            posixMode: payload.additional?.perm?.posix
        )
        let time = payload.additional?.time
        let times = FileTimes(
            modifiedAt: time?.mtime.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            createdAt: time?.crtime.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            accessedAt: time?.atime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
        let fileExtension = URL(fileURLWithPath: payload.name).pathExtension.lowercased()
        let thumbnail = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp"]
            .contains(fileExtension)

        return FileItem(
            profileID: profileID,
            name: payload.name,
            path: payload.path,
            kind: kind,
            sizeBytes: payload.additional?.size,
            fileExtension: fileExtension,
            owner: payload.additional?.owner?.user,
            group: payload.additional?.owner?.group,
            times: times,
            permissions: permissions,
            thumbnailAvailable: thumbnail,
            rawType: rawType
        )
    }

    private func requireCapability(_ name: String) throws -> ApiCapability {
        guard let capability = capabilities[name], capability.selectedVersion != nil else {
            throw AppError(
                category: .apiUnavailable,
                isRetryable: false,
                safeUserMessage: "这台 NAS 未启用所需的 File Station 功能。"
            )
        }
        return capability
    }

    private func selectedVersion(_ capability: ApiCapability) throws -> Int {
        guard let version = capability.selectedVersion else {
            throw AppError(
                category: .versionUnsupported,
                isRetryable: false,
                safeUserMessage: "这台 NAS 的 File Station 版本暂不受支持。"
            )
        }
        return version
    }

    private func apiURL(path: String) -> URL {
        var url = baseURL.appendingPathComponent("webapi", isDirectory: true)
        for segment in path.split(separator: "/") {
            url.appendPathComponent(String(segment), isDirectory: false)
        }
        return url
    }

    private func validateUploadSuccess(_ response: DsmHTTPResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw AppError(
                category: response.statusCode >= 500 ? .serverBusy : .invalidResponse,
                isRetryable: response.statusCode >= 500,
                safeUserMessage: "NAS 没有接受这次文件传输，请检查当前用户的权限。",
                httpStatus: response.statusCode
            )
        }
        guard let envelope = try? JSONDecoder().decode(BinaryEnvelope.self, from: response.data) else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: "上传没有完成，NAS 返回的信息无法读取。"
            )
        }
        if let error = envelope.error {
            throw uploadError(code: error.code)
        }
        guard envelope.success else {
            throw AppError(
                category: .unknown,
                isRetryable: false,
                safeUserMessage: "NAS 无法完成这次文件操作。"
            )
        }
    }

    private func uploadError(code: Int) -> AppError {
        switch code {
        case 105:
            AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: "当前用户没有执行此操作的权限。",
                dsmCode: code
            )
        case 106, 107, 119:
            AppError(
                category: .authenticationRequired,
                isRetryable: false,
                safeUserMessage: "登录已过期，请重新登录。",
                dsmCode: code
            )
        case 108:
            AppError(
                category: .unknown,
                isRetryable: false,
                safeUserMessage: "文件上传失败，请检查 NAS 剩余空间或传输状态。",
                dsmCode: code
            )
        case 115:
            AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: "当前目录下不允许上传文件，请确认权限与服务器策略。",
                dsmCode: code
            )
        case 1800:
            AppError(
                category: .invalidResponse,
                isRetryable: true,
                safeUserMessage: "上传的数据不完整，请重试。",
                dsmCode: code
            )
        case 1801:
            AppError(
                category: .timeout,
                isRetryable: true,
                safeUserMessage: "上传等待超时，请检查网络后重试。",
                dsmCode: code
            )
        case 1802:
            AppError(
                category: .invalidResponse,
                isRetryable: true,
                safeUserMessage: "NAS 没有收到文件名，请重新选择文件。",
                dsmCode: code
            )
        case 1803:
            AppError(
                category: .cancelled,
                isRetryable: true,
                safeUserMessage: "上传已取消。",
                dsmCode: code
            )
        case 1804:
            AppError(
                category: .remoteStorageFull,
                isRetryable: false,
                safeUserMessage: "目标存储不支持这么大的文件。",
                dsmCode: code
            )
        case 1805:
            AppError(
                category: .conflict,
                isRetryable: false,
                safeUserMessage: "目标文件夹中已有同名文件，请选择覆盖上传或先改名。",
                dsmCode: code
            )
        default:
            AppError(
                category: .unknown,
                isRetryable: false,
                safeUserMessage: "NAS 没有完成上传，请稍后重试。(错误码: \(code))",
                dsmCode: code
            )
        }
    }

    private func downloadError(code: Int) -> AppError {
        switch code {
        case 105:
            AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: "当前用户没有执行此操作的权限。",
                dsmCode: code
            )
        case 106, 107, 119:
            AppError(
                category: .authenticationRequired,
                isRetryable: false,
                safeUserMessage: "登录已过期，请重新登录。",
                dsmCode: code
            )
        default:
            AppError(
                category: .unknown,
                isRetryable: false,
                safeUserMessage: "下载失败，NAS 无法读取该文件。",
                dsmCode: code
            )
        }
    }

    private func validateBinaryResponse(_ response: DsmHTTPResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw AppError(
                category: response.statusCode >= 500 ? .serverBusy : .invalidResponse,
                isRetryable: response.statusCode >= 500,
                safeUserMessage: "下载没有完成，请稍后重试。",
                httpStatus: response.statusCode
            )
        }
        let contentType = response.headers["content-type"]?.lowercased() ?? ""
        if contentType.contains("application/json"),
           let envelope = try? JSONDecoder().decode(BinaryEnvelope.self, from: data) {
            if !envelope.success {
                let errorCode = envelope.error?.code ?? -1
                throw downloadError(code: errorCode)
            }
        }
        if contentType.contains("text/html") {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: "下载失败，请确认当前用户有权读取这个文件。"
            )
        }
    }

    private func translate(_ error: Error) -> Error {
        if Task.isCancelled {
            return CancellationError()
        }
        if error is CancellationError || error is MemoryPipeError {
            return CancellationError()
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return CancellationError()
        }
        if error is AppError || error is DsmCertificateTrustError {
            return error
        }
        if let error = error as? URLError {
            return DsmErrorMapper.map(
                .transport(code: error.errorCode, requestID: UUID())
            )
        }
        return AppError(
            category: .unknown,
            isRetryable: false,
            safeUserMessage: "文件操作没有完成。"
        )
    }

    private func createMultipartBody(
        localURL: URL,
        boundary: String,
        fields: [String: String]
    ) throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanStashUpload-\(UUID().uuidString).multipart")
        guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil) else {
            throw AppError(
                category: .localStorageFull,
                isRetryable: false,
                safeUserMessage: "无法创建上传临时文件。"
            )
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: bodyURL.path
        )

        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }
        func write(_ string: String) throws {
            guard let data = string.data(using: .utf8) else {
                throw DsmRequestError.parameterEncodingFailed
            }
            try output.write(contentsOf: data)
        }

        for (name, value) in fields.sorted(by: { $0.key < $1.key }) where !value.isEmpty {
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            try write("\(value)\r\n")
        }

        let safeFilename = localURL.lastPathComponent
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\"", with: "'")
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\n")
        try write("Content-Type: application/octet-stream\r\n\r\n")

        let input = try FileHandle(forReadingFrom: localURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try write("\r\n--\(boundary)--\r\n")
        return bodyURL
    }

    private static let additionalFields = [
        "real_path", "size", "owner", "time", "perm", "mount_point_type", "type"
    ]
}

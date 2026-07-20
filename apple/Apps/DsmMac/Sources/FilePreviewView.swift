import AppKit
import AVKit
import CryptoKit
import DsmCore
import Observation
import PDFKit
import Security
import SwiftUI
import UniformTypeIdentifiers

private final class MediaLoadingContext: @unchecked Sendable {
    let loadingRequest: AVAssetResourceLoadingRequest
    let requestedOffset: Int64
    let maximumLength: Int
    var receivedLength = 0

    init(
        loadingRequest: AVAssetResourceLoadingRequest,
        requestedOffset: Int64,
        maximumLength: Int
    ) {
        self.loadingRequest = loadingRequest
        self.requestedOffset = requestedOffset
        self.maximumLength = maximumLength
    }
}

@MainActor
@Observable
final class PreviewWindowPresentationState {
    var isFullScreen = false
}

final class DsmAVAssetResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private let source: MediaStreamSource
    private let onFailure: @Sendable (String) -> Void
    private let onLoadingMetrics: @Sendable (Double?, Bool) -> Void
    private var session: URLSession!
    private var activeRequests = [URLSessionDataTask: MediaLoadingContext]()
    private let lock = NSLock()
    private var speedWindowStartedAt = Date()
    private var speedWindowBytes: Int64 = 0
    private var smoothedBytesPerSecond: Double?

    init(
        source: MediaStreamSource,
        onFailure: @escaping @Sendable (String) -> Void,
        onLoadingMetrics: @escaping @Sendable (Double?, Bool) -> Void
    ) {
        self.source = source
        self.onFailure = onFailure
        self.onLoadingMetrics = onLoadingMetrics
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func cancelAll() {
        let requests = lock.withLock {
            let values = Array(activeRequests.values)
            activeRequests.removeAll()
            return values
        }
        session.invalidateAndCancel()
        onLoadingMetrics(nil, false)
        for context in requests {
            context.loadingRequest.finishLoading(with: CancellationError())
        }
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        let dataRequest = loadingRequest.dataRequest
        let offset = max(dataRequest?.currentOffset ?? dataRequest?.requestedOffset ?? 0, 0)
        let requestedLength = max(dataRequest?.requestedLength ?? 1, 1)
        // 防止播放器或异常媒体一次请求整个大文件；AVFoundation 会按需继续请求后续区间。
        let maximumLength = min(requestedLength, 16 * 1_024 * 1_024)

        var request = source.request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "bytes=\(offset)-\(offset + Int64(maximumLength) - 1)",
            forHTTPHeaderField: "Range"
        )

        let task = session.dataTask(with: request)
        lock.withLock {
            if activeRequests.isEmpty {
                speedWindowStartedAt = Date()
                speedWindowBytes = 0
                smoothedBytesPerSecond = nil
            }
            activeRequests[task] = MediaLoadingContext(
                loadingRequest: loadingRequest,
                requestedOffset: offset,
                maximumLength: maximumLength
            )
        }
        onLoadingMetrics(nil, true)
        task.resume()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        lock.withLock {
            if let task = activeRequests.first(where: { $0.value.loadingRequest == loadingRequest })?.key {
                task.cancel()
                activeRequests.removeValue(forKey: task)
            }
        }
        publishIdleIfNeeded()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        let context = activeRequests[dataTask]
        lock.unlock()

        guard let context, let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(dataTask, message: "媒体服务没有返回可读取的数据。")
            return
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased()
        guard (200..<300).contains(httpResponse.statusCode),
              contentType?.contains("application/json") != true,
              contentType?.contains("text/html") != true else {
            completionHandler(.cancel)
            finish(dataTask, message: "NAS 没有返回可播放的媒体内容，请重新登录后重试。")
            return
        }

        let contentRange = Self.parseContentRange(
            httpResponse.value(forHTTPHeaderField: "Content-Range")
        )
        let supportsRange = httpResponse.statusCode == 206 && contentRange != nil
        if context.requestedOffset > 0 && !supportsRange {
            completionHandler(.cancel)
            finish(dataTask, message: "这台 NAS 没有响应媒体分段读取，暂时无法流式播放。")
            return
        }
        if let contentRange, contentRange.start != context.requestedOffset {
            completionHandler(.cancel)
            finish(dataTask, message: "NAS 返回的媒体片段位置不正确，请重试。")
            return
        }

        if let infoRequest = context.loadingRequest.contentInformationRequest {
            infoRequest.contentType = Self.typeIdentifier(
                mimeType: contentType,
                fileExtension: source.fileExtension
            )
            infoRequest.isByteRangeAccessSupported = supportsRange
            if let total = contentRange?.total ?? source.expectedContentLength {
                infoRequest.contentLength = total
            } else if httpResponse.statusCode == 200,
                      let length = httpResponse.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init) {
                infoRequest.contentLength = length
            }
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        let context = activeRequests[dataTask]
        lock.unlock()

        guard let context else { return }
        let remaining = context.maximumLength - context.receivedLength
        guard remaining > 0 else {
            finish(dataTask)
            return
        }
        let accepted = data.prefix(remaining)
        if !accepted.isEmpty {
            context.loadingRequest.dataRequest?.respond(with: Data(accepted))
            context.receivedLength += accepted.count
            recordReceivedBytes(accepted.count)
        }
        if context.receivedLength >= context.maximumLength {
            finish(dataTask)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let dataTask = task as? URLSessionDataTask else { return }
        let context = lock.withLock { activeRequests.removeValue(forKey: dataTask) }
        guard let context else { return }
        if let error, (error as? URLError)?.code != .cancelled {
            context.loadingRequest.finishLoading(with: error)
            onFailure("媒体读取中断，请检查网络后重试。")
        } else {
            context.loadingRequest.finishLoading()
        }
        publishIdleIfNeeded()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard request.url?.host?.lowercased() == source.expectedHost.lowercased() else {
            completionHandler(nil)
            if let dataTask = task as? URLSessionDataTask {
                finish(dataTask, message: "媒体地址发生了意外变化，已停止播放以保护登录信息。")
            }
            return
        }
        completionHandler(request)
    }

    // MARK: - URLSessionDelegate (TLS)

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    private func handleChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == source.expectedHost.lowercased(),
              let serverTrust = challenge.protectionSpace.serverTrust,
              let certificate = (SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate])?.first else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var systemError: CFError?
        let systemTrusted = SecTrustEvaluateWithError(serverTrust, &systemError)
        let fingerprint = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
            .map { String(format: "%02X", $0) }
            .joined()
        let pin = source.pinnedCertificateSHA256?
            .replacingOccurrences(of: ":", with: "")
            .uppercased()

        if systemTrusted, pin == nil || pin == fingerprint {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }
        if pin == fingerprint,
           SecTrustSetPolicies(serverTrust, SecPolicyCreateBasicX509()) == errSecSuccess,
           SecTrustSetAnchorCertificates(serverTrust, [certificate] as CFArray) == errSecSuccess,
           SecTrustSetAnchorCertificatesOnly(serverTrust, true) == errSecSuccess {
            var pinnedError: CFError?
            if SecTrustEvaluateWithError(serverTrust, &pinnedError) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }
        completionHandler(.cancelAuthenticationChallenge, nil)
        onFailure("无法确认媒体来源的安全信息，请重新连接这台 NAS。")
    }

    private func finish(_ task: URLSessionDataTask, message: String? = nil) {
        let context = lock.withLock { activeRequests.removeValue(forKey: task) }
        guard let context else { return }
        if let message {
            let error = NSError(
                domain: "LanStashMediaStream",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
            context.loadingRequest.finishLoading(with: error)
            onFailure(message)
        } else {
            context.loadingRequest.finishLoading()
        }
        task.cancel()
        publishIdleIfNeeded()
    }

    private func recordReceivedBytes(_ count: Int) {
        let result: (Double, Bool)? = lock.withLock {
            speedWindowBytes += Int64(count)
            let elapsed = Date().timeIntervalSince(speedWindowStartedAt)
            guard elapsed >= 0.25 else { return nil }
            let instantSpeed = Double(speedWindowBytes) / elapsed
            if let previous = smoothedBytesPerSecond {
                smoothedBytesPerSecond = previous * 0.65 + instantSpeed * 0.35
            } else {
                smoothedBytesPerSecond = instantSpeed
            }
            speedWindowStartedAt = Date()
            speedWindowBytes = 0
            return (smoothedBytesPerSecond ?? instantSpeed, !activeRequests.isEmpty)
        }
        if let result {
            onLoadingMetrics(result.0, result.1)
        }
    }

    private func publishIdleIfNeeded() {
        let isLoading = lock.withLock { !activeRequests.isEmpty }
        if !isLoading {
            onLoadingMetrics(nil, false)
        }
    }

    private static func parseContentRange(
        _ value: String?
    ) -> (start: Int64, end: Int64, total: Int64?)? {
        guard let value,
              value.lowercased().hasPrefix("bytes ") else { return nil }
        let parts = value.dropFirst(6).split(separator: "/", maxSplits: 1)
        guard let rangePart = parts.first else { return nil }
        let bounds = rangePart.split(separator: "-", maxSplits: 1)
        guard bounds.count == 2,
              let start = Int64(bounds[0]),
              let end = Int64(bounds[1]),
              end >= start else { return nil }
        let total = parts.count == 2 && parts[1] != "*" ? Int64(parts[1]) : nil
        return (start, end, total)
    }

    private static func typeIdentifier(
        mimeType: String?,
        fileExtension: String?
    ) -> String {
        if let mimeType, let type = UTType(mimeType: mimeType) {
            return type.identifier
        }
        if let fileExtension, let type = UTType(filenameExtension: fileExtension) {
            return type.identifier
        }
        return AVFileType.mp4.rawValue
    }
}

struct FileDetailView: View {
    @Bindable var model: WorkspaceModel
    @Bindable var windowState: PreviewWindowPresentationState
    let onDownload: (FileItem, WorkspaceModel.FolderDownloadMode) -> Void
    let onDelete: ([FileItem]) -> Void
    let onRestore: (FileItem) -> Void
    @State private var confirmsDiscardAndClose = false
    @State private var confirmsCancelEditing = false
    @State private var livePhotoPlayer: AVPlayer?
    @State private var livePhotoResourceLoaderDelegate: DsmAVAssetResourceLoaderDelegate?

    var body: some View {
        Group {
            if windowState.isFullScreen, let item = model.selectedItem, supportsFullScreen {
                fullScreenPreview(item)
            } else {
                standardPreview
            }
        }
        .background {
            PreviewSpaceShortcutHandler {
                requestClose()
            }
        }
        .alert("放弃未保存的修改？", isPresented: $confirmsDiscardAndClose) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃修改", role: .destructive) {
                model.cancelTextEditing()
                model.dismissPreview()
            }
        } message: {
            Text("关闭后，尚未保存到 NAS 的修改会丢失。")
        }
        .alert("取消这次编辑？", isPresented: $confirmsCancelEditing) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃修改", role: .destructive) {
                model.cancelTextEditing()
            }
        } message: {
            Text("尚未保存到 NAS 的修改会丢失。")
        }
    }

    private var standardPreview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("项目详情")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if supportsFullScreen {
                    Button {
                        NSApp.keyWindow?.toggleFullScreen(nil)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("f", modifiers: [.command, .control])
                    .help("进入或退出全屏（⌃⌘F）")
                    .accessibilityLabel("进入或退出全屏")
                }
                Button {
                    requestClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .disabled(model.isSavingText)
                .help("关闭预览窗口")
                .accessibilityLabel("关闭预览窗口")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            Divider()

            Group {
                if model.selection.count > 1 {
                    ContentUnavailableView(
                        "已选择 \(model.selection.count) 个项目",
                        systemImage: "checkmark.circle",
                        description: Text("可从工具栏下载或删除所选项目。")
                    )
                } else if let item = model.selectedItem {
                    detail(for: item)
                } else {
                    ContentUnavailableView(
                        "选择一个项目",
                        systemImage: "sidebar.right",
                        description: Text("文件详情和预览会显示在这里。")
                    )
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var supportsFullScreen: Bool {
        guard let item = model.selectedItem else { return false }
        let kind = model.resolvedPreviewKind ?? PreviewKind.classify(item)
        return kind == .image || kind == .video
    }

    private func fullScreenPreview(_ item: FileItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            preview(item)
                .ignoresSafeArea()
            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.48), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: [.command, .control])
            .help("退出全屏（⌃⌘F）")
            .accessibilityLabel("退出全屏")
            .padding(20)
        }
    }

    private func livePhotoVideoPath(for item: FileItem) -> String? {
        if model.section == .photos {
            if let photoItem = model.photoLibrary.displayedItems.first(where: { $0.id == item.id }),
               let videoPath = photoItem.livePhotoVideoPath {
                return videoPath
            }
        }
        let directory = (item.path as NSString).deletingLastPathComponent
        let stem = ((item.name as NSString).deletingPathExtension).lowercased()
        for candidate in model.filteredItems {
            guard candidate.id != item.id else { continue }
            let candidateDir = (candidate.path as NSString).deletingLastPathComponent
            let candidateStem = ((candidate.name as NSString).deletingPathExtension).lowercased()
            let candidateExt = candidate.fileExtension?.lowercased() ?? ""
            if candidateDir == directory && candidateStem == stem && ["mov", "mp4"].contains(candidateExt) {
                return candidate.path
            }
        }
        return nil
    }

    private func detail(for item: FileItem) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                FileIcon(item: item)
                    .font(.system(size: 30))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                        if let videoPath = livePhotoVideoPath(for: item) {
                            LivePhotoPreviewBadgeButton(
                                model: model,
                                item: item,
                                videoPath: videoPath,
                                player: $livePhotoPlayer,
                                resourceLoaderDelegate: $livePhotoResourceLoaderDelegate
                            )
                        }
                    }
                    Text(item.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            if item.isDirectory {
                folderDetails(item)
            } else {
                preview(item)
            }

        }
        .onChange(of: item.id) { _, _ in
            livePhotoPlayer?.pause()
            livePhotoPlayer = nil
            livePhotoResourceLoaderDelegate?.cancelAll()
            livePhotoResourceLoaderDelegate = nil
        }
    }

    @ViewBuilder
    private func preview(_ item: FileItem) -> some View {
        switch model.preview {
        case .empty:
            Color.clear
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("正在准备预览…")
                    .foregroundStyle(.secondary)
                if let speed = model.previewLoadingSpeedBytesPerSecond, speed > 0 {
                    Text("读取速度 \(networkSpeedText(speed))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .image(let data):
            if let image = NSImage(data: data) {
                ZStack {
                    FittedImagePreview(image: image)
                        .id(item.id)
                    if livePhotoPlayer != nil {
                        VideoPlayerRepresentable(
                            player: $livePhotoPlayer,
                            controlsStyle: .none,
                            showsFrameSteppingButtons: false,
                            showsSharingServiceButton: false
                        )
                        .background(Color.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if model.canPreviewPreviousImage || model.canPreviewNextImage {
                        HStack {
                            imageNavigationButton(
                                title: "上一张",
                                systemImage: "chevron.left",
                                isEnabled: model.canPreviewPreviousImage,
                                shortcut: .leftArrow,
                                action: model.previewPreviousImage
                            )
                            Spacer()
                            imageNavigationButton(
                                title: "下一张",
                                systemImage: "chevron.right",
                                isEnabled: model.canPreviewNextImage,
                                shortcut: .rightArrow,
                                action: model.previewNextImage
                            )
                        }
                        .padding(.horizontal, 18)
                    }
                }
            } else {
                previewMessage("无法读取这张图片。", systemImage: "photo.badge.exclamationmark") {
                    onDownload(item, .archive)
                }
            }
        case .text(let text, let truncated):
            VStack(spacing: 0) {
                if truncated {
                    Label("较大的文件仅显示开头内容", systemImage: "scissors")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(8)
                }
                HStack(spacing: 10) {
                    if model.isEditingText {
                        Button("取消") {
                            if model.hasUnsavedTextEdits {
                                confirmsCancelEditing = true
                            } else {
                                model.cancelTextEditing()
                            }
                        }
                        .disabled(model.isSavingText)
                        if model.canFormatSelectedText {
                            Button("整理格式") {
                                model.formatEditableText()
                            }
                            .disabled(model.isSavingText)
                            .help("整理支持格式的缩进与换行")
                        }
                        Spacer()
                        Button {
                            Task { await model.saveTextEdits() }
                        } label: {
                            if model.isSavingText {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("正在保存…")
                                }
                            } else {
                                Text("保存")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(model.isSavingText || !model.hasUnsavedTextEdits)
                    } else {
                        Spacer()
                        if model.canEditSelectedText {
                            Button("编辑") {
                                model.beginTextEditing()
                            }
                            .keyboardShortcut("e", modifiers: .command)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))

                if let message = model.textEditingMessage {
                    Label(
                        message,
                        systemImage: model.textEditingMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(model.textEditingMessageIsError ? .red : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if model.isEditingText {
                    TextEditor(text: $model.editableText)
                        .font(.system(.callout, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor))
                        .accessibilityLabel("编辑 \(item.name)")
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Text(text)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
            }
        case .pdf(let url):
            PDFDocumentView(url: url)
        case .video(let source):
            VideoPlayerView(source: source) {
                onDownload(item, .archive)
            }
        case .audio(let source):
            AudioPlayerView(source: source)
        case .unsupported(let message):
            previewMessage(message, systemImage: "doc.questionmark") {
                onDownload(item, .archive)
            }
        case .failed(let message):
            previewMessage(message, systemImage: "exclamationmark.triangle", color: .red) {
                onDownload(item, .archive)
            }
        }
    }

    private func requestClose() {
        guard !model.isSavingText else { return }
        if model.hasUnsavedTextEdits {
            confirmsDiscardAndClose = true
        } else {
            model.dismissPreview()
        }
    }

    private func imageNavigationButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        shortcut: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.32)
        .keyboardShortcut(shortcut, modifiers: [])
        .help("\(title)（方向键）")
        .accessibilityLabel(title)
    }

    private func folderDetails(_ item: FileItem) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.fill")
                .font(.system(size: 72))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
            Text("双击文件夹以浏览内容")
                .foregroundStyle(.secondary)
            Button("打开文件夹") {
                Task { await model.open(item) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewMessage(
        _ message: String,
        systemImage: String,
        color: Color = .secondary,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(color)
            Text("无法预览")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button("下载文件…", action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PreviewSpaceShortcutHandler: NSViewRepresentable {
    let onSpace: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSpace: onSpace) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSpace = onSpace
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSpace: () -> Void
        private weak var hostView: NSView?
        private var monitor: Any?

        init(onSpace: @escaping () -> Void) {
            self.onSpace = onSpace
        }

        func attach(to view: NSView) {
            hostView = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor [weak self] event in
                guard let self,
                      event.window === self.hostView?.window,
                      !self.isEditingText(in: event.window),
                      event.keyCode == 49,
                      event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
                    return event
                }
                self.onSpace()
                return nil
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func isEditingText(in window: NSWindow?) -> Bool {
            window?.firstResponder is NSTextView
        }
    }
}

private struct FittedImagePreview: View {
    let image: NSImage
    @State private var zoom: CGFloat = 1
    @State private var rotation = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(1, geometry.size.width - 32)
            let availableHeight = max(1, geometry.size.height - 88)
            let originalWidth = max(1, image.size.width)
            let originalHeight = max(1, image.size.height)
            let isQuarterTurn = abs(rotation) % 180 == 90
            let rotatedWidth = isQuarterTurn ? originalHeight : originalWidth
            let rotatedHeight = isQuarterTurn ? originalWidth : originalHeight
            let fittedScale = min(1, availableWidth / rotatedWidth, availableHeight / rotatedHeight)
            let imageWidth = originalWidth * fittedScale * zoom
            let imageHeight = originalHeight * fittedScale * zoom
            let visualWidth = isQuarterTurn ? imageHeight : imageWidth
            let visualHeight = isQuarterTurn ? imageWidth : imageHeight

            ZStack(alignment: .bottom) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: imageWidth, height: imageHeight)
                    .rotationEffect(.degrees(Double(rotation)))
                    .frame(width: visualWidth, height: visualHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .clipped()

                HStack(spacing: 4) {
                    previewControl("向左旋转", systemImage: "rotate.left") {
                        updateRotation(by: -90)
                    }
                    .keyboardShortcut("l", modifiers: .command)
                    previewControl("向右旋转", systemImage: "rotate.right") {
                        updateRotation(by: 90)
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    Divider().frame(height: 22).padding(.horizontal, 4)
                    previewControl("缩小", systemImage: "minus.magnifyingglass") {
                        updateZoom(zoom - 0.2)
                    }
                    .keyboardShortcut("-", modifiers: .command)
                    Text("\(Int((zoom * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 44)
                        .accessibilityLabel("缩放比例百分之 \(Int((zoom * 100).rounded()))")
                    previewControl("放大", systemImage: "plus.magnifyingglass") {
                        updateZoom(zoom + 0.2)
                    }
                    .keyboardShortcut("=", modifiers: .command)
                    Button("适合窗口") {
                        updateZoom(1)
                    }
                    .buttonStyle(.borderless)
                    .disabled(zoom == 1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 10)
            }
            .background {
                ImageScrollWheelReader { delta, isPrecise in
                    let step = isPrecise ? delta * 0.012 : delta * 0.08
                    updateZoom(zoom + step)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityLabel("图片预览，可使用滚轮缩放")
    }

    private func previewControl(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func updateZoom(_ value: CGFloat) {
        let newValue = min(5, max(0.25, value))
        if reduceMotion {
            zoom = newValue
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                zoom = newValue
            }
        }
    }

    private func updateRotation(by degrees: Int) {
        let newValue = (rotation + degrees) % 360
        if reduceMotion {
            rotation = newValue
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                rotation = newValue
            }
        }
    }
}

private struct ImageScrollWheelReader: NSViewRepresentable {
    let onScroll: (CGFloat, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onScroll: (CGFloat, Bool) -> Void
        private weak var hostView: NSView?
        private var monitor: Any?

        init(onScroll: @escaping (CGFloat, Bool) -> Void) {
            self.onScroll = onScroll
        }

        func attach(to view: NSView) {
            hostView = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { @MainActor [weak self] event in
                guard let self,
                      event.window === self.hostView?.window,
                      let hostView = self.hostView else { return event }
                let point = hostView.convert(event.locationInWindow, from: nil)
                guard hostView.bounds.contains(point) else { return event }
                self.onScroll(event.scrollingDeltaY, event.hasPreciseScrollingDeltas)
                return nil
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

private struct PDFDocumentView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            view.autoScales = true
        }
    }
}

struct VideoPlayerView: View {
    let source: MediaStreamSource
    let onDownload: () -> Void
    @State private var player: AVPlayer?
    @State private var resourceLoaderDelegate: DsmAVAssetResourceLoaderDelegate?
    @State private var playbackGeneration = UUID()
    @State private var isPreparing = true
    @State private var failureMessage: String?
    @State private var networkSpeed: Double?
    @State private var isNetworkLoading = false

    var body: some View {
        ZStack {
            VideoPlayerRepresentable(player: $player)

            if isPreparing, failureMessage == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在缓冲视频…")
                        .foregroundStyle(.secondary)
                    if let networkSpeed, networkSpeed > 0 {
                        Text("读取速度 \(networkSpeedText(networkSpeed))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
            }

            if !isPreparing, failureMessage == nil, isNetworkLoading,
               let networkSpeed, networkSpeed > 0 {
                VStack {
                    HStack {
                        Spacer()
                        Label(networkSpeedText(networkSpeed), systemImage: "arrow.down.circle")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .accessibilityLabel("视频读取速度 \(networkSpeedText(networkSpeed))")
                    }
                    Spacer()
                }
                .padding(14)
                .allowsHitTesting(false)
            }

            if let failureMessage {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("视频无法播放")
                        .font(.headline)
                    Text(failureMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack {
                    Button("重试") {
                        setupPlayer()
                    }
                        Button("下载文件…", action: onDownload)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .frame(maxWidth: 420)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .contain)
            }
        }
            .onAppear {
                setupPlayer()
            }
            .onDisappear {
                cleanPlayer()
            }
            .onChange(of: source.request.url) { _, _ in
                setupPlayer()
            }
    }

    private func setupPlayer() {
        cleanPlayer()
        isPreparing = true
        failureMessage = nil
        networkSpeed = nil
        isNetworkLoading = false
        let generation = UUID()
        playbackGeneration = generation

        let delegate = DsmAVAssetResourceLoaderDelegate(source: source) { message in
            Task { @MainActor in
                guard playbackGeneration == generation else { return }
                isPreparing = false
                failureMessage = message.replacingOccurrences(of: "媒体", with: "视频")
                player?.pause()
            }
        } onLoadingMetrics: { speed, isLoading in
            Task { @MainActor in
                guard playbackGeneration == generation else { return }
                networkSpeed = speed
                isNetworkLoading = isLoading
            }
        }
        resourceLoaderDelegate = delegate

        let suffix = source.fileExtension.map { ".\($0)" } ?? ".mp4"
        guard let assetURL = URL(string: "lanstash-media://stream/\(UUID().uuidString)\(suffix)") else {
            failureMessage = "无法准备视频播放器。"
            isPreparing = false
            return
        }
        let asset = AVURLAsset(url: assetURL)
        asset.resourceLoader.setDelegate(
            delegate,
            queue: DispatchQueue(label: "io.github.qwertyuiop1995.lanstash.media-loader")
        )
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer

        Task {
            do {
                let playable = try await asset.load(.isPlayable)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard playbackGeneration == generation else { return }
                    guard playable else {
                        isPreparing = false
                        failureMessage = "视频编码不受这台 Mac 支持。请下载后使用其他播放器打开。"
                        return
                    }
                    isPreparing = false
                    newPlayer.play()
                }
            } catch {
                await MainActor.run {
                    guard playbackGeneration == generation, failureMessage == nil else { return }
                    isPreparing = false
                    failureMessage = "视频信息读取失败，请检查网络后重试。"
                }
            }
        }
    }

    private func cleanPlayer() {
        playbackGeneration = UUID()
        player?.pause()
        player = nil
        resourceLoaderDelegate?.cancelAll()
        resourceLoaderDelegate = nil
        networkSpeed = nil
        isNetworkLoading = false
    }
}

struct VideoPlayerRepresentable: NSViewRepresentable {
    @Binding var player: AVPlayer?
    var controlsStyle: AVPlayerViewControlsStyle = .floating
    var showsFrameSteppingButtons: Bool = true
    var showsSharingServiceButton: Bool = true

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = controlsStyle
        view.showsFrameSteppingButtons = showsFrameSteppingButtons
        view.showsSharingServiceButton = showsSharingServiceButton
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player != player {
            view.player = player
        }
    }
}

struct AudioPlayerView: View {
    let source: MediaStreamSource
    @State private var player: AVPlayer?
    @State private var resourceLoaderDelegate: DsmAVAssetResourceLoaderDelegate?
    @State private var playbackGeneration = UUID()
    @State private var isPlaying = false
    @State private var isPreparing = true
    @State private var isSeeking = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timer: Timer?
    @State private var failureMessage: String?
    @State private var networkSpeed: Double?
    @State private var isNetworkLoading = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // 音频播放精美图标
            Image(systemName: "music.note.waveform")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)
                .symbolEffect(.bounce, value: isPlaying)
                .accessibilityHidden(true)

            if isPreparing, failureMessage == nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在缓冲音乐…")
                        .foregroundStyle(.secondary)
                    if let networkSpeed, networkSpeed > 0 {
                        Text("读取速度 \(networkSpeedText(networkSpeed))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            if !isPreparing, failureMessage == nil, isNetworkLoading,
               let networkSpeed, networkSpeed > 0 {
                Label("正在读取 · \(networkSpeedText(networkSpeed))", systemImage: "arrow.down.circle")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel("音乐读取速度 \(networkSpeedText(networkSpeed))")
            }

            if let failureMessage {
                VStack(spacing: 10) {
                    Label("音乐无法播放", systemImage: "waveform.badge.exclamationmark")
                        .font(.headline)
                    Text(failureMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        setupPlayer()
                    }
                }
                .padding(.horizontal, 24)
                .accessibilityElement(children: .contain)
            }
            
            VStack(spacing: 8) {
                Slider(value: $currentTime, in: 0...max(duration, 1.0)) { editing in
                    isSeeking = editing
                    if !editing {
                        player?.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                    }
                }
                .tint(.blue)
                .disabled(isPreparing || failureMessage != nil || duration <= 0)
                .accessibilityLabel("播放进度")
                
                HStack {
                    Text(formatTime(currentTime))
                    Spacer()
                    Text(formatTime(duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
            
            // 控制按钮
            HStack(spacing: 24) {
                Button {
                    let newTime = max(currentTime - 10, 0)
                    player?.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
                    currentTime = newTime
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(isPreparing || failureMessage != nil)
                .accessibilityLabel("后退 10 秒")
                
                Button {
                    if isPlaying {
                        player?.pause()
                        isPlaying = false
                    } else {
                        player?.play()
                        isPlaying = true
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(isPreparing || failureMessage != nil)
                .accessibilityLabel(isPlaying ? "暂停" : "播放")
                
                Button {
                    let newTime = min(currentTime + 10, duration)
                    player?.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
                    currentTime = newTime
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(isPreparing || failureMessage != nil)
                .accessibilityLabel("前进 10 秒")
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanPlayer()
        }
        .onChange(of: source.request.url) { _, _ in
            setupPlayer()
        }
    }

    private func setupPlayer() {
        cleanPlayer()
        isPreparing = true
        failureMessage = nil
        networkSpeed = nil
        isNetworkLoading = false
        let generation = UUID()
        playbackGeneration = generation

        let delegate = DsmAVAssetResourceLoaderDelegate(source: source) { message in
            Task { @MainActor in
                guard playbackGeneration == generation else { return }
                isPreparing = false
                failureMessage = message.replacingOccurrences(of: "媒体", with: "音乐")
                player?.pause()
                isPlaying = false
            }
        } onLoadingMetrics: { speed, isLoading in
            Task { @MainActor in
                guard playbackGeneration == generation else { return }
                networkSpeed = speed
                isNetworkLoading = isLoading
            }
        }
        resourceLoaderDelegate = delegate

        let suffix = source.fileExtension.map { ".\($0)" } ?? ".mp3"
        guard let assetURL = URL(string: "lanstash-media://stream/\(UUID().uuidString)\(suffix)") else {
            failureMessage = "无法准备音乐播放器。"
            isPreparing = false
            return
        }
        let asset = AVURLAsset(url: assetURL)
        asset.resourceLoader.setDelegate(
            delegate,
            queue: DispatchQueue(label: "io.github.qwertyuiop1995.lanstash.audio-loader")
        )
        let playerItem = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: playerItem)
        self.player = avPlayer

        Task {
            do {
                async let playableValue = asset.load(.isPlayable)
                async let durationValue = asset.load(.duration)
                let (playable, loadedDuration) = try await (playableValue, durationValue)
                await MainActor.run {
                    guard playbackGeneration == generation else { return }
                    guard playable else {
                        isPreparing = false
                        failureMessage = "音乐编码不受这台 Mac 支持，可以下载后使用其他播放器打开。"
                        return
                    }
                    let seconds = loadedDuration.seconds
                    duration = seconds.isFinite && seconds > 0 ? seconds : 0
                    isPreparing = false
                }
            } catch {
                await MainActor.run {
                    guard playbackGeneration == generation, failureMessage == nil else { return }
                    isPreparing = false
                    failureMessage = "音乐信息读取失败，请检查网络后重试。"
                }
            }
        }

        let currentPlayer = avPlayer
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak currentPlayer] _ in
            Task { @MainActor in
                if !isSeeking,
                   let current = currentPlayer?.currentTime().seconds,
                   current.isFinite {
                    currentTime = current
                }
            }
        }
    }

    private func cleanPlayer() {
        playbackGeneration = UUID()
        timer?.invalidate()
        timer = nil
        player?.pause()
        player = nil
        resourceLoaderDelegate?.cancelAll()
        resourceLoaderDelegate = nil
        networkSpeed = nil
        isNetworkLoading = false
        isPlaying = false
        isSeeking = false
        currentTime = 0
        duration = 0
    }

    private func formatTime(_ time: Double) -> String {
        guard !time.isNaN else { return "00:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private func networkSpeedText(_ bytesPerSecond: Double) -> String {
    let formatted = ByteCountFormatter.string(
        fromByteCount: Int64(max(0, bytesPerSecond)),
        countStyle: .file
    )
    return "\(formatted)/秒"
}

private struct LivePhotoPreviewBadgeButton: View {
    let model: WorkspaceModel
    let item: FileItem
    let videoPath: String
    @Binding var player: AVPlayer?
    @Binding var resourceLoaderDelegate: DsmAVAssetResourceLoaderDelegate?

    var body: some View {
        let isPlaying = player != nil
        Button {
            triggerLivePhoto()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isPlaying ? "livephoto.play" : "livephoto")
                    .font(.caption.weight(.bold))
                Text("LIVE")
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isPlaying ? Color.accentColor : Color.secondary.opacity(0.18), in: Capsule())
            .foregroundStyle(isPlaying ? .white : .primary)
        }
        .buttonStyle(.plain)
        .help("播放动态照片动画")
    }

    private func triggerLivePhoto() {
        guard player == nil else { return }
        Task {
            do {
                let source = try await model.mediaStreamSource(
                    path: videoPath,
                    fileExtension: "mov"
                )
                guard let assetURL = URL(string: "lanstash-media://stream/\(UUID().uuidString).mov") else { return }
                let asset = AVURLAsset(url: assetURL)
                let delegate = DsmAVAssetResourceLoaderDelegate(
                    source: source,
                    onFailure: { _ in },
                    onLoadingMetrics: { _, _ in }
                )
                asset.resourceLoader.setDelegate(
                    delegate,
                    queue: DispatchQueue(label: "io.github.qwertyuiop1995.lanstash.livephoto-loader")
                )
                let playerItem = AVPlayerItem(asset: asset)
                let avPlayer = AVPlayer(playerItem: playerItem)
                avPlayer.actionAtItemEnd = .pause

                // 先异步加载 asset.isPlayable，等资源加载器拿到内容信息后再播放，
                // 避免直接 play() 让主线程等待资源信息而卡死。
                await MainActor.run {
                    resourceLoaderDelegate = delegate
                }
                let playable = try await asset.load(.isPlayable)
                guard !Task.isCancelled else {
                    await MainActor.run {
                        resourceLoaderDelegate?.cancelAll()
                        resourceLoaderDelegate = nil
                    }
                    return
                }

                await MainActor.run {
                    guard playable else {
                        resourceLoaderDelegate?.cancelAll()
                        resourceLoaderDelegate = nil
                        return
                    }
                    player = avPlayer
                    avPlayer.play()
                }

                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    player?.pause()
                    player = nil
                    resourceLoaderDelegate?.cancelAll()
                    resourceLoaderDelegate = nil
                }
            } catch {
                await MainActor.run {
                    player?.pause()
                    player = nil
                    resourceLoaderDelegate?.cancelAll()
                    resourceLoaderDelegate = nil
                }
            }
        }
    }
}

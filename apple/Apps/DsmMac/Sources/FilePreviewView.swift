import AppKit
import AVKit
import CryptoKit
import DsmCore
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

final class DsmAVAssetResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private let source: MediaStreamSource
    private let onFailure: @Sendable (String) -> Void
    private var session: URLSession!
    private var activeRequests = [URLSessionDataTask: MediaLoadingContext]()
    private let lock = NSLock()

    init(
        source: MediaStreamSource,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        self.source = source
        self.onFailure = onFailure
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
            activeRequests[task] = MediaLoadingContext(
                loadingRequest: loadingRequest,
                requestedOffset: offset,
                maximumLength: maximumLength
            )
        }
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
    let onDownload: (FileItem) -> Void
    let onDelete: ([FileItem]) -> Void
    let onRestore: (FileItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("项目详情")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.isPreviewPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("关闭预览窗口")
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

    private func detail(for item: FileItem) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                FileIcon(item: item)
                    .font(.system(size: 30))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
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

            Divider()
            actionBar(item)
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .image(let data):
            if let image = NSImage(data: data) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 900, maxHeight: 900)
                        .padding(20)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                previewMessage("无法读取图片缩略图。", systemImage: "photo.badge.exclamationmark")
            }
        case .text(let text, let truncated):
            VStack(spacing: 0) {
                if truncated {
                    Label("较大的文件仅显示开头内容", systemImage: "scissors")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(8)
                }
                ScrollView([.horizontal, .vertical]) {
                    Text(text)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
        case .pdf(let url):
            PDFDocumentView(url: url)
        case .video(let source):
            VideoPlayerView(source: source)
        case .audio(let source):
            AudioPlayerView(source: source)
        case .unsupported(let message):
            previewMessage(message, systemImage: "doc.questionmark")
        case .failed(let message):
            previewMessage(message, systemImage: "exclamationmark.triangle", color: .red)
        }
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

    private func actionBar(_ item: FileItem) -> some View {
        HStack(spacing: 10) {
            if item.isDirectory {
                Button("打开") {
                    Task { await model.open(item) }
                }
            } else {
                Button("下载…") {
                    onDownload(item)
                }
                .buttonStyle(.borderedProminent)
            }
            if item.isRecyclePath {
                if model.allowsVerifiedRestore {
                    Button("恢复…") {
                        onRestore(item)
                    }
                } else {
                    Label("暂不支持直接恢复", systemImage: "lock.trianglebadge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button(item.isRecyclePath ? "永久删除…" : "删除…", role: .destructive) {
                onDelete([item])
            }
        }
        .padding(12)
    }

    private func previewMessage(
        _ message: String,
        systemImage: String,
        color: Color = .secondary
    ) -> some View {
        ContentUnavailableView {
            Label("无法预览", systemImage: systemImage)
        } description: {
            Text(message)
                .foregroundStyle(color)
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
    @State private var player: AVPlayer?
    @State private var resourceLoaderDelegate: DsmAVAssetResourceLoaderDelegate?
    @State private var playbackGeneration = UUID()
    @State private var isPreparing = true
    @State private var failureMessage: String?

    var body: some View {
        ZStack {
            VideoPlayerRepresentable(player: $player)

            if isPreparing, failureMessage == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在缓冲视频…")
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
            }

            if let failureMessage {
                ContentUnavailableView {
                    Label("视频无法播放", systemImage: "video.slash")
                } description: {
                    Text(failureMessage)
                } actions: {
                    Button("重试") {
                        setupPlayer()
                    }
                }
                .background(.regularMaterial)
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
        let generation = UUID()
        playbackGeneration = generation

        let delegate = DsmAVAssetResourceLoaderDelegate(source: source) { message in
            Task { @MainActor in
                guard playbackGeneration == generation else { return }
                isPreparing = false
                failureMessage = message.replacingOccurrences(of: "媒体", with: "视频")
                player?.pause()
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
                        failureMessage = "视频编码不受这台 Mac 支持，可以下载后使用其他播放器打开。"
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
    }
}

struct VideoPlayerRepresentable: NSViewRepresentable {
    @Binding var player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFrameSteppingButtons = true
        view.showsSharingServiceButton = true
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
                }
                .accessibilityElement(children: .combine)
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

import DsmCore
import Foundation

enum MemoryPipeError: Error {
    case cancelled
    case closed
    case unavailable
}

/// 跨 NAS 中转使用的系统有界流对，缓冲区满后由写入端等待读取端消费数据。
final class BoundedMemoryPipe: @unchecked Sendable {
    private let inputStream: InputStream
    private let outputStream: OutputStream
    private let capacity: Int
    private let stateLock = NSLock()
    private let onFileBytesWritten: @Sendable (Int) -> Void
    private var failure: Error?
    private var isClosed = false

    init(capacity: Int, onFileBytesRead: @escaping @Sendable (Int) -> Void) {
        self.capacity = max(capacity, 1)
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreateBoundPair(
            nil,
            &readStream,
            &writeStream,
            self.capacity
        )
        guard let readStream, let writeStream else {
            preconditionFailure("无法创建跨 NAS 内存流")
        }
        inputStream = readStream.takeRetainedValue() as InputStream
        outputStream = writeStream.takeRetainedValue() as OutputStream
        onFileBytesWritten = onFileBytesRead
        outputStream.open()
    }

    func makeInputStream() -> InputStream {
        inputStream
    }

    func write(_ data: Data, countsAsFileData: Bool) throws {
        guard !data.isEmpty else { return }
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            var offset = 0
            while offset < rawBuffer.count {
                try Task.checkCancellation()
                try checkWritable()
                guard outputStream.hasSpaceAvailable else {
                    Thread.sleep(forTimeInterval: 0.002)
                    continue
                }
                let count = outputStream.write(
                    baseAddress.advanced(by: offset),
                    maxLength: min(rawBuffer.count - offset, capacity)
                )
                if count < 0 {
                    throw outputStream.streamError ?? MemoryPipeError.unavailable
                }
                if count == 0 {
                    Thread.sleep(forTimeInterval: 0.002)
                    continue
                }
                offset += count
                if countsAsFileData {
                    onFileBytesWritten(count)
                }
            }
        }
    }

    func finish() {
        stateLock.lock()
        guard !isClosed else {
            stateLock.unlock()
            return
        }
        isClosed = true
        stateLock.unlock()
        outputStream.close()
    }

    func cancel(with error: Error = MemoryPipeError.cancelled) {
        stateLock.lock()
        failure = error
        isClosed = true
        stateLock.unlock()
        outputStream.close()
    }

    private func checkWritable() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let failure { throw failure }
        if isClosed { throw MemoryPipeError.closed }
    }
}

final class CrossNASProgressState: @unchecked Sendable {
    private let lock = NSLock()
    private var downloaded: Int64 = 0
    private var uploaded: Int64 = 0
    private let total: Int64
    private let progress: FileTransferProgress

    init(fileSize: Int64, progress: @escaping FileTransferProgress) {
        total = fileSize * 2
        self.progress = progress
    }

    func didDownload(_ bytes: Int) {
        lock.lock()
        downloaded += Int64(bytes)
        let completed = downloaded + uploaded
        lock.unlock()
        progress(completed, total)
    }

    func didUpload(_ bytes: Int) {
        lock.lock()
        uploaded += Int64(bytes)
        let completed = downloaded + uploaded
        lock.unlock()
        progress(completed, total)
    }
}

import Foundation
import XCTest
@testable import DsmNetwork

final class BoundedMemoryPipeTests: XCTestCase {
    func test有界内存管道按顺序传输且只统计文件内容() async throws {
        let counter = LockedByteCounter()
        let pipe = BoundedMemoryPipe(capacity: 8) { bytes in
            counter.add(bytes)
        }
        let stream = pipe.makeInputStream()
        let writer = Task.detached {
            try pipe.write(Data("H".utf8), countsAsFileData: false)
            try pipe.write(Data("hello".utf8), countsAsFileData: true)
            try pipe.write(Data("T".utf8), countsAsFileData: false)
            pipe.finish()
        }

        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 2)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            XCTAssertGreaterThanOrEqual(count, 0)
            if count == 0 { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        try await writer.value

        XCTAssertEqual(result, Data("HhelloT".utf8))
        XCTAssertEqual(counter.value, 5)
    }

    func test取消管道会拒绝继续写入() {
        let pipe = BoundedMemoryPipe(capacity: 8) { _ in }
        pipe.cancel()

        XCTAssertThrowsError(try pipe.write(Data("x".utf8), countsAsFileData: true))
    }

    func test系统输入流支持CFNetwork需要的事件调度() {
        let pipe = BoundedMemoryPipe(capacity: 8) { _ in }
        let stream = pipe.makeInputStream()
        let delegate = StreamDelegateProbe()

        stream.delegate = delegate
        stream.schedule(in: .current, forMode: .default)
        stream.remove(from: .current, forMode: .default)
        pipe.cancel()

        XCTAssertTrue(stream.delegate === delegate)
    }

    func test目标端失败会解除等待缓冲区的写入() async throws {
        let pipe = BoundedMemoryPipe(capacity: 4) { _ in }
        let writer = Task.detached {
            try pipe.write(Data(repeating: 1, count: 32), countsAsFileData: true)
        }
        try await Task.sleep(for: .milliseconds(20))

        pipe.cancel()

        do {
            try await writer.value
            XCTFail("取消后写入不应继续成功")
        } catch {
            XCTAssertTrue(error is MemoryPipeError || error is CancellationError)
        }
    }
}

private final class LockedByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = 0

    func add(_ count: Int) {
        lock.lock()
        bytes += count
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return bytes
    }
}

private final class StreamDelegateProbe: NSObject, StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {}
}

import XCTest
@testable import DsmCore

final class FileStationTests: XCTestCase {
    func test回收站路径映射到同一共享的原位置() throws {
        let location = try XCTUnwrap(
            RecycleLocation(recyclePath: "/projects/#recycle/设计/方案.pdf")
        )

        XCTAssertEqual(location.recycleRoot, "/projects/#recycle")
        XCTAssertEqual(location.relativePath, "/设计/方案.pdf")
        XCTAssertEqual(location.originalPath, "/projects/设计/方案.pdf")
        XCTAssertEqual(location.originalParentPath, "/projects/设计")
    }

    func test拒绝非共享根下的伪回收站路径() {
        XCTAssertNil(RecycleLocation(recyclePath: "/projects/archive/#recycle/file.txt"))
    }

    func test预览类型按扩展名分类() throws {
        let profileID = UUID()
        XCTAssertEqual(
            PreviewKind.classify(
                FileItem(profileID: profileID, name: "photo.HEIC", path: "/photo/photo.HEIC", kind: .file)
            ),
            .image
        )
        XCTAssertEqual(
            PreviewKind.classify(
                FileItem(profileID: profileID, name: "README.md", path: "/home/README.md", kind: .file)
            ),
            .text
        )
        XCTAssertEqual(
            PreviewKind.classify(
                FileItem(profileID: profileID, name: "manual.pdf", path: "/home/manual.pdf", kind: .file)
            ),
            .pdf
        )
        XCTAssertEqual(
            PreviewKind.classify(
                FileItem(profileID: profileID, name: "movie.mp4", path: "/home/movie.mp4", kind: .file)
            ),
            .video
        )
        XCTAssertEqual(
            PreviewKind.classify(
                FileItem(profileID: profileID, name: "song.mp3", path: "/home/song.mp3", kind: .file)
            ),
            .audio
        )
        XCTAssertEqual(
            PreviewKind.classify(
                FileItem(
                    profileID: profileID,
                    name: "episode.TS",
                    path: "/video/episode.TS",
                    kind: .file,
                    sizeBytes: 300 * 1_024 * 1_024,
                    mimeType: "video/mp2t"
                )
            ),
            .video
        )
        XCTAssertEqual(
            PreviewKind.classify(
                FileItem(
                    profileID: profileID,
                    name: "large.ts",
                    path: "/code/large.ts",
                    kind: .file,
                    sizeBytes: 300 * 1_024 * 1_024
                )
            ),
            .text
        )
    }

    func testTS文件根据内容而不是大小区分视频和代码() {
        var transportStream = Data(repeating: 0, count: 188 * 4)
        for packetIndex in 0..<4 {
            transportStream[packetIndex * 188] = 0x47
        }

        XCTAssertEqual(
            FileContentSniffer.classifyTypeScriptOrTransportStream(transportStream),
            .video
        )
        XCTAssertEqual(
            FileContentSniffer.classifyTypeScriptOrTransportStream(
                Data("export const greeting = 'hello';".utf8)
            ),
            .text
        )
    }
}

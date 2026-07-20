import Foundation
import XCTest
@testable import DsmCore

final class PhotoLibraryTests: XCTestCase {
    func test照片项目只接受文件夹图片和视频() throws {
        let profileID = UUID()
        let folder = FileItem(
            profileID: profileID,
            name: "旅行",
            path: "/photo/旅行",
            kind: .directory
        )
        let image = FileItem(
            profileID: profileID,
            name: "海边.HEIC",
            path: "/photo/海边.HEIC",
            kind: .file
        )
        let video = FileItem(
            profileID: profileID,
            name: "日落.mov",
            path: "/photo/日落.mov",
            kind: .file
        )
        let document = FileItem(
            profileID: profileID,
            name: "说明.txt",
            path: "/photo/说明.txt",
            kind: .file
        )

        XCTAssertEqual(try XCTUnwrap(PhotoLibraryItem(folder)).kind, .folder)
        XCTAssertEqual(try XCTUnwrap(PhotoLibraryItem(image)).kind, .image)
        XCTAssertEqual(try XCTUnwrap(PhotoLibraryItem(video)).kind, .video)
        XCTAssertNil(PhotoLibraryItem(document))
    }

    func test照片空间使用固定公开目录() {
        XCTAssertEqual(PhotoSpace.personal.rootPath, "/home/Photos")
        XCTAssertEqual(PhotoSpace.shared.rootPath, "/photo")
        XCTAssertEqual(PhotoSpace.shared.title, "共享空间")
    }

    func testLivePhotoAutoPairing() throws {
        let profileID = UUID()
        let image = try XCTUnwrap(PhotoLibraryItem(FileItem(
            profileID: profileID,
            name: "IMG_2026.HEIC",
            path: "/photo/2026/IMG_2026.HEIC",
            kind: .file
        )))
        let video = try XCTUnwrap(PhotoLibraryItem(FileItem(
            profileID: profileID,
            name: "IMG_2026.MOV",
            path: "/photo/2026/IMG_2026.MOV",
            kind: .file
        )))
        let standaloneVideo = try XCTUnwrap(PhotoLibraryItem(FileItem(
            profileID: profileID,
            name: "OTHER.MOV",
            path: "/photo/2026/OTHER.MOV",
            kind: .file
        )))

        let paired = PhotoLibraryItem.pairLivePhotos([image, video, standaloneVideo])
        XCTAssertEqual(paired.count, 2)
        XCTAssertTrue(paired[0].isLivePhoto)
        XCTAssertEqual(paired[0].livePhotoVideoPath, "/photo/2026/IMG_2026.MOV")
        XCTAssertEqual(paired[1].name, "OTHER.MOV")
    }
}

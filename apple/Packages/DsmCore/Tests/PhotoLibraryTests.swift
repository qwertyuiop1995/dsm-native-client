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
        XCTAssertEqual(PhotoSpace.personal.title, "个人空间")
        XCTAssertEqual(PhotoSpace.shared.title, "共享空间")
    }
}

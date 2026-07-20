import DsmCore
import Foundation
import XCTest

final class PhotoLibraryCacheStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoLibraryCacheStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        try super.tearDownWithError()
    }

    func testSaveAndLoadCache() throws {
        let store = PhotoLibraryCacheStore(baseURL: temporaryDirectory)
        let profileID = UUID()

        let item = try XCTUnwrap(
            PhotoLibraryItem(
                FileItem(
                    profileID: profileID,
                    name: "test.jpg",
                    path: "/home/Photos/test.jpg",
                    kind: .file,
                    sizeBytes: 1024,
                    fileExtension: "jpg",
                    times: FileTimes(modifiedAt: Date(), createdAt: Date(), accessedAt: nil),
                    thumbnailAvailable: true
                )
            )
        )

        let cache = PhotoSpaceCache(
            items: [item],
            folderItemPaths: ["/home/Photos": ["/home/Photos/test.jpg"]],
            lastScannedAt: Date()
        )

        store.save(cache, profileID: profileID, spaceKind: .personal)

        let loaded = store.load(profileID: profileID, spaceKind: .personal)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.items.count, 1)
        XCTAssertEqual(loaded?.items.first?.path, "/home/Photos/test.jpg")
        XCTAssertEqual(loaded?.folderItemPaths["/home/Photos"], ["/home/Photos/test.jpg"])
    }

    func testRemoveCache() throws {
        let store = PhotoLibraryCacheStore(baseURL: temporaryDirectory)
        let profileID = UUID()

        let cache = PhotoSpaceCache(items: [], folderItemPaths: [:], lastScannedAt: Date())
        store.save(cache, profileID: profileID, spaceKind: .personal)

        store.remove(profileID: profileID, spaceKind: .personal)
        let loaded = store.load(profileID: profileID, spaceKind: .personal)
        XCTAssertNil(loaded)
    }
}

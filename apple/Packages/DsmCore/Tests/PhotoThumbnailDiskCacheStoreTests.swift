import Foundation
import XCTest
@testable import DsmCore

final class PhotoThumbnailDiskCacheStoreTests: XCTestCase {
    func testThumbnailSaveAndLoad() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoThumbnailDiskCacheStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = PhotoThumbnailDiskCacheStore(baseURL: tempDir)
        let profileID = UUID()
        let itemID = "photo_test_123"
        let mockData = Data("FakeImageDataBuffer".utf8)

        XCTAssertNil(store.load(profileID: profileID, itemID: itemID))

        store.save(mockData, profileID: profileID, itemID: itemID)

        let loaded = store.load(profileID: profileID, itemID: itemID)
        XCTAssertEqual(loaded, mockData)
        XCTAssertGreaterThan(store.diskUsageBytes, 0)

        store.remove(profileID: profileID, itemID: itemID)
        XCTAssertNil(store.load(profileID: profileID, itemID: itemID))
    }
}

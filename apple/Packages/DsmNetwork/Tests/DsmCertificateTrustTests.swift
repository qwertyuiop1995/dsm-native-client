import XCTest
@testable import DsmNetwork

final class DsmCertificateTrustTests: XCTestCase {
    func test格式化安全指纹() {
        let review = DsmCertificateReview(
            host: "nas.local",
            subjectSummary: "NAS",
            sha256Fingerprint: "001122AABBCC",
            canBePinned: true
        )

        XCTAssertEqual(review.formattedFingerprint, "00:11:22:AA:BB:CC")
    }

    func test系统无法验证时允许用户核对后信任() {
        XCTAssertEqual(
            DsmCertificateTrustPolicy.decide(
                systemTrusted: false,
                pinnedFingerprint: nil,
                presentedFingerprint: "AABB",
                canBePinned: true
            ),
            .reviewUntrustedCertificate
        )
    }

    func test已核对的同一证书可以继续连接() {
        XCTAssertEqual(
            DsmCertificateTrustPolicy.decide(
                systemTrusted: false,
                pinnedFingerprint: "AABB",
                presentedFingerprint: "AABB",
                canBePinned: true
            ),
            .usePinnedCertificate
        )
    }

    func test证书变化时即使系统信任也必须再次确认() {
        XCTAssertEqual(
            DsmCertificateTrustPolicy.decide(
                systemTrusted: true,
                pinnedFingerprint: "AABB",
                presentedFingerprint: "CCDD",
                canBePinned: true
            ),
            .reviewChangedCertificate
        )
    }

    func test过期或无效证书不能被用户放行() {
        XCTAssertEqual(
            DsmCertificateTrustPolicy.decide(
                systemTrusted: false,
                pinnedFingerprint: nil,
                presentedFingerprint: "AABB",
                canBePinned: false
            ),
            .rejectInvalidCertificate
        )
    }
}

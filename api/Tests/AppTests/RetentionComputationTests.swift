import XCTest
@testable import App

final class RetentionComputationTests: XCTestCase {
    func testNormalizeDaysUsesDefault() {
        XCTAssertEqual(RetentionComputation.normalizeDays(nil), 365)
    }

    func testNormalizeDaysClampsRange() {
        XCTAssertEqual(RetentionComputation.normalizeDays(0), 1)
        XCTAssertEqual(RetentionComputation.normalizeDays(999999), 36500)
    }

    func testCutoffStringMatchesEpoch() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let cutoff = RetentionComputation.cutoff(now: now, olderThanDays: 10)
        XCTAssertEqual(
            RetentionComputation.cutoffString(cutoff),
            String(Int64(cutoff.timeIntervalSince1970))
        )
    }

    func testCutoffSubtractsWholeDays() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let cutoff = RetentionComputation.cutoff(now: now, olderThanDays: 2)
        XCTAssertEqual(Int(cutoff.timeIntervalSince1970), 1_999_827_200)
    }

    func testCutoffClampsOutOfRangeDays() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let minCutoff = RetentionComputation.cutoff(now: now, olderThanDays: 0)
        let maxCutoff = RetentionComputation.cutoff(now: now, olderThanDays: 999_999)
        XCTAssertEqual(Int(minCutoff.timeIntervalSince1970), 1_999_913_600)
        XCTAssertEqual(Int(maxCutoff.timeIntervalSince1970), -1_153_600_000)
    }
}

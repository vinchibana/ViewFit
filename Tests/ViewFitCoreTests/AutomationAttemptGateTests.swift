import XCTest
@testable import ViewFitCore

final class AutomationAttemptGateTests: XCTestCase {
    private let request = "wechat:42:internal-generation-2:100"
    private let start = Date(timeIntervalSince1970: 10_000)

    func testFailedWeChatTransitionDoesNotRepeatedlyOpenMenuOnForegroundPolling() {
        var gate = AutomationAttemptGate()
        var resetAttempts = 0
        // The production foreground poll occurs every three seconds. Repeated
        // stale AX "Zoom Out enabled" responses make each reset attempt fail.
        for elapsed in stride(from: 0, through: 60, by: 3) {
            let now = start.addingTimeInterval(Double(elapsed))
            if gate.begin(key: request, now: now) {
                resetAttempts += 1
                gate.finish(key: request, succeeded: false, now: now)
            }
        }
        XCTAssertEqual(resetAttempts, 1, "A failed display transition must not reopen the app menu every retry interval")
        XCTAssertEqual(gate.outcome(for: request), .failed)
    }

    func testDuplicateForegroundNotificationsCannotStartConcurrentAttempt() {
        var gate = AutomationAttemptGate()
        XCTAssertTrue(gate.begin(key: request, now: start))
        XCTAssertFalse(gate.begin(key: request, now: start))
        XCTAssertTrue(gate.hasAttempted(key: request))
        XCTAssertEqual(gate.outcome(for: request), .inProgress)
    }

    func testInterruptedAttemptRemainsLatchedWithoutFinish() {
        var gate = AutomationAttemptGate()
        XCTAssertTrue(gate.begin(key: request, now: start))
        XCTAssertFalse(gate.begin(key: request, now: start.addingTimeInterval(3600)))
    }

    func testExplicitApplyClearsFailureAndAllowsExactlyOneNewAttempt() {
        var gate = AutomationAttemptGate()
        XCTAssertTrue(gate.begin(key: request, now: start))
        gate.finish(key: request, succeeded: false, now: start)
        gate.reset()
        XCTAssertFalse(gate.hasAttempted(key: request))
        XCTAssertTrue(gate.begin(key: request, now: start))
        XCTAssertFalse(gate.begin(key: request, now: start))
    }

    func testNewProfileAndOtherAppsAreNotBlockedByWeChatFailure() {
        var gate = AutomationAttemptGate()
        XCTAssertTrue(gate.begin(key: request, now: start))
        gate.finish(key: request, succeeded: false, now: start)
        XCTAssertTrue(gate.begin(key: "wechat:42:external-generation-3:120", now: start))
        XCTAssertTrue(gate.begin(key: "codex:99:internal-generation-2:100", now: start))
    }

    func testCompletedRequestIsNotAppliedAgainOnRepeatedPolls() {
        var gate = AutomationAttemptGate()
        XCTAssertTrue(gate.begin(key: request, now: start))
        gate.finish(key: request, succeeded: true, now: start)
        XCTAssertFalse(gate.begin(key: request, now: start.addingTimeInterval(3600)))
        XCTAssertEqual(gate.outcome(for: request), .succeeded)
    }
}

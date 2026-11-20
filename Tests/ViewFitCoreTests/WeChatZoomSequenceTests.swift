import XCTest
@testable import ViewFitCore

final class WeChatZoomSequenceTests: XCTestCase {
    @MainActor
    func testForegroundPollingWithStaleWeChatStateMakesOneBoundedAttempt() async {
        var gate = AutomationAttemptGate()
        let request = "wechat:42:internal-generation-2:100"
        let start = Date(timeIntervalSince1970: 10_000)
        var attempts = 0
        var downs = 0
        var ups = 0
        // Exercise the production composition: the foreground heartbeat checks
        // the gate, then runs the same native adjustment sequence, then latches
        // its failure. Qt's Zoom Out flag stays enabled throughout the minute.
        for elapsed in stride(from: 0, through: 60, by: 3) {
            let now = start.addingTimeInterval(Double(elapsed))
            guard gate.begin(key: request, now: now) else { continue }
            attempts += 1
            do {
                try await WeChatZoomSequence.apply(
                    steps: 0,
                    readState: { .init(canEnlarge: true, canShrink: true) },
                    shrink: { downs += 1 },
                    enlarge: { ups += 1 }
                )
                gate.finish(key: request, succeeded: true, now: now)
            } catch {
                gate.finish(key: request, succeeded: false, now: now)
            }
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(downs, 2)
        XCTAssertEqual(ups, 0)
        XCTAssertEqual(gate.outcome(for: request), .failed)
    }

    @MainActor
    func testStaleEnabledFlagStopsAfterManagedRangeInsteadOfRepeatedShrink() async {
        var downs = 0
        var ups = 0
        do {
            try await WeChatZoomSequence.apply(
                steps: 0,
                readState: { .init(canEnlarge: true, canShrink: true) },
                shrink: { downs += 1 },
                enlarge: { ups += 1 }
            )
            XCTFail("Unverified baseline must not report success")
        } catch {}
        XCTAssertEqual(downs, 2, "Stale Qt enabled state must never cause repeated shrink attempts")
        XCTAssertEqual(ups, 0)
    }

    @MainActor
    func testManagedTwoStepUnplugRestoresBaselineExactlyOnce() async throws {
        var level = 2
        var downs = 0
        try await WeChatZoomSequence.apply(
            steps: 0,
            readState: { .init(canEnlarge: true, canShrink: level > 0) },
            shrink: { level -= 1; downs += 1 },
            enlarge: { level += 1 }
        )
        XCTAssertEqual(level, 0)
        XCTAssertEqual(downs, 2)
    }

    @MainActor
    func testAlreadyAtBaselineSendsNoShrink() async throws {
        var downs = 0
        try await WeChatZoomSequence.apply(
            steps: 0,
            readState: { .init(canEnlarge: true, canShrink: false) },
            shrink: { downs += 1 },
            enlarge: { XCTFail("Unexpected enlargement") }
        )
        XCTAssertEqual(downs, 0)
    }

    @MainActor
    func testExternalTwoStepPresetStillWorksAfterReset() async throws {
        var level = 1
        var downs = 0
        var ups = 0
        try await WeChatZoomSequence.apply(
            steps: 2,
            readState: { .init(canEnlarge: level < 2, canShrink: level > 0) },
            shrink: { level -= 1; downs += 1 },
            enlarge: { level += 1; ups += 1 }
        )
        XCTAssertEqual(level, 2)
        XCTAssertEqual(downs, 1)
        XCTAssertEqual(ups, 2)
    }

    @MainActor
    func testUnavailableWindowIsNotMistakenForBaseline() async {
        var downs = 0
        var failed = false
        do {
            try await WeChatZoomSequence.apply(
                steps: 0,
                readState: { .init(canEnlarge: false, canShrink: false) },
                shrink: { downs += 1 },
                enlarge: { XCTFail("Unexpected enlargement") }
            )
        } catch { failed = true }
        XCTAssertTrue(failed)
        XCTAssertEqual(downs, 0)
    }

    @MainActor
    func testCancellationAfterFirstDecrementStopsFurtherInput() async {
        var downs = 0
        let task = Task { @MainActor in
            try await WeChatZoomSequence.apply(
                steps: 2,
                readState: { .init(canEnlarge: true, canShrink: true) },
                shrink: { downs += 1; withUnsafeCurrentTask { $0?.cancel() } },
                enlarge: { XCTFail("Cancelled sequence must not enlarge") }
            )
        }
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(downs, 1)
    }
}

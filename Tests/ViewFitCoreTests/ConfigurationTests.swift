import XCTest
@testable import ViewFitCore

final class ConfigurationTests: XCTestCase {
    func testInternalAlwaysRestores100() {
        var config = AppConfiguration()
        config.rules[0].externalPercent = 175
        XCTAssertEqual(config.target(for: "chrome", external: false), 100)
        XCTAssertEqual(config.target(for: "chrome", external: true), 175)
    }
    func testPauseDoesNotRequestZoom() {
        var config = AppConfiguration(); config.enabled = false
        XCTAssertNil(config.target(for: "codex", external: true))
        config.enabled = true; config.rules[1].enabled = false
        XCTAssertNil(config.target(for: "codex", external: false))
    }
    func testSavedConfigurationRecoversMissingRulesAndBounds() {
        var config = AppConfiguration()
        config.rules = [.init(id: "chrome", name: "old", externalPercent: 900)]
        config.normalize()
        XCTAssertEqual(config.rules.count, 3)
        XCTAssertEqual(config.rules[0].externalPercent, 200)
        XCTAssertEqual(config.rules[0].name, "Chrome")
        XCTAssertEqual(config.rules[1].externalPercent, 120)
    }
    func testBridgeExpiresAfterAppStops() {
        let now = Date()
        var state = ChromeState(configuration: AppConfiguration(), external: true, generation: 7, now: now)
        XCTAssertEqual(state.chromeZoom, 1.25)
        state.disableIfStale(now: now.addingTimeInterval(21))
        XCTAssertFalse(state.enabled)
    }
    func testBridgeUnplugIsExact100() {
        let state = ChromeState(configuration: AppConfiguration(), external: false, generation: 8)
        XCTAssertEqual(state.chromeZoom, 1)
        XCTAssertFalse(state.externalConnected)
    }
}

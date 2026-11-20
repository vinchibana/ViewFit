import Foundation

/// Request keys identify an app process/window, profile generation and target.
/// Each request may touch another app's UI at most once. A failure or interrupted
/// attempt stays latched until an explicit reset or a genuinely new request key;
/// foreground notifications and elapsed time must never reopen the app's menus.
public struct AutomationAttemptGate {
    public enum Outcome: Equatable {
        case inProgress
        case succeeded
        case failed
    }

    private var outcomes: [String: Outcome] = [:]

    public init() {}

    public mutating func begin(key: String, now: Date = Date()) -> Bool {
        guard outcomes[key] == nil else { return false }
        outcomes[key] = .inProgress
        return true
    }

    public mutating func finish(key: String, succeeded: Bool, now: Date = Date()) {
        guard outcomes[key] == .inProgress else { return }
        outcomes[key] = succeeded ? .succeeded : .failed
    }

    public func hasAttempted(key: String) -> Bool { outcomes[key] != nil }
    public func outcome(for key: String) -> Outcome? { outcomes[key] }

    public mutating func reset() {
        outcomes.removeAll()
    }
}

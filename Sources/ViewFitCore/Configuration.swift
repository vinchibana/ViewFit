import Foundation

public struct AppRule: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var externalPercent: Int
    public init(id: String, name: String, enabled: Bool = true, externalPercent: Int = 125) {
        self.id = id; self.name = name; self.enabled = enabled; self.externalPercent = externalPercent
    }
}

public struct AppConfiguration: Codable, Equatable {
    public var enabled = true
    public var rules: [AppRule] = [
        .init(id: "chrome", name: "Chrome", externalPercent: 125),
        .init(id: "codex", name: "Codex", externalPercent: 120),
        .init(id: "wechat", name: "微信", externalPercent: 120)
    ]
    public init() {}
    public func target(for id: String, external: Bool) -> Int? {
        guard enabled, let rule = rules.first(where: { $0.id == id }), rule.enabled else { return nil }
        return external ? rule.externalPercent : 100
    }
    public mutating func normalize() {
        let defaults = AppConfiguration()
        rules = defaults.rules.map { fallback in
            guard var found = rules.first(where: { $0.id == fallback.id }) else { return fallback }
            found.name = fallback.name
            found.externalPercent = min(200, max(100, found.externalPercent))
            if found.id == "codex" { found.externalPercent = ((found.externalPercent + 5) / 10) * 10 }
            if found.id == "wechat" { found.externalPercent = [100, 110, 120].min(by: { abs($0 - found.externalPercent) < abs($1 - found.externalPercent) })! }
            return found
        }
    }
}

public struct ChromeState: Codable, Equatable {
    public var enabled: Bool
    public var externalConnected: Bool
    public var chromeEnabled: Bool
    public var chromeZoom: Double
    public var generation: Int
    public var updatedAt: Double
    public init(configuration: AppConfiguration, external: Bool, generation: Int, now: Date = Date()) {
        enabled = configuration.enabled
        externalConnected = external
        chromeEnabled = configuration.rules.first(where: { $0.id == "chrome" })?.enabled ?? false
        chromeZoom = Double(configuration.target(for: "chrome", external: external) ?? 100) / 100
        self.generation = generation
        updatedAt = now.timeIntervalSince1970
    }
    public mutating func disableIfStale(now: Date = Date()) {
        if now.timeIntervalSince1970 - updatedAt > 20 { enabled = false }
    }
}

public enum Storage {
    public static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["SCREEN_SCALE_SUPPORT_DIRECTORY"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        // Retain the original storage location so renaming the app preserves user presets.
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenScale", isDirectory: true)
    }
    public static var configurationURL: URL { directory.appendingPathComponent("configuration.json") }
    public static var chromeStateURL: URL { directory.appendingPathComponent("chrome-state.json") }
    public static var heartbeatURL: URL { directory.appendingPathComponent("chrome-heartbeat") }
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

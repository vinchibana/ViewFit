import Foundation
import ViewFitCore
import Darwin

// Chrome owns this process and speaks length-prefixed JSON over stdio.
// No logs are written to stdout, and the host never accepts paths or shell commands.
final class Bridge {
    private let outputLock = NSLock()
    private var lastSignature = ""
    private var timer: DispatchSourceTimer?
    private var lastHeartbeat = Date.distantPast

    func run() {
        DispatchQueue.global(qos: .utility).async { [self] in
            while let header = readExactly(4) {
                let count = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
                guard count > 0, count <= 64 * 1024,
                      let body = readExactly(Int(count)),
                      let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                      message["type"] as? String == "getState" else { exit(0) }
                DispatchQueue.main.async { self.publish(force: true) }
            }
            exit(0)
        }
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: 1)
        source.setEventHandler { [self] in publish() }
        timer = source; source.resume()
        dispatchMain()
    }

    private func readExactly(_ count: Int) -> Data? {
        var result = Data()
        while result.count < count {
            guard let chunk = try? FileHandle.standardInput.read(upToCount: count - result.count), !chunk.isEmpty else { return nil }
            result.append(chunk)
        }
        return result
    }

    private func publish(force: Bool = false) {
        var state = (try? Data(contentsOf: Storage.chromeStateURL)).flatMap { try? JSONDecoder().decode(ChromeState.self, from: $0) }
            ?? ChromeState(configuration: AppConfiguration(), external: false, generation: 0, now: .distantPast)
        state.disableIfStale()
        let signature = "\(state.enabled)-\(state.chromeEnabled)-\(state.chromeZoom)-\(state.externalConnected)-\(state.generation)"
        if force || signature != lastSignature, let data = try? JSONEncoder().encode(state) {
            var size = UInt32(data.count).littleEndian
            outputLock.lock()
            do {
                try FileHandle.standardOutput.write(contentsOf: withUnsafeBytes(of: &size) { Data($0) })
                try FileHandle.standardOutput.write(contentsOf: data)
            } catch { exit(0) }
            outputLock.unlock()
            lastSignature = signature
        }
        if Date().timeIntervalSince(lastHeartbeat) > 3 {
            try? FileManager.default.createDirectory(at: Storage.directory, withIntermediateDirectories: true)
            try? Data(String(Date().timeIntervalSince1970).utf8).write(to: Storage.heartbeatURL, options: .atomic)
            lastHeartbeat = Date()
        }
    }
}

// Only Chrome's allowlisted extension is expected to start this helper.
guard CommandLine.arguments.contains("chrome-extension://fgmjjmcpabiopnbpgcjdbgfbcpiajmhl/") else { exit(1) }
Bridge().run()

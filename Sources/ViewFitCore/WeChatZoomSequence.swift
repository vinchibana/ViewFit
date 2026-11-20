import Foundation

/// A single WeChat adjustment, independent of native event transport.
@MainActor
public enum WeChatZoomSequence {
    public struct State {
        public var canEnlarge: Bool
        public var canShrink: Bool
        public init(canEnlarge: Bool, canShrink: Bool) {
            self.canEnlarge = canEnlarge; self.canShrink = canShrink
        }
    }
    public struct Failure: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }
    public static func apply(
        steps: Int,
        readState: () throws -> State,
        shrink: () async throws -> Void,
        enlarge: () async throws -> Void
    ) async throws {
        guard (0...2).contains(steps) else { throw Failure(message: "微信仅支持基准或放大一至两档") }
        func checkedState() throws -> State {
            try Task.checkCancellation()
            let state = try readState()
            guard state.canEnlarge || state.canShrink else {
                throw Failure(message: "请打开微信聊天主窗口后重试")
            }
            return state
        }
        _ = try checkedState()
        var reachedMinimum = false
        // The supported range is baseline/+1/+2. A stale Qt enabled flag is
        // not evidence that another decrement is useful. Never chase it.
        for _ in 0..<2 {
            if !(try checkedState()).canShrink { reachedMinimum = true; break }
            try await shrink()
        }
        if !reachedMinimum { reachedMinimum = !(try checkedState()).canShrink }
        guard reachedMinimum else {
            throw Failure(message: "无法确认微信基准字号，已停止；请手动恢复基准后点击“应用当前规则”")
        }
        for _ in 0..<steps {
            guard (try checkedState()).canEnlarge else {
                throw Failure(message: "微信不能继续放大，已停止调整")
            }
            try await enlarge()
        }
        if steps > 0, !(try checkedState()).canShrink {
            throw Failure(message: "微信未响应字号调整，请打开聊天主窗口后重试")
        }
    }
}

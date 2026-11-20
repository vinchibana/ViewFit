import SwiftUI
import AppKit

@main
struct ViewFitApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        MenuBarExtra("ViewFit · 随屏", systemImage: "textformat.size") {
            MenuContent(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

import SwiftUI

@main
struct AiQokkaMenubarApp: App {
    var body: some Scene {
        MenuBarExtra("aiquokka", systemImage: "gauge.with.dots.needle.67percent") {
            Text("Loading…")
                .frame(width: 380, height: 520)
        }
        .menuBarExtraStyle(.window)
    }
}

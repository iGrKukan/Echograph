import SwiftUI

@main
struct EchographWatchApp: App {
    @State private var recorder = WatchRecorder()

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(recorder)
        }
    }
}

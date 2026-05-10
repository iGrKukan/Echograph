import AppIntents
import Foundation

/// User-facing intent that flips a flag to auto-start recording when the app opens.
/// Designed to be assigned to the iPhone 15 Pro Action Button or invoked from Siri.
struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording"

    static let description = IntentDescription(
        "Open Echograph and start a new voice recording.",
        categoryName: "Recording"
    )

    /// Bringing the app to the foreground means the recording begins under user-visible
    /// context, satisfying iOS background-recording rules.
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingIntent.shared.shouldStartRecordingOnLaunch = true
        return .result()
    }
}

struct EchographShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording in \(.applicationName)",
                "Record with \(.applicationName)",
                "Capture a voice note in \(.applicationName)"
            ],
            shortTitle: "Record",
            systemImageName: "mic.circle.fill"
        )
    }
}

/// Tiny coordination shim between AppIntents and SwiftUI scenes.
/// The intent runs out-of-process; we set this flag, the app launches, the home
/// view consumes it on appear and triggers `recorder.start()`.
@MainActor
final class PendingIntent {
    static let shared = PendingIntent()
    private init() {}

    var shouldStartRecordingOnLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: Self.key) }
        set { UserDefaults.standard.set(newValue, forKey: Self.key) }
    }

    private static let key = "Echograph.PendingIntent.shouldStartRecording"
}

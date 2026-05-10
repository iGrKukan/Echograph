@preconcurrency import ActivityKit
import Foundation

actor LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private var currentActivity: Activity<RecordingActivityAttributes>?

    nonisolated var isAuthorized: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(title: String) {
        // Simulator can't reliably register Live Activity widgets with SpringBoard
        // ("Failed to get descriptors for extensionBundleID"), so skip on simulator.
        #if targetEnvironment(simulator)
        return
        #else
        guard isAuthorized else { return }
        guard currentActivity == nil else { return }

        let attributes = RecordingActivityAttributes(title: title)
        let initialState = RecordingActivityAttributes.ContentState(
            startedAt: .now,
            elapsed: 0
        )

        do {
            let content = ActivityContent(state: initialState, staleDate: nil)
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            currentActivity = nil
        }
        #endif
    }

    func update(elapsed: TimeInterval, startedAt: Date) async {
        guard let activity = currentActivity else { return }
        let state = RecordingActivityAttributes.ContentState(
            startedAt: startedAt,
            elapsed: elapsed
        )
        let content = ActivityContent(state: state, staleDate: nil)
        await activity.update(content)
    }

    func end() async {
        guard let activity = currentActivity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        currentActivity = nil
    }
}

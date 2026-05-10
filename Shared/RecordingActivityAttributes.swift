import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    public struct State: Codable, Hashable {
        var startedAt: Date
        var elapsed: TimeInterval
    }

    var title: String
}

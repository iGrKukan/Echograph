import AVFoundation
import Foundation

enum MicrophonePermissionStatus {
    case undetermined
    case granted
    case denied

    init(_ status: AVAudioApplication.recordPermission) {
        switch status {
        case .undetermined: self = .undetermined
        case .granted: self = .granted
        case .denied: self = .denied
        @unknown default: self = .denied
        }
    }
}

enum MicrophonePermission {
    static var current: MicrophonePermissionStatus {
        MicrophonePermissionStatus(AVAudioApplication.shared.recordPermission)
    }

    static func request() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

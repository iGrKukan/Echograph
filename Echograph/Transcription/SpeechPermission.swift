import Foundation
import Speech

enum SpeechPermissionStatus {
    case undetermined
    case granted
    case denied
    case restricted

    init(_ status: SFSpeechRecognizerAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .undetermined
        case .authorized: self = .granted
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }
}

enum SpeechPermission {
    static var current: SpeechPermissionStatus {
        SpeechPermissionStatus(SFSpeechRecognizer.authorizationStatus())
    }

    static func request() async -> SpeechPermissionStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: SpeechPermissionStatus(status))
            }
        }
    }
}

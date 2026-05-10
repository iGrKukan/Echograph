import Foundation
import Observation

/// HTTP client for the Mac-side `cli/server.py` analyzer. URL and bearer
/// token live in UserDefaults under the keys `Voicekeep.analyzerURL` and
/// `Voicekeep.analyzerToken` (configured from `SettingsView`).
@MainActor
@Observable
final class AnalysisService {
    private static let urlKey = "Voicekeep.analyzerURL"
    private static let tokenKey = "Voicekeep.analyzerToken"

    var urlString: String {
        get { UserDefaults.standard.string(forKey: Self.urlKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.urlKey) }
    }

    var token: String {
        get { UserDefaults.standard.string(forKey: Self.tokenKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.tokenKey) }
    }

    var isConfigured: Bool {
        !urlString.trimmingCharacters(in: .whitespaces).isEmpty &&
        !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    enum ServiceError: LocalizedError {
        case notConfigured
        case noTranscript
        case invalidURL(String)
        case http(Int, String)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return String(localized: "Open Settings → AI Analyzer and set the server URL and token first.")
            case .noTranscript:
                return String(localized: "Recording has no transcript yet. Transcribe it first.")
            case .invalidURL(let s):
                return String(localized: "Server URL is invalid: \(s)")
            case .http(let code, let detail):
                return String(localized: "Server replied \(code): \(detail)")
            case .network(let detail):
                return String(localized: "Network error: \(detail)")
            }
        }
    }

    /// Send the recording to the Mac analyzer and return the markdown body.
    func analyze(_ recording: Recording) async throws -> String {
        guard isConfigured else { throw ServiceError.notConfigured }
        guard recording.transcript != nil else { throw ServiceError.noTranscript }
        let url = try analyzeURL()
        let body = try AnalysisExport.makeJSON(recording)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        req.timeoutInterval = 180

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw ServiceError.network(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw ServiceError.network("unexpected response type")
        }
        if http.statusCode != 200 {
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            throw ServiceError.http(http.statusCode, detail)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// `GET /health` — true if the server replies 200 within ~5 s.
    func healthCheck() async -> Bool {
        guard let base = try? baseURL() else { return false }
        var req = URLRequest(url: base.appendingPathComponent("health"))
        req.timeoutInterval = 5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func baseURL() throws -> URL {
        let trimmed = urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed),
              url.scheme != nil,
              url.host != nil else {
            throw ServiceError.invalidURL(urlString)
        }
        return url
    }

    private func analyzeURL() throws -> URL {
        try baseURL().appendingPathComponent("analyze")
    }
}

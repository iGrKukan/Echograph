import Foundation
import Observation

#if !targetEnvironment(simulator)
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers
#endif

/// On-device fallback for the AI features (summary, tags, Q&A) on iPhones
/// without Apple Intelligence — a small Qwen3 model running locally via
/// MLX Swift. See `SummaryService` for the two-backend selection logic.
///
/// MLX needs a real Metal GPU, which iOS Simulator does not provide. Every
/// entry point below checks `isSupported` first and fails gracefully
/// (`LocalLLMError.unsupportedEnvironment`) instead of touching any MLX API
/// when running in the simulator, so Debug builds still compile and launch
/// there — only on-device model inference is unavailable.
@MainActor
@Observable
final class LocalLLMService {
    enum ModelChoice {
        case qwen17B
        case qwen08B

        /// Hugging Face repo id (also the MLX model registry id for qwen17B).
        var repoID: String {
            switch self {
            case .qwen17B: "mlx-community/Qwen3-1.7B-4bit"
            case .qwen08B: "mlx-community/Qwen3.5-0.8B-MLX-4bit"
            }
        }

        /// Approximate download size, for the "Download AI model (938 MB)" label.
        var approximateDownloadMB: Int {
            switch self {
            case .qwen17B: 938
            case .qwen08B: 627
            }
        }
    }

    /// Devices at or above this much RAM get the larger, better-quality 1.7B
    /// model; below it they get the 0.8B model to leave headroom for iOS
    /// itself and the rest of the app.
    private static let recommendedModelMemoryThreshold: UInt64 = 6 * 1_024 * 1_024 * 1_024

    /// Low sampling temperature — these are extraction/summary tasks, not
    /// creative writing, so we want consistent, literal output.
    private static let temperature: Float = 0.3

    /// Without this, the smaller 0.8B model reliably degenerates into
    /// repeating one line dozens of times on longer generations (observed
    /// live on the "Deep Analysis" prompt's "Open questions" section, which
    /// has the least structural guardrails). 1.15 clears it up completely
    /// in testing without hurting the 1.7B model's output quality.
    private static let repetitionPenalty: Float = 1.15

    static var recommendedModel: ModelChoice {
        ProcessInfo.processInfo.physicalMemory >= recommendedModelMemoryThreshold ? .qwen17B : .qwen08B
    }

    let modelChoice: ModelChoice

    /// `false` in the iOS Simulator (no Metal GPU) — every other member
    /// checks this and fails gracefully rather than touching MLX.
    var isSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    /// Whether the model weights are already on disk (downloaded, possibly
    /// in an earlier app run) and ready to be loaded into memory. Checked
    /// against the on-disk Hugging Face cache at init so the "Download AI
    /// model" prompt doesn't reappear after every cold launch.
    private(set) var isModelReady: Bool

    /// 0...1 while a download is in flight; unused once `isModelReady` is true.
    private(set) var downloadProgress: Double = 0

    init(modelChoice: ModelChoice = LocalLLMService.recommendedModel) {
        self.modelChoice = modelChoice
        #if !targetEnvironment(simulator)
        self.isModelReady = Self.isCachedOnDisk(modelChoice)
        #else
        self.isModelReady = false
        #endif
    }

    #if !targetEnvironment(simulator)
    private enum LoadState {
        case idle
        case loading
        case loaded(ModelContainer)
    }

    private var loadState: LoadState = .idle
    #endif

    /// Downloads (if needed) and loads the model into memory. Safe to call
    /// repeatedly — a already-loaded model returns immediately, and
    /// concurrent callers share the same in-flight download/load.
    func prepare() async throws {
        guard isSupported else { throw LocalLLMError.unsupportedEnvironment }
        #if !targetEnvironment(simulator)
        _ = try await loadedContainer()
        #endif
    }

    /// Runs one prompt through the local model and returns the reply.
    /// - Parameters:
    ///   - system: system/instructions prompt (kept identical to the Apple
    ///     Intelligence prompts in `SummaryService` — this backend adds its
    ///     own "no thinking" directive underneath, it never rewrites the
    ///     caller's prompt).
    ///   - user: the user-turn prompt (e.g. "Transcript:\n\n...").
    ///   - maxTokens: generation length cap.
    func respond(system: String, user: String, maxTokens: Int) async throws -> String {
        guard isSupported else { throw LocalLLMError.unsupportedEnvironment }
        #if !targetEnvironment(simulator)
        let container = try await loadedContainer()
        let session = ChatSession(
            container,
            // Qwen3's chat template inserts a `<think>...</think>` block by
            // default. `enable_thinking: false` (via additionalContext, the
            // template's own kwarg) is the primary switch; the `/no_think`
            // line is a belt-and-suspenders fallback for whichever model
            // variant doesn't honor the kwarg, per Qwen3's own convention.
            instructions: system + "\n\n/no_think",
            generateParameters: GenerateParameters(
                maxTokens: maxTokens,
                temperature: Self.temperature,
                repetitionPenalty: Self.repetitionPenalty
            ),
            additionalContext: ["enable_thinking": false]
        )
        do {
            let raw = try await session.respond(to: user)
            return Self.stripThinkingTags(raw)
        } catch {
            throw LocalLLMError.generationFailed(error.localizedDescription)
        }
        #else
        throw LocalLLMError.unsupportedEnvironment
        #endif
    }

    /// Releases the loaded model and its Metal buffers. Call from
    /// `applicationDidEnterBackground` — a loaded 4-bit model is roughly a
    /// gigabyte resident, and iOS will jetsam the app if it stays there.
    func unload() {
        #if !targetEnvironment(simulator)
        loadState = .idle
        isModelReady = Self.isCachedOnDisk(modelChoice)
        downloadProgress = 0
        Memory.clearCache()
        #endif
    }

    #if !targetEnvironment(simulator)
    private func loadedContainer() async throws -> ModelContainer {
        while true {
            switch loadState {
            case .loaded(let container):
                return container
            case .loading:
                try await Task.sleep(for: .milliseconds(100))
            case .idle:
                loadState = .loading
                do {
                    let container = try await downloadAndLoad()
                    loadState = .loaded(container)
                    isModelReady = true
                    downloadProgress = 1
                    return container
                } catch {
                    loadState = .idle
                    downloadProgress = 0
                    throw LocalLLMError.downloadOrLoadFailed(error.localizedDescription)
                }
            }
        }
    }

    private func downloadAndLoad() async throws -> ModelContainer {
        let configuration = ModelConfiguration(id: modelChoice.repoID)
        downloadProgress = 0
        return try await #huggingFaceLoadModelContainer(configuration: configuration) { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress.fractionCompleted
            }
        }
    }

    /// Read-only, no-network check of the Hugging Face Hub cache for an
    /// already-downloaded snapshot of `choice`, so `isModelReady` reflects
    /// reality across app relaunches instead of always starting at `false`.
    private static func isCachedOnDisk(_ choice: ModelChoice) -> Bool {
        guard let repo = HuggingFace.Repo.ID(rawValue: choice.repoID) else { return false }
        let cache = HuggingFace.HubCache.default
        guard let commit = cache.resolveRevision(repo: repo, kind: .model, ref: "main"),
              let snapshot = try? cache.snapshotPath(repo: repo, kind: .model, commitHash: commit)
        else { return false }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: snapshot.path)) ?? []
        return files.contains { $0.hasSuffix(".safetensors") }
    }

    /// Defensive cleanup in case a `<think>...</think>` block slips through
    /// despite `enable_thinking: false` / `/no_think`.
    private static func stripThinkingTags(_ text: String) -> String {
        guard let start = text.range(of: "<think>"),
              let end = text.range(of: "</think>", range: start.upperBound..<text.endIndex)
        else { return text }
        var result = text
        result.removeSubrange(start.lowerBound..<end.upperBound)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif
}

enum LocalLLMError: LocalizedError {
    case unsupportedEnvironment
    case downloadOrLoadFailed(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedEnvironment:
            return "On-device AI needs a real iPhone GPU and isn't available in the Simulator."
        case .downloadOrLoadFailed(let message):
            return "Couldn't download or load the on-device AI model: \(message)"
        case .generationFailed(let message):
            return "The on-device AI model failed to respond: \(message)"
        }
    }
}

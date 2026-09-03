import Foundation
import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct RecordingDetailView: View {
    let recordingID: UUID
    var onDelete: () -> Void = {}

    @Environment(RecordingStore.self) private var store
    @Environment(TranscriptionService.self) private var transcription
    @Environment(PurchaseManager.self) private var purchases
    @Environment(SummaryService.self) private var summary

    @State private var player = AudioPlayer()
    @State private var showingDeleteConfirm = false
    @State private var showingExportSheet = false
    @State private var showingPaywall = false
    @State private var showingAddTag = false
    @State private var newTagText = ""
    @State private var suggestedTags: [String] = []
    @State private var isSuggestingTags = false
    @State private var showingVocabularySheet = false
    @State private var showingAskSheet = false
    @State private var showingTranslation = false
    @State private var translationSource: String = ""
    @State private var calendarError: String?
    @State private var isPreparingLocalModel = false
    @State private var localModelDownloadError: String?
    @AppStorage("Echograph.preferredLanguage") private var preferredLanguageRaw: String = TranscriptionLanguage.auto.rawValue
    @AppStorage("Echograph.customVocabulary") private var customVocabulary: String = ""

    private var preferredLanguage: TranscriptionLanguage {
        TranscriptionLanguage(rawValue: preferredLanguageRaw) ?? .auto
    }

    private var recording: Recording? {
        store.recordings.first(where: { $0.id == recordingID })
    }

    var body: some View {
        Group {
            if let recording {
                content(for: recording)
            } else {
                ContentUnavailableView("Recording missing", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let recording {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingExportSheet = true
                        } label: {
                            Label("Export…", systemImage: "square.and.arrow.up")
                        }
                        .disabled(recording.transcript == nil)

                        // On-device analysis — Apple Intelligence when available,
                        // otherwise the local Qwen3 fallback (App Store-friendly),
                        // available to Pro+.
                        Button {
                            if !purchases.hasProPlus {
                                showingPaywall = true
                            } else if aiUIState == .needsDownload || aiUIState == .downloading {
                                downloadLocalModelIfNeeded()
                            } else if aiUIState == .unavailable {
                                // no-op; nothing can answer (Simulator, in practice)
                            } else {
                                Task { await summary.analyze(recording) }
                            }
                        } label: {
                            if summary.isRunning(for: recording.id) {
                                Label("Analyzing…", systemImage: "sparkles")
                            } else {
                                Label(purchases.hasProPlus ? "Deep Analysis (AI)…" : "Deep Analysis · Pro+",
                                      systemImage: purchases.hasProPlus ? "sparkles" : "lock.fill")
                            }
                        }
                        .disabled(recording.transcript == nil || summary.isRunning(for: recording.id))

                        Button {
                            translationSource = recording.transcript?.fullText ?? ""
                            showingTranslation = true
                        } label: {
                            Label("Translate Transcript…", systemImage: "translate")
                        }
                        .disabled(recording.transcript == nil)

                        Button {
                            Task { await addToCalendar(recording) }
                        } label: {
                            Label("Add to Calendar", systemImage: "calendar.badge.plus")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this recording?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                player.stop()
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingExportSheet) {
            if let recording {
                ExportSheet(recording: recording)
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .alert("Add tag", isPresented: $showingAddTag) {
            TextField("e.g. interview", text: $newTagText)
                .textInputAutocapitalization(.never)
            Button("Add") {
                if let recording { addTag(to: recording) }
            }
            Button("Cancel", role: .cancel) { newTagText = "" }
        }
        .sheet(isPresented: $showingVocabularySheet) {
            VocabularySheet(text: $customVocabulary)
        }
        .sheet(isPresented: $showingAskSheet) {
            if let recording {
                AskSheet(recording: recording)
            }
        }
        .modifier(TranslationOverlay(isPresented: $showingTranslation, text: translationSource))
        .alert("Calendar error", isPresented: Binding(
            get: { calendarError != nil },
            set: { if !$0 { calendarError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(calendarError ?? "")
        }
        .onAppear {
            if let recording {
                player.load(url: recording.fileURL)
            }
        }
        .onDisappear {
            player.stop()
        }
    }

    @ViewBuilder
    private func content(for recording: Recording) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recording.title)
                        .font(.title2.weight(.semibold))
                    Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    tagsRow(for: recording)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                playerCard

                transcriptSection(for: recording)
            }
            .padding(.top)
            .padding(.bottom, 32)
        }
    }

    private var playerCard: some View {
        VStack(spacing: 16) {
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 0.01)
            )

            HStack {
                Text(format(time: player.currentTime))
                    .monospacedDigit()
                Spacer()
                Text(format(time: player.duration))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                if player.isPlaying {
                    player.pause()
                } else {
                    player.play()
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: player.isPlaying)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    @ViewBuilder
    private func transcriptSection(for recording: Recording) -> some View {
        if let transcript = recording.transcript {
            VStack(spacing: 16) {
                summarySection(for: recording)
                // Deep analysis via on-device Apple Intelligence (Pro+).
                if recording.analysis != nil {
                    AnalysisSection(analysis: recording.analysis)
                        .padding(.horizontal)
                }
                TranscriptView(
                    transcript: transcript,
                    currentTime: player.currentTime,
                    recordingTitle: recording.title,
                    onTapSegment: { player.seek(to: $0); player.play() },
                    onEditSegment: { segment, newText in
                        updateSegment(segment, text: newText, in: recording)
                    },
                    onToggleHighlight: { segment in
                        toggleHighlight(segment, in: recording)
                    },
                    onAssignSpeaker: { segment, speaker in
                        assignSpeaker(speaker, to: segment, in: recording)
                    },
                    onRenameSpeaker: { speaker, newName in
                        renameSpeaker(speaker, to: newName, in: recording)
                    }
                )
            }
        } else if transcription.isRunning(for: recording.id) {
            VStack(spacing: 12) {
                ProgressView()
                Text(transcription.phase(for: recording.id) ?? "Transcribing on-device…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
        } else if let error = transcription.errorMessage(for: recording.id) {
            VStack(spacing: 12) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Button("Try Again") {
                    transcription.clearError()
                    transcribeWithParakeet(recording)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 24)
        } else {
            VStack(spacing: 16) {
                ContentUnavailableView {
                    Label("No transcript yet", systemImage: "text.bubble")
                } description: {
                    Text("Transcribe on-device. Audio stays on your iPhone.")
                }
                HStack(spacing: 10) {
                    // Language picker (separate from engine menu so the engine
                    // buttons stay visible after selection).
                    Menu {
                        Picker("Language", selection: Binding(
                            get: { preferredLanguage },
                            set: { preferredLanguageRaw = $0.rawValue }
                        )) {
                            ForEach(TranscriptionLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                    } label: {
                        Label(preferredLanguage.displayName, systemImage: "globe")
                            .padding(.horizontal, 4)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)

                    // Engine menu — Apple Speech or Parakeet.
                    Menu {
                        Button {
                            Task { await transcription.transcribe(recording, using: .appleSpeech, languageHint: preferredLanguage.languageHint) }
                        } label: {
                            Label("Apple Speech (fast, free)", systemImage: "waveform")
                        }
                        Section("Parakeet") {
                            Button {
                                transcribeWithParakeet(recording, vocabularyPrompt: customVocabulary)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Parakeet v3 (~\(ParakeetTranscriber.downloadSizeMB) MB)")
                                        if let status = freeTranscriptionStatusText {
                                            Text(status)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: "wand.and.stars")
                                }
                            }
                            .accessibilityIdentifier("parakeetOption")
                            Divider()
                            Button {
                                showingVocabularySheet = true
                            } label: {
                                let count = customVocabulary
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .components(separatedBy: .whitespacesAndNewlines)
                                    .filter { !$0.isEmpty }
                                    .count
                                Label(
                                    count > 0 ? "Custom Vocabulary (\(count) terms)" : "Add Custom Vocabulary…",
                                    systemImage: "text.book.closed"
                                )
                            }
                        }
                    } label: {
                        Label("Transcribe", systemImage: "wand.and.stars")
                            .padding(.horizontal, 8)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("transcribeMenu")
                }
            }
            .padding(.top, 16)
        }
    }

    private func format(time: TimeInterval) -> String {
        let total = Int(time.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    private func summarySection(for recording: Recording) -> some View {
        if let summary = recording.summary {
            VStack(alignment: .leading, spacing: 8) {
                Label("AI Summary", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(summary)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                askButton
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
        } else if self.summary.isRunning(for: recording.id) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Generating summary…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else if purchases.hasProPlus && (aiUIState == .needsDownload || aiUIState == .downloading) {
            downloadPromptView
                .padding(.horizontal)
        } else {
            VStack(spacing: 8) {
                Button {
                    if !purchases.hasProPlus {
                        showingPaywall = true
                    } else if aiUIState != .ready {
                        // handled by downloadPromptView above
                    } else {
                        Task { await self.summary.summarize(recording) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: purchases.hasProPlus ? "sparkles" : "lock.fill")
                        Text(summaryButtonLabel)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                askButton
            }
            .padding(.horizontal)
        }
    }

    /// The three states the local AI backend can be in from this view's
    /// perspective. Apple Intelligence, when it's the active backend, is
    /// always `.ready` — nothing to download.
    private enum AIUIState: Equatable {
        case ready
        case needsDownload
        case downloading
        /// Neither backend can answer (only the Simulator, in practice).
        case unavailable
    }

    private var aiUIState: AIUIState {
        switch summary.activeBackend {
        case .appleIntelligence:
            return .ready
        case .localModel:
            if summary.isLocalModelReady { return .ready }
            return isPreparingLocalModel ? .downloading : .needsDownload
        case .none:
            return .unavailable
        }
    }

    /// Shared by the summary button, the ask button and the tag-suggest
    /// button — whichever the user taps first kicks off the one-time
    /// download, and all three reflect its progress the same way.
    private func downloadLocalModelIfNeeded() {
        guard !isPreparingLocalModel else { return }
        isPreparingLocalModel = true
        localModelDownloadError = nil
        Task {
            do {
                try await summary.prepareLocalModel()
            } catch {
                localModelDownloadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isPreparingLocalModel = false
        }
    }

    @ViewBuilder
    private var downloadPromptView: some View {
        VStack(spacing: 8) {
            Text("The AI model runs on your device. It downloads once — you'll only need internet for that.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button {
                downloadLocalModelIfNeeded()
            } label: {
                HStack(spacing: 8) {
                    if aiUIState == .downloading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                    Text(downloadButtonLabel)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(aiUIState == .downloading)

            if let localModelDownloadError {
                Text(localModelDownloadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var downloadButtonLabel: String {
        if aiUIState == .downloading {
            let percent = Int(summary.localModelDownloadProgress * 100)
            return String(localized: "Downloading…") + " \(percent)%"
        }
        return String(localized: "Download AI Model (\(summary.localModelSizeMB) MB)")
    }

    @ViewBuilder
    private var askButton: some View {
        Button {
            if !purchases.hasProPlus {
                showingPaywall = true
            } else if aiUIState == .needsDownload || aiUIState == .downloading {
                downloadLocalModelIfNeeded()
            } else if aiUIState == .unavailable {
                // no-op; the button label already explains it
            } else {
                showingAskSheet = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: purchases.hasProPlus ? "bubble.left.and.text.bubble.right" : "lock.fill")
                Text(askButtonLabel)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var askButtonLabel: String {
        if !purchases.hasProPlus { return String(localized: "Ask AI · Pro+") }
        switch aiUIState {
        case .ready: return String(localized: "Ask AI")
        case .needsDownload, .downloading: return downloadButtonLabel
        case .unavailable: return String(localized: "On-device AI unavailable")
        }
    }

    private var summaryButtonLabel: String {
        if !purchases.hasProPlus { return String(localized: "AI Summary · Pro+") }
        switch aiUIState {
        case .ready: return String(localized: "Generate AI Summary")
        case .needsDownload, .downloading: return downloadButtonLabel
        case .unavailable: return String(localized: "On-device AI unavailable")
        }
    }

    /// Runs Parakeet, gated by `FreeTranscriptionLimiter` for non-subscribers
    /// — shows the paywall instead of transcribing once the free quota is
    /// spent. Shared by the "Transcribe" menu and the error screen's
    /// "Try Again" button so both respect the same gate.
    private func transcribeWithParakeet(_ recording: Recording, vocabularyPrompt: String? = nil) {
        if !purchases.hasPro && FreeTranscriptionLimiter.isExhausted {
            showingPaywall = true
            return
        }
        Task {
            await transcription.transcribe(
                recording,
                using: .parakeet,
                languageHint: preferredLanguage.languageHint,
                vocabularyPrompt: vocabularyPrompt,
                unlimited: purchases.hasPro
            )
        }
    }

    /// `nil` for subscribers (no quota to report). Otherwise one of three
    /// states: a pluralized "N left" count, a "last one" warning at 1, or
    /// "used up" at 0 — matches `FreeTranscriptionLimiter`.
    private var freeTranscriptionStatusText: String? {
        guard !purchases.hasPro else { return nil }
        let remaining = FreeTranscriptionLimiter.remaining
        if remaining <= 0 { return String(localized: "Free transcriptions used up") }
        if remaining == 1 { return String(localized: "Last free transcription") }
        return String(localized: "\(remaining) free transcriptions left")
    }

    private func updateSegment(_ segment: Transcript.Segment, text: String, in recording: Recording) {
        guard var transcript = recording.transcript,
              let idx = transcript.segments.firstIndex(where: { $0.id == segment.id }) else { return }
        transcript.segments[idx].text = text
        // Word-level timestamps no longer match the edited text — drop them so
        // the user isn't confused by stale per-word data.
        transcript.segments[idx].words = []
        var updated = recording
        updated.transcript = transcript
        store.update(updated)
    }

    @ViewBuilder
    private func tagsRow(for recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(recording.tags, id: \.self) { tag in
                    Menu {
                        Button(role: .destructive) {
                            removeTag(tag, from: recording)
                        } label: {
                            Label("Remove “\(tag)”", systemImage: "xmark")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                                .imageScale(.small)
                            Text(tag)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                    }
                }
                Button {
                    newTagText = ""
                    showingAddTag = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .imageScale(.small)
                        Text(recording.tags.isEmpty ? "Add tag" : "Add")
                    }
                    .font(.caption.weight(.medium))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                if recording.transcript != nil && aiUIState != .unavailable {
                    Button {
                        if aiUIState == .needsDownload || aiUIState == .downloading {
                            downloadLocalModelIfNeeded()
                        } else {
                            Task { await suggestTags(for: recording) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isSuggestingTags || aiUIState == .downloading {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: aiUIState == .needsDownload ? "arrow.down.circle" : "sparkles")
                                    .imageScale(.small)
                            }
                            Text("Suggest")
                        }
                        .font(.caption.weight(.medium))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSuggestingTags || aiUIState == .downloading)
                }
                Spacer(minLength: 0)
            }
            if !suggestedTags.isEmpty {
                let pending = suggestedTags.filter { !recording.tags.contains($0) }
                if !pending.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(pending, id: \.self) { tag in
                            Button {
                                addSuggestedTag(tag, to: recording)
                            } label: {
                                Text("+ \(tag)")
                                    .font(.caption2.weight(.medium))
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 7)
                                    .background(.tint.opacity(0.08), in: Capsule())
                                    .foregroundStyle(.tint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func suggestTags(for recording: Recording) async {
        guard let transcript = recording.transcript else { return }
        isSuggestingTags = true
        defer { isSuggestingTags = false }
        do {
            suggestedTags = try await summary.suggestTags(for: transcript)
        } catch {
            // Reuse the summary service's localized error path is overkill here;
            // fail silently so the user can retry.
            suggestedTags = []
        }
    }

    private func addSuggestedTag(_ tag: String, to recording: Recording) {
        var updated = recording
        if !updated.tags.contains(tag) {
            updated.tags.append(tag)
            store.update(updated)
        }
        suggestedTags.removeAll { $0 == tag }
    }

    private func addToCalendar(_ recording: Recording) async {
        let notes = recording.summary
            ?? recording.transcript?.fullText
            ?? "Recorded with Echograph."
        do {
            try await CalendarService.addEvent(
                title: recording.title,
                startDate: recording.createdAt,
                duration: recording.duration,
                notes: notes
            )
        } catch {
            calendarError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func addTag(to recording: Recording) {
        let trimmed = newTagText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard !trimmed.isEmpty else { return }
        var updated = recording
        if !updated.tags.contains(trimmed) {
            updated.tags.append(trimmed)
            store.update(updated)
        }
        newTagText = ""
    }

    private func removeTag(_ tag: String, from recording: Recording) {
        var updated = recording
        updated.tags.removeAll { $0 == tag }
        store.update(updated)
    }

    private func toggleHighlight(_ segment: Transcript.Segment, in recording: Recording) {
        guard var transcript = recording.transcript,
              let idx = transcript.segments.firstIndex(where: { $0.id == segment.id }) else { return }
        transcript.segments[idx].isHighlighted.toggle()
        var updated = recording
        updated.transcript = transcript
        store.update(updated)
    }

    private func assignSpeaker(_ speaker: Transcript.Speaker?, to segment: Transcript.Segment, in recording: Recording) {
        guard var transcript = recording.transcript,
              let idx = transcript.segments.firstIndex(where: { $0.id == segment.id }) else { return }
        transcript.segments[idx].speaker = speaker
        var updated = recording
        updated.transcript = transcript
        updated.speakerCount = Set(transcript.segments.compactMap { $0.speaker?.id }).count
        store.update(updated)
    }

    private func renameSpeaker(_ speaker: Transcript.Speaker, to newName: String, in recording: Recording) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var transcript = recording.transcript else { return }
        for i in transcript.segments.indices where transcript.segments[i].speaker?.id == speaker.id {
            transcript.segments[i].speaker?.label = trimmed
        }
        var updated = recording
        updated.transcript = transcript
        store.update(updated)
    }
}

private struct TranscriptView: View {
    let transcript: Transcript
    let currentTime: TimeInterval
    let recordingTitle: String
    let onTapSegment: (TimeInterval) -> Void
    let onEditSegment: (Transcript.Segment, String) -> Void
    let onToggleHighlight: (Transcript.Segment) -> Void
    let onAssignSpeaker: (Transcript.Segment, Transcript.Speaker?) -> Void
    let onRenameSpeaker: (Transcript.Speaker, String) -> Void

    @State private var editingSegment: Transcript.Segment?
    @State private var editingText: String = ""
    @State private var showOnlyHighlights = false
    @State private var reminderError: String?
    @State private var renamingSpeaker: Transcript.Speaker?
    @State private var renameSpeakerText: String = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if hasAnyHighlight {
                        Toggle(isOn: $showOnlyHighlights.animation(.easeInOut(duration: 0.2))) {
                            Label("Show only highlights", systemImage: "highlighter")
                                .font(.subheadline)
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .padding(.horizontal, 12)
                    }

                    ForEach(visibleSegments) { segment in
                        Button {
                            onTapSegment(segment.startTime)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                if let speaker = segment.speaker {
                                    SpeakerBadge(
                                        speaker: speaker,
                                        color: speakerColor(for: speaker)
                                    )
                                }
                                HStack(alignment: .top, spacing: 12) {
                                    Text(timecode(segment.startTime))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 56, alignment: .leading)
                                    Text(segment.text)
                                        .font(.body)
                                        .foregroundStyle(isActive(segment) ? Color.primary : Color.secondary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(rowBackground(for: segment))
                            )
                            .overlay(alignment: .topTrailing) {
                                if segment.isHighlighted {
                                    Image(systemName: "highlighter")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                        .padding(6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(segment.id)
                        .contextMenu {
                            speakerSubmenu(for: segment)

                            Button {
                                onToggleHighlight(segment)
                            } label: {
                                Label(
                                    segment.isHighlighted ? "Remove Highlight" : "Highlight",
                                    systemImage: "highlighter"
                                )
                            }
                            Button {
                                editingText = segment.text
                                editingSegment = segment
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Divider()
                            Button {
                                UIPasteboard.general.string = segment.text
                            } label: {
                                Label("Copy Text", systemImage: "doc.on.doc")
                            }
                            Button {
                                UIPasteboard.general.string = "[\(timecode(segment.startTime))] \(segment.text)"
                            } label: {
                                Label("Copy with Timecode", systemImage: "clock")
                            }
                            ShareLink(item: "[\(timecode(segment.startTime))] \(segment.text)") {
                                Label("Share…", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                Task { await addToReminders(segment) }
                            } label: {
                                Label("Add to Reminders", systemImage: "checklist")
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .onChange(of: activeSegmentID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            .sheet(item: $editingSegment) { segment in
                EditSegmentSheet(
                    initialText: segment.text,
                    timecode: timecode(segment.startTime)
                ) { updated in
                    onEditSegment(segment, updated)
                    editingSegment = nil
                }
            }
            .alert("Reminder error", isPresented: Binding(
                get: { reminderError != nil },
                set: { if !$0 { reminderError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(reminderError ?? "")
            }
            .alert("Rename speaker", isPresented: Binding(
                get: { renamingSpeaker != nil },
                set: { if !$0 { renamingSpeaker = nil } }
            )) {
                TextField("Name", text: $renameSpeakerText)
                Button("Save") {
                    if let speaker = renamingSpeaker {
                        onRenameSpeaker(speaker, renameSpeakerText)
                    }
                    renamingSpeaker = nil
                }
                Button("Cancel", role: .cancel) { renamingSpeaker = nil }
            }
        }
    }

    @ViewBuilder
    private func speakerSubmenu(for segment: Transcript.Segment) -> some View {
        Menu {
            // Existing speakers in this transcript
            ForEach(allSpeakers) { sp in
                Button {
                    onAssignSpeaker(segment, sp)
                } label: {
                    if segment.speaker?.id == sp.id {
                        Label(sp.label, systemImage: "checkmark")
                    } else {
                        Text(sp.label)
                    }
                }
            }
            if !allSpeakers.isEmpty { Divider() }
            Button {
                let newSpeaker = Transcript.Speaker(
                    label: "Speaker \(allSpeakers.count + 1)"
                )
                onAssignSpeaker(segment, newSpeaker)
            } label: {
                Label("New Speaker", systemImage: "person.badge.plus")
            }
            if let current = segment.speaker {
                Button {
                    renameSpeakerText = current.label
                    renamingSpeaker = current
                } label: {
                    Label("Rename “\(current.label)”", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onAssignSpeaker(segment, nil)
                } label: {
                    Label("Remove Speaker", systemImage: "person.fill.xmark")
                }
            }
        } label: {
            Label(
                segment.speaker.map { "Speaker · \($0.label)" } ?? "Assign Speaker",
                systemImage: "person.wave.2"
            )
        }
    }

    private var allSpeakers: [Transcript.Speaker] {
        var seen: [UUID: Transcript.Speaker] = [:]
        var ordered: [Transcript.Speaker] = []
        for s in transcript.segments {
            if let sp = s.speaker, seen[sp.id] == nil {
                seen[sp.id] = sp
                ordered.append(sp)
            }
        }
        return ordered
    }

    private func speakerColor(for speaker: Transcript.Speaker) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown]
        let index = allSpeakers.firstIndex(where: { $0.id == speaker.id }) ?? 0
        return palette[index % palette.count]
    }

    private func addToReminders(_ segment: Transcript.Segment) async {
        let title = segment.text.prefix(120).description
        let notes = "From “\(recordingTitle)” at \(timecode(segment.startTime))"
        do {
            try await RemindersService.addReminder(title: title, notes: notes)
        } catch {
            reminderError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var activeSegmentID: UUID? {
        transcript.segments.first(where: isActive)?.id
    }

    private var visibleSegments: [Transcript.Segment] {
        showOnlyHighlights
            ? transcript.segments.filter(\.isHighlighted)
            : transcript.segments
    }

    private var hasAnyHighlight: Bool {
        transcript.segments.contains(where: \.isHighlighted)
    }

    private func isActive(_ segment: Transcript.Segment) -> Bool {
        currentTime >= segment.startTime && currentTime < segment.endTime
    }

    private func rowBackground(for segment: Transcript.Segment) -> Color {
        if segment.isHighlighted { return .yellow.opacity(0.18) }
        if isActive(segment) { return .accentColor.opacity(0.12) }
        return .clear
    }

    private func timecode(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Wraps Apple's translationPresentation modifier so callers don't need to
/// `#if canImport(Translation)` themselves.
private struct TranslationOverlay: ViewModifier {
    @Binding var isPresented: Bool
    let text: String

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(iOS 17.4, *) {
            content.translationPresentation(isPresented: $isPresented, text: text)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct VocabularySheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add proper nouns, technical terms, brand names you want the transcript to get right. One per line works best.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .padding(.horizontal, 12)
                    .focused($focused)
            }
            .padding(.top, 8)
            .navigationTitle("Custom Vocabulary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", role: .destructive) { text = "" }
                        .disabled(text.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }
}

private struct SpeakerBadge: View {
    let speaker: Transcript.Speaker
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(speaker.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}

private struct EditSegmentSheet: View {
    let initialText: String
    let timecode: String
    let onSave: (String) -> Void

    @State private var text: String = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Timecode \(timecode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                TextEditor(text: $text)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .focused($focused)
            }
            .padding(.top, 8)
            .navigationTitle("Edit Segment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || text == initialText)
                }
            }
            .onAppear {
                text = initialText
                focused = true
            }
        }
    }
}

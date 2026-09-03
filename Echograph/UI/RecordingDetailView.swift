import Foundation
import SwiftUI
import MarkdownUI
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
    @State private var showingAISettings = false
    @State private var showingAddTag = false
    @State private var newTagText = ""
    @State private var suggestedTags: [String] = []
    @State private var isSuggestingTags = false
    @State private var showingAskSheet = false
    @State private var askInitialQuestion = ""
    @State private var quickAskText = ""
    @FocusState private var quickAskFocused: Bool
    @State private var showingTranslation = false
    @State private var translationSource: String = ""
    @State private var calendarError: String?
    @State private var selectedTab: DetailTab = .transcript
    @AppStorage("Echograph.preferredLanguage") private var preferredLanguageRaw: String = TranscriptionLanguage.auto.rawValue

    private var preferredLanguage: TranscriptionLanguage {
        TranscriptionLanguage(rawValue: preferredLanguageRaw) ?? .auto
    }

    private var recording: Recording? {
        store.recordings.first(where: { $0.id == recordingID })
    }

    /// The two panes of the recording screen. "Summary" shows exactly the
    /// content that used to be stacked under the transcript, split into its
    /// own pane.
    private enum DetailTab: String, CaseIterable, Identifiable {
        case transcript, summary
        var id: String { rawValue }
        var title: String {
            switch self {
            case .transcript: return String(localized: "Transcript")
            case .summary: return String(localized: "Summary")
            }
        }
    }

    var body: some View {
        Group {
            if let recording {
                content(for: recording)
            } else {
                ContentUnavailableView("Recording missing", systemImage: "exclamationmark.triangle")
            }
        }
        .background(DS.Color.background)
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let recording {
                if selectedTab == .transcript, let transcript = recording.transcript, !transcript.segments.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: shareText(forTranscript: transcript, in: recording)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(Text("Share Transcript"))
                        .tint(DS.Color.accent)
                    }
                } else if selectedTab == .summary, let summaryText = recording.summary, !summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: shareText(forSummary: summaryText, in: recording)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(Text("Share Summary"))
                        .tint(DS.Color.accent)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Продублировано в меню с подписью: иконку «поделиться»
                        // в панели навигации пользователи не находят.
                        if let transcript = recording.transcript {
                            ShareLink(item: shareText(forTranscript: transcript, in: recording)) {
                                Label(String(localized: "Share Transcript"), systemImage: "square.and.arrow.up")
                            }
                        }
                        if let summaryText = recording.summary, !summaryText.isEmpty {
                            ShareLink(item: shareText(forSummary: summaryText, in: recording)) {
                                Label(String(localized: "Share Summary"), systemImage: "square.and.arrow.up")
                            }
                        }

                        Divider()

                        Button {
                            showingExportSheet = true
                        } label: {
                            Label("Export…", systemImage: "square.and.arrow.up")
                        }
                        .disabled(recording.transcript == nil)

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
                    .tint(DS.Color.accent)
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
        .sheet(isPresented: $showingAISettings) {
            SettingsView()
        }
        .alert("Add tag", isPresented: $showingAddTag) {
            TextField("e.g. interview", text: $newTagText)
                .textInputAutocapitalization(.never)
            Button("Add") {
                if let recording { addTag(to: recording) }
            }
            Button("Cancel", role: .cancel) { newTagText = "" }
        }
        .sheet(isPresented: $showingAskSheet) {
            if let recording {
                AskSheet(recording: recording, initialQuestion: askInitialQuestion)
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
        VStack(alignment: .leading, spacing: 0) {
            headerBlock(for: recording)
                .padding(.top, 12)

            playerRow
                .padding(.top, 18)

            Hairline()
                .padding(.top, 16)

            if recording.transcript != nil {
                tabPicker
                    .padding(.horizontal, DS.Spacing.horizontal)
                    .padding(.top, 14)

                tabContent(for: recording)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                noTranscriptState(for: recording)
                    .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            askBar(for: recording)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerBlock(for recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recording.title)
                .font(DS.Typography.recordingTitle)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(3)

            HStack(spacing: 6) {
                Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text("·")
                Text(durationLabel(recording.duration))
                if let transcript = recording.transcript {
                    Text("·")
                    Text(languageLabel(transcript.language))
                }
            }
            .font(DS.Typography.secondary)
            .foregroundStyle(DS.Color.textSecondary)

            tagsRow(for: recording)
        }
        .padding(.horizontal, DS.Spacing.horizontal)
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: duration) ?? ""
    }

    private func languageLabel(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    // MARK: - Player (compact row, not a card)

    private var playerRow: some View {
        HStack(spacing: 12) {
            Button {
                if player.isPlaying {
                    player.pause()
                } else {
                    player.play()
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(DS.Color.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: player.isPlaying)

            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 0.01)
            )
            .tint(DS.Color.accent)

            Text("\(format(time: player.currentTime))/\(format(time: player.duration))")
                .font(DS.Typography.timecode)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize()
        }
        .padding(.horizontal, DS.Spacing.horizontal)
    }

    // MARK: - Tabs

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(DetailTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func tabContent(for recording: Recording) -> some View {
        switch selectedTab {
        case .transcript:
            if let transcript = recording.transcript {
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
        case .summary:
            summaryTab(for: recording)
        }
    }

    /// "Конспект" — a document-style summary: bold section openers,
    /// numbered/bulleted lists, air between blocks, no card chrome.
    @ViewBuilder
    private func summaryTab(for recording: Recording) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summaryText = recording.summary {
                    Markdown(summaryText)
                        .markdownTheme(.gitHub)
                        .textSelection(.enabled)
                } else if summary.isRunning(for: recording.id) {
                    generatingRow("Generating summary…")
                } else if !purchases.hasProPlus {
                    generateButton(icon: "lock.fill", label: String(localized: "AI Summary · Pro+")) {
                        showingPaywall = true
                    }
                } else if summary.isAvailable {
                    generateButton(icon: "sparkles", label: String(localized: "Generate AI Summary")) {
                        Task { await self.summary.summarize(recording) }
                    }
                } else {
                    aiModelNeededState()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }

    private func generatingRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    @ViewBuilder
    private func generateButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(label).fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(DS.Color.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.field))
            .foregroundStyle(DS.Color.accent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - No-transcript state

    @ViewBuilder
    private func noTranscriptState(for recording: Recording) -> some View {
        if transcription.isRunning(for: recording.id) {
            VStack(spacing: 12) {
                ProgressView()
                Text(transcription.phase(for: recording.id) ?? "Transcribing on-device…")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
        } else if let error = transcription.errorMessage(for: recording.id) {
            VStack(spacing: 12) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.horizontal)
                Button("Try Again") {
                    transcription.clearError()
                    transcribeRecording(recording)
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Color.accent)
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
                    .tint(DS.Color.accent)

                    // Single button — Apple Speech is the only transcription
                    // engine now (Parakeet was removed: its model download
                    // from Hugging Face silently failed on real devices).
                    Button {
                        transcribeRecording(recording)
                    } label: {
                        VStack(spacing: 2) {
                            Label("Transcribe", systemImage: "wand.and.stars")
                            if let status = freeTranscriptionStatusText {
                                Text(status)
                                    .font(.caption2)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Color.accent)
                    .accessibilityIdentifier("transcribeButton")
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

    // MARK: - Share

    /// "[мм:сс] Speaker: text" per line, one line per segment, under a
    /// two-line header (title, then date · duration) and a blank line.
    private func shareText(forTranscript transcript: Transcript, in recording: Recording) -> String {
        var lines = [
            recording.title,
            "\(recording.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(durationLabel(recording.duration))",
            "",
        ]
        // Сегменты распознавания бывают очень короткими (вплоть до слова),
        // поэтому в отправку идёт сплошной текст, а не строка на сегмент.
        // Новый абзац — только когда меняется говорящий.
        var paragraphs: [String] = []
        var current: [String] = []
        var currentSpeaker: String?? = nil
        for segment in transcript.segments {
            let speaker = segment.speaker?.label
            if currentSpeaker != nil, currentSpeaker! != speaker, !current.isEmpty {
                paragraphs.append(paragraph(current, speaker: currentSpeaker!))
                current = []
            }
            currentSpeaker = .some(speaker)
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { current.append(text) }
        }
        if !current.isEmpty { paragraphs.append(paragraph(current, speaker: currentSpeaker ?? nil)) }
        lines.append(paragraphs.joined(separator: "\n\n"))
        return lines.joined(separator: "\n")
    }

    private func paragraph(_ parts: [String], speaker: String?) -> String {
        let body = parts.joined(separator: " ")
        return speaker.map { "\($0): \(body)" } ?? body
    }

    private func shareText(forSummary summaryText: String, in recording: Recording) -> String {
        "\(recording.title)\n\n\(summaryText)"
    }

    private func shareTimecode(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// Shown on the "Конспект" tab when Apple Intelligence is unavailable
    /// and the local fallback model hasn't been downloaded yet. Never
    /// starts a download itself — it only points at the "AI Model" section
    /// in Settings, where the user explicitly opts in.
    @ViewBuilder
    private func aiModelNeededState() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI model needed for summaries")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.textSecondary)
            Button {
                showingAISettings = true
            } label: {
                Text("Open Settings")
                    .fontWeight(.medium)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.Color.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Ask bar (pinned)

    /// Quick entry point pinned to the bottom of the screen. For a
    /// free user it shows a lock and opens the paywall; otherwise it opens
    /// `AskSheet` pre-filled with whatever was typed here.
    @ViewBuilder
    private func askBar(for recording: Recording) -> some View {
        Group {
            if !purchases.hasProPlus {
                Button {
                    showingPaywall = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(DS.Color.textSecondary)
                        Text("Ask about this recording · Pro+")
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .font(DS.Typography.body)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.field))
                }
                .buttonStyle(.plain)
            } else if recording.transcript == nil {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .foregroundStyle(DS.Color.textTertiary)
                    Text("Transcribe first to ask about this recording")
                        .foregroundStyle(DS.Color.textTertiary)
                    Spacer(minLength: 0)
                }
                .font(DS.Typography.body)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.field))
            } else {
                HStack(spacing: 8) {
                    TextField("Ask about this recording…", text: $quickAskText, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($quickAskFocused)
                        .submitLabel(.send)
                        .onSubmit { openAskSheet() }
                    Button {
                        openAskSheet()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                            .frame(width: 26, height: 26)
                            .foregroundStyle(DS.Color.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quickAskSend")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.field))
            }
        }
        .padding(.horizontal, DS.Spacing.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func openAskSheet() {
        askInitialQuestion = quickAskText
        quickAskText = ""
        quickAskFocused = false
        showingAskSheet = true
    }

    /// Runs the transcription, gated by `FreeTranscriptionLimiter` for
    /// non-subscribers — shows the paywall instead of transcribing once the
    /// free quota is spent. Shared by the "Transcribe" button and the error
    /// screen's "Try Again" button so both respect the same gate.
    private func transcribeRecording(_ recording: Recording) {
        if !purchases.hasPro && FreeTranscriptionLimiter.isExhausted {
            showingPaywall = true
            return
        }
        Task {
            await transcription.transcribe(
                recording,
                languageHint: preferredLanguage.languageHint,
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
            // Horizontal scroll (not a wrapping HStack) so pills keep their
            // natural pill shape instead of squeezing their text onto two
            // lines when there isn't room for everything.
            ScrollView(.horizontal, showsIndicators: false) {
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
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .font(DS.Typography.pill)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(DS.Color.lavender, in: Capsule())
                            .foregroundStyle(DS.Color.textPrimary)
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
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .font(DS.Typography.pill)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(DS.Color.surface, in: Capsule())
                        .foregroundStyle(DS.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    if recording.transcript != nil && summary.isAvailable {
                        Button {
                            Task { await suggestTags(for: recording) }
                        } label: {
                            HStack(spacing: 4) {
                                if isSuggestingTags {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "sparkles")
                                        .imageScale(.small)
                                }
                                Text("Suggest")
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .font(DS.Typography.pill)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(DS.Color.surface, in: Capsule())
                            .foregroundStyle(DS.Color.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSuggestingTags)
                    }
                }
            }
            if !suggestedTags.isEmpty {
                let pending = suggestedTags.filter { !recording.tags.contains($0) }
                if !pending.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(DS.Color.textSecondary)
                        ForEach(pending, id: \.self) { tag in
                            Button {
                                addSuggestedTag(tag, to: recording)
                            } label: {
                                Text("+ \(tag)")
                                    .font(.caption2.weight(.medium))
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 7)
                                    .background(DS.Color.mint, in: Capsule())
                                    .foregroundStyle(DS.Color.textPrimary)
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
                VStack(alignment: .leading, spacing: 16) {
                    if hasAnyHighlight {
                        Toggle(isOn: $showOnlyHighlights.animation(.easeInOut(duration: 0.2))) {
                            Label("Show only highlights", systemImage: "highlighter")
                                .font(.subheadline)
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .tint(DS.Color.accent)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(visibleSegments) { segment in
                            Button {
                                onTapSegment(segment.startTime)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Text(timecode(segment.startTime))
                                        .font(DS.Typography.timecode)
                                        .foregroundStyle(DS.Color.textSecondary)
                                        .frame(width: 52, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let speaker = segment.speaker {
                                            PastelPill(
                                                text: speaker.label,
                                                tint: speakerPastel(for: speaker),
                                                foreground: DS.Color.textPrimary
                                            )
                                        }
                                        Text(segment.text)
                                            .font(DS.Typography.body)
                                            .foregroundStyle(isActive(segment) ? DS.Color.textPrimary : DS.Color.textSecondary)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
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
                }
                .padding(.horizontal, DS.Spacing.horizontal)
                .padding(.top, 16)
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

    /// Cycles through the pastel highlight palette — the same one used for
    /// tags and statuses — instead of saturated system colors.
    private func speakerPastel(for speaker: Transcript.Speaker) -> Color {
        let palette: [Color] = [DS.Color.mint, DS.Color.lavender, DS.Color.sky]
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
        if isActive(segment) { return DS.Color.sky.opacity(0.6) }
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

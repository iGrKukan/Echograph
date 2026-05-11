import SwiftUI

struct HomeView: View {
    @Environment(RecordingStore.self) private var store
    @Environment(TranscriptionService.self) private var transcription

    @State private var recorder = AudioRecorder()
    @State private var permissionStatus: MicrophonePermissionStatus = MicrophonePermission.current
    @State private var showPermissionAlert = false
    @State private var showRecordingError = false
    @State private var recordingErrorMessage = ""
    @State private var searchQuery = ""
    @State private var didConsumePendingIntent = false
    @State private var showingSettings = false
    @State private var showingImporter = false
    @State private var importErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                content

                VStack(spacing: 12) {
                    if isRecording {
                        recordingIndicator
                    }
                    RecordButton(isRecording: isRecording) {
                        Task { await toggleRecording() }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isRecording)
                .padding(.bottom, 32)
            }
            .navigationTitle("Echograph")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("importButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityIdentifier("settingsButton")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleImport(result) }
            }
            .alert("Import failed", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "")
            }
        }
        .alert("Microphone access needed", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Echograph needs access to your microphone to record voice notes. Audio stays on your device.")
        }
        .alert("Couldn't start recording", isPresented: $showRecordingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recordingErrorMessage)
        }
        .task { consumePendingIntentIfNeeded() }
    }

    private func handleImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let recording = try await AudioFileImporter.import(from: url)
                store.add(recording)
            } catch {
                importErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func consumePendingIntentIfNeeded() {
        guard !didConsumePendingIntent else { return }
        didConsumePendingIntent = true
        if PendingIntent.shared.shouldStartRecordingOnLaunch {
            PendingIntent.shared.shouldStartRecordingOnLaunch = false
            Task { await startRecording() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.recordings.isEmpty {
            ContentUnavailableView(
                "No recordings yet",
                systemImage: "waveform",
                description: Text("Tap the record button to capture your first voice note. Audio stays on your device.")
            )
        } else if filteredRecordings.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
        } else {
            List {
                ForEach(filteredRecordings) { recording in
                    NavigationLink {
                        RecordingDetailView(recordingID: recording.id) {
                            store.delete(recording)
                        }
                    } label: {
                        RecordingRow(recording: recording, query: searchQuery)
                    }
                    .accessibilityIdentifier("recordingRow_\(recording.id.uuidString)")
                }
                .onDelete { indexSet in
                    indexSet.map { filteredRecordings[$0] }.forEach(store.delete)
                }
            }
            .listStyle(.plain)
            .safeAreaPadding(.bottom, 140)
            .searchable(text: $searchQuery, prompt: Text("Search recordings or transcripts"))
        }
    }

    private var filteredRecordings: [Recording] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.recordings }
        // Strip leading "#" so users can search tags as "#interview" or "interview".
        let needle = trimmed.lowercased().replacingOccurrences(of: "#", with: "")
        return store.recordings.filter { recording in
            if recording.title.lowercased().contains(needle) { return true }
            if recording.tags.contains(where: { $0.lowercased().contains(needle) }) { return true }
            if let transcript = recording.transcript {
                return transcript.fullText.lowercased().contains(needle)
            }
            return false
        }
    }

    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            if case .interrupted = recorder.state {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
            } else {
                BlinkingDot()
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(format(time: recorder.elapsed))
                    .monospacedDigit()
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())
                if case .interrupted(let reason, _) = recorder.state {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .transition(.scale.combined(with: .opacity))
    }

    private var isRecording: Bool {
        switch recorder.state {
        case .recording, .interrupted: return true
        default: return false
        }
    }

    private func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        switch MicrophonePermission.current {
        case .granted:
            beginRecording()
        case .undetermined:
            let granted = await MicrophonePermission.request()
            permissionStatus = granted ? .granted : .denied
            if granted { beginRecording() }
        case .denied:
            showPermissionAlert = true
        }
    }

    private func beginRecording() {
        do {
            _ = try recorder.start()
        } catch {
            recordingErrorMessage = (error as NSError).localizedDescription
            showRecordingError = true
        }
    }

    private func stopRecording() async {
        let elapsed = recorder.elapsed
        guard let url = recorder.stop() else { return }
        let recording = Recording(
            title: defaultTitle(for: .now),
            duration: elapsed,
            filename: url.lastPathComponent
        )
        store.add(recording)
    }

    private func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
}

private struct BlinkingDot: View {
    @State private var visible = true

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .opacity(visible ? 1 : 0.3)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                    visible.toggle()
                }
            }
    }
}

private struct RecordingRow: View {
    let recording: Recording
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.body)
                .fontWeight(.medium)
            HStack(spacing: 8) {
                Text(recording.createdAt.formatted(.relative(presentation: .named)))
                Text("·")
                Text(durationLabel)
                if recording.transcript != nil {
                    Text("·")
                    Image(systemName: "text.bubble.fill")
                        .imageScale(.small)
                }
                if recording.speakerCount > 1 {
                    Text("·")
                    Text("\(recording.speakerCount) speakers")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !recording.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(recording.tags.prefix(4), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(.tint.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.top, 2)
            }

            if let snippet = matchingSnippet {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private var matchingSnippet: String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let transcript = recording.transcript else { return nil }
        let text = transcript.fullText
        guard let range = text.range(of: trimmed, options: .caseInsensitive) else { return nil }
        let startOffset = max(0, text.distance(from: text.startIndex, to: range.lowerBound) - 30)
        let start = text.index(text.startIndex, offsetBy: startOffset)
        let snippet = String(text[start...]).prefix(140)
        return "…" + snippet
    }

    private var durationLabel: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: recording.duration) ?? ""
    }
}

#Preview {
    HomeView()
}

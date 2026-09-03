import SwiftUI

struct AskSheet: View {
    let recording: Recording
    /// Pre-fills the input — used by the quick "Ask about this recording"
    /// bar pinned to the bottom of `RecordingDetailView`, which opens this
    /// sheet with whatever the user already typed there.
    var initialQuestion: String = ""

    @Environment(SummaryService.self) private var summary
    @Environment(\.dismiss) private var dismiss

    @State private var question: String = ""
    @State private var history: [QA] = []
    @State private var isAsking = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if history.isEmpty && !isAsking {
                    ContentUnavailableView {
                        Label("Ask anything", systemImage: "bubble.left.and.text.bubble.right")
                    } description: {
                        Text("Ask a question about “\(recording.title)”. AI answers using only the transcript, on-device.")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(history) { qa in
                                qaBubble(qa)
                            }
                            if isAsking {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Thinking…")
                                        .font(DS.Typography.secondary)
                                        .foregroundStyle(DS.Color.textSecondary)
                                }
                                .padding(.horizontal, DS.Spacing.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }

                Hairline()

                inputBar
            }
            .background(DS.Color.background)
            .navigationTitle("Ask AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                if question.isEmpty { question = initialQuestion }
                focused = true
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about this recording…", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .padding(10)
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.field))
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { send() }

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(canSend ? DS.Color.accent : DS.Color.textTertiary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, DS.Spacing.horizontal)
        .padding(.vertical, 12)
    }

    private var canSend: Bool {
        !isAsking && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let transcript = recording.transcript else { return }
        question = ""
        isAsking = true
        Task {
            do {
                let answer = try await summary.ask(q, about: transcript)
                history.append(QA(question: q, answer: answer))
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isAsking = false
        }
    }

    @ViewBuilder
    private func qaBubble(_ qa: QA) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(DS.Color.textSecondary)
                Text(qa.question)
                    .font(DS.Typography.body.weight(.medium))
                    .foregroundStyle(DS.Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(DS.Color.accent)
                Text(qa.answer)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(DS.Color.lavender.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, DS.Spacing.horizontal)
    }

    struct QA: Identifiable, Hashable {
        let id = UUID()
        let question: String
        let answer: String
    }
}

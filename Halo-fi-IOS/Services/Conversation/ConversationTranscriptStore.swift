//
//  ConversationTranscriptStore.swift
//  Halo-fi-IOS
//
//  Append-only event store that derives renderable TranscriptEntry objects.
//  Key responsibility: Coordinator emits events → Store decides how they render.
//
//  Handles:
//  - Merging streaming deltas into single entries
//  - Converting events to renderable entries
//  - Suppressing noisy events in privacy mode (future)
//

import Foundation

@Observable
@MainActor
final class ConversationTranscriptStore {
    // MARK: - Published State

    /// Raw events (source of truth)
    private(set) var events: [ConversationEvent] = []

    /// Derived entries for UI rendering
    private(set) var entries: [TranscriptEntry] = []

    // MARK: - Feedback Callbacks

    /// Called when agent starts typing (first delta of a new response)
    var onAgentTypingStarted: (() -> Void)?

    /// Called when agent message is complete
    var onAgentMessageComplete: (() -> Void)?

    // MARK: - Streaming State

    /// Currently streaming agent entry (if any)
    private var streamingAgentEntryId: UUID?
    private var streamingAgentText: String = ""

    /// Currently streaming user speech entry (if any)
    private var streamingUserEntryId: UUID?
    private var streamingUserText: String = ""

    /// Draft entry for live transcription (ElevenLabs STT)
    private var draftEntryId: UUID?
    private var draftText: String = ""

    /// Text from STT segments the server already committed this turn.
    /// Scribe v2 rolls to a new segment mid-speech (~20-25s VAD/buffer
    /// commit) whose partials contain ONLY the new segment's words — before
    /// this existed, each rollover wiped the screen and tap-send delivered
    /// just the last segment.
    private var committedText: String = ""

    /// committedText + current segment draft — what renders and what sends.
    private var fullDraftText: String {
        committedText.isEmpty
            ? draftText
            : (draftText.isEmpty ? committedText : "\(committedText) \(draftText)")
    }

    // MARK: - Public Methods

    /// Append a new event and update entries
    func append(_ event: ConversationEvent) {
        events.append(event)
        processEvent(event)
    }

    /// Reset all state (e.g., on new session)
    func reset() {
        events.removeAll()
        entries.removeAll()
        streamingAgentEntryId = nil
        streamingAgentText = ""
        streamingUserEntryId = nil
        streamingUserText = ""
        draftEntryId = nil
        draftText = ""
        committedText = ""
    }

    // MARK: - Draft Management (ElevenLabs STT)

    /// Update draft with new transcription text. The incoming text replaces
    /// only the CURRENT SEGMENT's portion (ElevenLabs partials revise the
    /// whole segment); text from previously committed segments is preserved
    /// in front of it. Never clear anything on a segment rollover.
    func updateDraft(_ text: String) {
        draftText = text
        renderDraft()
    }

    /// The server committed the current segment (committed_transcript).
    /// Fold its final text into committedText and reset the segment draft —
    /// the next partial will contain only the NEW segment's words.
    func commitSegment(_ text: String) {
        let segment = text.trimmingCharacters(in: .whitespaces)
        if !segment.isEmpty {
            committedText = committedText.isEmpty
                ? segment
                : "\(committedText) \(segment)"
        }
        draftText = ""
        renderDraft()
    }

    private func renderDraft() {
        let display = fullDraftText
        if let existingId = draftEntryId,
           let index = entries.firstIndex(where: { $0.id == existingId }) {
            // Update existing draft entry
            entries[index].text = display
        } else if !display.isEmpty {
            // Create new draft entry
            let id = UUID()
            draftEntryId = id
            entries.append(TranscriptEntry(
                id: id,
                speaker: .userDraft,
                text: display,
                timestamp: Date(),
                isStreaming: true
            ))
        }
    }

    /// Finalize draft into a permanent user message
    /// Returns the finalized text (for sending to agent) — ALL committed
    /// segments plus the live remainder, not just the last segment.
    @discardableResult
    func finalizeDraft() -> String? {
        guard let id = draftEntryId,
              let index = entries.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let finalText = fullDraftText

        // Skip if empty or whitespace-only
        guard !finalText.trimmingCharacters(in: .whitespaces).isEmpty else {
            discardDraft()
            return nil
        }

        // Convert draft to final user entry
        entries[index] = TranscriptEntry(
            id: id,
            speaker: .user,
            text: finalText,
            timestamp: entries[index].timestamp,
            isStreaming: false
        )

        // Clear draft state
        draftEntryId = nil
        draftText = ""
        committedText = ""

        return finalText
    }

    /// Discard draft without sending (user cancelled or empty)
    func discardDraft() {
        guard let id = draftEntryId else { return }

        // Remove draft entry from entries
        entries.removeAll { $0.id == id }

        // Clear draft state
        draftEntryId = nil
        draftText = ""
        committedText = ""
    }

    // MARK: - Event Processing

    private func processEvent(_ event: ConversationEvent) {
        switch event {
        // User text (final, complete)
        case .userText(let id, let text, let timestamp):
            entries.append(.user(text, id: id, timestamp: timestamp))

        // User speech delta (streaming)
        case .userSpeechDelta(let id, let delta, let timestamp):
            handleUserSpeechDelta(id: id, delta: delta, timestamp: timestamp)

        // User speech final (complete)
        case .userSpeechFinal(let id, let text, let timestamp):
            handleUserSpeechFinal(id: id, text: text, timestamp: timestamp)

        // Agent text delta (streaming)
        case .agentTextDelta(let id, let delta, let timestamp):
            handleAgentTextDelta(id: id, delta: delta, timestamp: timestamp)

        // Agent text final (complete)
        case .agentTextFinal(let id, let text, let timestamp):
            handleAgentTextFinal(id: id, text: text, timestamp: timestamp)

        // Tool events (currently collapsed into system messages)
        case .toolCallStarted(let id, let name, let timestamp):
            entries.append(.system("Checking \(name)...", id: id, timestamp: timestamp))

        case .toolCallFinished(let id, _, let summary, _):
            // Update the existing tool entry or add new one
            if let index = entries.firstIndex(where: { $0.id == id }) {
                entries[index].text = summary ?? "Done"
                entries[index].isStreaming = false
            }

        // System status
        case .systemStatus(let id, let message, let timestamp):
            entries.append(.system(message, id: id, timestamp: timestamp))

        // Error
        case .error(let id, let message, let timestamp):
            entries.append(.system("Error: \(message)", id: id, timestamp: timestamp))
        }
    }

    // MARK: - Streaming Merge Logic

    /// Handle user speech delta - merge into single streaming entry
    private func handleUserSpeechDelta(id: UUID, delta: String, timestamp: Date) {
        if streamingUserEntryId == id {
            // Append to existing streaming entry
            streamingUserText += delta
            if let index = entries.firstIndex(where: { $0.id == id }) {
                entries[index].text = streamingUserText
            }
        } else {
            // Start new streaming entry
            streamingUserEntryId = id
            streamingUserText = delta
            entries.append(TranscriptEntry(
                id: id,
                speaker: .user,
                text: delta,
                timestamp: timestamp,
                isStreaming: true
            ))
        }
    }

    /// Handle user speech final - finalize the streaming entry
    private func handleUserSpeechFinal(id: UUID, text: String, timestamp: Date) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            // Update existing entry with final text
            entries[index].text = text
            entries[index].isStreaming = false
        } else {
            // No streaming entry exists, create final entry
            entries.append(.user(text, id: id, timestamp: timestamp))
        }

        // Clear streaming state
        streamingUserEntryId = nil
        streamingUserText = ""
    }

    /// Handle agent text delta - merge into single streaming entry
    private func handleAgentTextDelta(id: UUID, delta: String, timestamp: Date) {
        if streamingAgentEntryId == id {
            // Append to existing streaming entry
            streamingAgentText += delta
            if let index = entries.firstIndex(where: { $0.id == id }) {
                entries[index].text = streamingAgentText
            }
        } else {
            // Start new streaming entry
            streamingAgentEntryId = id
            streamingAgentText = delta
            entries.append(TranscriptEntry(
                id: id,
                speaker: .agent,
                text: delta,
                timestamp: timestamp,
                isStreaming: true
            ))

            // Trigger typing feedback (only once per response)
            onAgentTypingStarted?()
        }
    }

    /// Handle agent text final - finalize the streaming entry
    private func handleAgentTextFinal(id: UUID, text: String, timestamp: Date) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            // Update existing entry with final text
            entries[index].text = text
            entries[index].isStreaming = false
        } else {
            // No streaming entry exists - create final entry directly
            entries.append(.agent(text, id: id, timestamp: timestamp))
        }

        // Clear streaming state
        streamingAgentEntryId = nil
        streamingAgentText = ""

        // Trigger message complete feedback
        onAgentMessageComplete?()
    }
}

// MARK: - Convenience Properties

extension ConversationTranscriptStore {
    /// Whether there's currently a streaming agent response
    var hasStreamingAgentEntry: Bool {
        streamingAgentEntryId != nil
    }

    /// Whether there's currently streaming user speech
    var hasStreamingUserEntry: Bool {
        streamingUserEntryId != nil
    }

    /// Whether there's currently a draft entry (live transcription)
    var hasDraftEntry: Bool {
        draftEntryId != nil
    }

    /// Current draft text (if any) — committed segments + live remainder
    var currentDraftText: String? {
        draftEntryId != nil ? fullDraftText : nil
    }

    /// The most recent entry (for scrolling to bottom)
    var lastEntry: TranscriptEntry? {
        entries.last
    }

    /// Number of entries
    var entryCount: Int {
        entries.count
    }
}

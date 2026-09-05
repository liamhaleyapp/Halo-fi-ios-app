//
//  PreviousConversationsView.swift
//  Halo-fi-IOS
//
//  Behind the Agent tab's three-dots menu: saved sessions, newest first.
//  Open one to read it; "Continue this conversation" brings it back into
//  the thread. Swipe or the rotor deletes.
//

import SwiftUI

struct PreviousConversationsView: View {
    let store: ConversationTranscriptStore
    let onResume: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [ConversationSession] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Text(isLoading
                         ? "Loading your conversations…"
                         : "No previous conversations yet. Each time you open the app, a fresh conversation starts and the last one is saved here.")
                        .foregroundColor(.haloTextSecondary)
                }
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session) {
                            store.resume(session)
                            onResume()
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title).font(.body.weight(.semibold)).lineLimit(2)
                            Text("\(Self.spoken(session.updatedAt)) · \(VoiceOverFormatter.count(session.entries.count, singular: "message", plural: "messages"))")
                                .font(.caption).foregroundColor(.haloTextSecondary)
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens the conversation. You can continue it from there.")
                    .accessibilityAction(named: "Delete") { delete(session) }
                }
                .onDelete { offsets in offsets.map { sessions[$0] }.forEach(delete) }
            }
            // Short title: "Previous conversations" broke across two lines
            // with a hyphen at larger text sizes.
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // An icon, not a word: "Close"/"Cancel" truncated to
                    // "C…" at accessibility text sizes.
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close")
                    .accessibilityHint("Goes back to the conversation.")
                }
            }
            .accessibilityAction(.escape) { dismiss() }
            .task {
                // Cache first so the list is never blank, then the server.
                sessions = store.previousSessions()
                sessions = await store.refreshPreviousSessions()
                isLoading = false
            }
        }
    }

    private func delete(_ session: ConversationSession) {
        store.deleteSession(id: session.id)
        sessions.removeAll { $0.id == session.id }
        UIAccessibility.post(notification: .announcement, argument: "Deleted.")
    }

    static func spoken(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f.string(from: date)
    }
}

struct SessionDetailView: View {
    let session: ConversationSession
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TranscriptView(entries: session.entries, onCopyEntry: nil, isProcessing: false)
            Button(action: onContinue) {
                Label("Continue this conversation", systemImage: "arrow.uturn.forward")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .padding(16)
            .accessibilityHint("Loads these messages into the Agent tab so you can keep going.")
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

//
//  TranscriptView.swift
//  Halo-fi-IOS
//
//  Scrollable transcript view displaying conversation entries.
//  Features:
//  - Auto-scroll to bottom on new messages
//  - "Jump to latest" button when scrolled up
//  - Accessible navigation through entries
//

import SwiftUI

struct TranscriptView: View {
    let entries: [TranscriptEntry]
    let onCopyEntry: ((TranscriptEntry) -> Void)?

    @State private var isAtBottom = true
    @State private var showJumpToLatest = false

    init(entries: [TranscriptEntry], onCopyEntry: ((TranscriptEntry) -> Void)? = nil) {
        self.entries = entries
        self.onCopyEntry = onCopyEntry
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Transcript scroll view
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(entries) { entry in
                                TranscriptBlock(entry: entry)
                                    .id(entry.id)
                                    .onTapGesture(count: 2) {
                                        onCopyEntry?(entry)
                                    }
                            }

                            // Bottom anchor for scrolling
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 80) // Space for jump button
                    }
                    .onChange(of: entries.count) { oldCount, newCount in
                        // Auto-scroll to bottom on new entries if already at bottom
                        if isAtBottom && newCount > oldCount {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        } else if newCount > oldCount {
                            showJumpToLatest = true
                        }
                    }
                    .onChange(of: entries.last?.text) { _, _ in
                        // Auto-scroll on streaming updates if at bottom
                        if isAtBottom {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        // Scroll to bottom on appear
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    // Track scroll position
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { _ in
                                // User is scrolling, assume they moved away from bottom
                                isAtBottom = false
                                showJumpToLatest = !entries.isEmpty
                            }
                    )
                    // Jump to latest button action
                    .overlay(alignment: .bottom) {
                        if showJumpToLatest && !entries.isEmpty {
                            jumpToLatestButton {
                                withAnimation {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                    isAtBottom = true
                                    showJumpToLatest = false
                                }
                            }
                            .padding(.bottom, 16)
                        }
                    }
                }

                // Empty state
                if entries.isEmpty {
                    emptyState
                }
            }
        }
        .accessibilityLabel("Conversation transcript")
        .accessibilityHint("Swipe up or down to navigate through messages")
    }

    // MARK: - Subviews

    @ViewBuilder
    private func jumpToLatestButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down")
                    .font(.caption.weight(.semibold))

                Text("Jump to latest")
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.blue)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .accessibilityLabel("Jump to latest message")
        .accessibilityHint("Double tap to scroll to the most recent message")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text("Start a conversation")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Tap the microphone or type to talk with Halo")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No messages yet. Tap the microphone or type to start a conversation with Halo.")
    }
}

// MARK: - Preview

#Preview {
    TranscriptView(entries: [
        .user("What's my checking account balance?"),
        .agent("Your checking account balance is $1,234.56. Would you like me to show recent transactions?"),
        .user("Yes, show me the last 5 transactions"),
        .system("Checking transactions..."),
        .agent("Here are your last 5 transactions:\n1. Grocery Store - $45.23\n2. Gas Station - $35.00\n3. Restaurant - $28.50\n4. Online Shopping - $89.99\n5. Coffee Shop - $5.75")
    ])
}

#Preview("Empty") {
    TranscriptView(entries: [])
}

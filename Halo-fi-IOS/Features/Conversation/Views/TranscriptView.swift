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
    var isProcessing: Bool = false

    @State private var isAtBottom = true

    init(entries: [TranscriptEntry], onCopyEntry: ((TranscriptEntry) -> Void)? = nil, isProcessing: Bool = false) {
        self.entries = entries
        self.onCopyEntry = onCopyEntry
        self.isProcessing = isProcessing
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

                            // Typing indicator when processing
                            if isProcessing {
                                TypingIndicator()
                                    .id("typing")
                            }

                            // Bottom anchor for scrolling and position tracking
                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: BottomAnchorPreferenceKey.self,
                                        value: geo.frame(in: .named("transcriptScroll")).minY
                                    )
                            }
                            .frame(height: 1)
                            .id("bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 80) // Space for jump button
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .coordinateSpace(name: "transcriptScroll")
                    .onChange(of: entries.count) { oldCount, newCount in
                        // Auto-scroll to bottom on new entries if already at bottom
                        if isAtBottom && newCount > oldCount {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
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
                    .onChange(of: isProcessing) { _, newValue in
                        // Scroll to typing indicator when it appears
                        if newValue && isAtBottom {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("typing", anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        // Scroll to bottom on appear
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    .onPreferenceChange(BottomAnchorPreferenceKey.self) { bottomY in
                        let viewportHeight = geometry.size.height
                        let threshold: CGFloat = 20
                        let newIsAtBottom = bottomY <= viewportHeight + threshold

                        // Only update if changed to avoid view churn
                        if newIsAtBottom != isAtBottom {
                            isAtBottom = newIsAtBottom
                        }
                    }
                    // Jump to latest button
                    .overlay(alignment: .bottom) {
                        if !isAtBottom && !entries.isEmpty {
                            jumpToLatestButton {
                                withAnimation {
                                    proxy.scrollTo("bottom", anchor: .bottom)
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

#Preview("Processing") {
    TranscriptView(
        entries: [.user("What's my balance?")],
        isProcessing: true
    )
}

// MARK: - Preference Key

private struct BottomAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.5)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray5))
        .cornerRadius(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { animating = true }
        .accessibilityLabel("Halo is typing")
    }
}

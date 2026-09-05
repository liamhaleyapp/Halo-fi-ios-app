//
//  ProfileQuestionsView.swift
//  Halo-fi-IOS
//
//  One question per screen (GOV.UK pattern), driven by ProfileQuestions.v1.
//
//  Accessibility contract:
//  - The question is the heading AND the label; VoiceOver focus lands on it
//    when the screen appears and after every async result.
//  - Every option is a ≥56 pt full-width button; the escape hatch ("Skip
//    for now" / "I'm not sure") is always present except on the promise.
//  - Errors are spoken and focused, never colour-only.
//  - Explainer cards are sheets with the Escape gesture wired.
//  - Each answer is PATCHed to /users/me the moment it is chosen; the
//    server is the source of truth, so leaving mid-way loses nothing.
//

import SwiftUI

struct ProfileQuestionsView: View {
    @Environment(UserManager.self) private var userManager

    let questions: [ProfileQuestionSpec]
    /// Called after the last visible question is answered or skipped.
    let onComplete: () -> Void
    /// Optional back action for the first question (nil hides Back there).
    let onBack: (() -> Void)?
    /// Onboarding shows the step header above; Settings uses a nav title.
    let embeddedInOnboarding: Bool
    /// Settings edits one question on its own: its `showIf` must not hide
    /// it (the condition refers to OTHER questions' answers).
    let ignoreVisibility: Bool
    /// When set, answers are NOT sent to the server here; each chosen
    /// patch is handed to this callback and the owner saves (or discards)
    /// them. The questionnaire uses it for "Save / Don't save" on exit.
    let onAnswer: ((BenefitsProfilePatch) -> Void)?

    @State private var answers: [String: String] = [:]
    /// Stored answers are read in onAppear, AFTER the first render. Until
    /// then a follow-up question (its showIf reads other answers) looks
    /// irrelevant, and the "nothing to ask" branch used to fire
    /// onComplete on that first pass — a white flash and an instant pop
    /// (Liam, 2026-09-05). Nothing is concluded before seeding.
    @State private var seeded = false
    @State private var index: Int = 0
    @State private var pendingOption: ProfileOption?
    @State private var showingExplainer = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private enum Focus: Hashable {
        case question
        case error
    }
    @AccessibilityFocusState private var focus: Focus?

    init(
        questions: [ProfileQuestionSpec] = ProfileQuestions.v1,
        embeddedInOnboarding: Bool = true,
        ignoreVisibility: Bool = false,
        onAnswer: ((BenefitsProfilePatch) -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        onComplete: @escaping () -> Void
    ) {
        self.questions = questions
        self.embeddedInOnboarding = embeddedInOnboarding
        self.ignoreVisibility = ignoreVisibility
        self.onAnswer = onAnswer
        self.onBack = onBack
        self.onComplete = onComplete
    }

    // MARK: - Derived

    private var visibleQuestions: [ProfileQuestionSpec] {
        ignoreVisibility ? questions : questions.filter { $0.showIf(answers) }
    }

    private var current: ProfileQuestionSpec? {
        let visible = visibleQuestions
        guard index < visible.count else { return nil }
        return visible[index]
    }

    private var isPromise: Bool { current?.field == "promise_accepted_at" }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let spec = current {
                    // No "question n of m": the total changes as branches
                    // resolve. A thin bar shows progress without a number.
                    if visibleQuestions.count > 1 {
                        ProgressView(value: Double(index + 1), total: Double(visibleQuestions.count))
                            .tint(.indigo)
                            .accessibilityHidden(true)
                    }

                    Text(spec.question)
                        .font(.title.weight(.bold))
                        .foregroundColor(.haloTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel(spec.question)
                        .accessibilityFocused($focus, equals: .question)

                    if let help = spec.helpText {
                        Text(help)
                            .font(.body)
                            .foregroundColor(.haloTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityFocused($focus, equals: .error)
                    }

                    VStack(spacing: 12) {
                        ForEach(spec.options) { option in
                            optionButton(option, spec: spec)
                        }
                    }
                    .padding(.top, 8)

                    if let skip = spec.skipTitle {
                        Button(skip) { advance(recording: "skipped", for: spec) }
                            .font(.body.weight(.medium))
                            .foregroundColor(.haloTextSecondary)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .accessibilityHint("Skips this question. You can answer it later in Settings, under Benefits profile.")
                            .disabled(isSaving)
                    }

                    if index > 0 || onBack != nil {
                        Button("Back") { goBack() }
                            .font(.body)
                            .foregroundColor(.haloTextSecondary)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .disabled(isSaving)
                    }
                } else if seeded {
                    // No visible question left — defensive; onComplete
                    // normally fires from advance().
                    ProgressView()
                        .onAppear { onComplete() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, embeddedInOnboarding ? 8 : 24)
            .padding(.bottom, 40)
        }
        .readableContentWidth()
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle(embeddedInOnboarding ? "" : (current?.shortTitle ?? "Benefits profile"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            seedFromProfile()
            focusQuestion()
        }
        .onChange(of: index) { _, _ in focusQuestion() }
        .sheet(isPresented: $showingExplainer, onDismiss: handleExplainerDismissed) {
            if let option = pendingOption, let explainer = option.explainer {
                ProfileExplainerSheet(explainer: explainer) {
                    showingExplainer = false
                }
            }
        }
    }

    // MARK: - Pieces

    private func optionButton(_ option: ProfileOption, spec: ProfileQuestionSpec) -> some View {
        let isSelected = answers[spec.id] == option.id
        return Button {
            choose(option, for: spec)
        } label: {
            HStack {
                Text(option.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .foregroundColor(isSelected ? .white : .haloTextPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(isSelected ? Color.blue : Color.haloSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.haloSeparator, lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel(option.title)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint(option.explainer == nil ? "Saves this answer and continues." : "Shows a short explanation, then continues.")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Actions

    private func seedFromProfile() {
        // Pre-select what the server already has so re-entering (Settings,
        // or a resumed onboarding) shows the current answer.
        // Seed from the WHOLE tree, not only the questions on screen: a
        // single question's showIf reads other questions' answers.
        let profile = userManager.benefitsProfile
        for spec in ProfileQuestions.v1 where answers[spec.id] == nil {
            if let stored = profile.answer(for: spec.field) {
                answers[spec.id] = stored
            }
        }
        seeded = true
    }

    private func focusQuestion() {
        // Defer one runloop so the new heading exists before focus moves.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focus = .question
        }
    }

    private func choose(_ option: ProfileOption, for spec: ProfileQuestionSpec) {
        errorMessage = nil
        Haptics.engine.play(.tapLight)
        if option.explainer != nil {
            pendingOption = option
            showingExplainer = true
            return
        }
        commit(option, for: spec)
    }

    private func handleExplainerDismissed() {
        guard let option = pendingOption, let spec = current else { return }
        pendingOption = nil
        commit(option, for: spec)
    }

    private func commit(_ option: ProfileOption, for spec: ProfileQuestionSpec) {
        answers[spec.id] = option.id
        guard !option.patch.isEmpty else {
            advance(recording: option.id, for: spec)
            return
        }
        if let onAnswer {
            onAnswer(option.patch)
            advance(recording: option.id, for: spec)
            return
        }
        isSaving = true
        Task {
            do {
                try await userManager.updateBenefitsProfile(option.patch)
                isSaving = false
                advance(recording: option.id, for: spec)
            } catch {
                isSaving = false
                Haptics.error()
                errorMessage = "Couldn't save that answer. \(error.localizedDescription) Try again, or skip for now."
                UIAccessibility.post(notification: .announcement, argument: errorMessage ?? "")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .error }
            }
        }
    }

    private func advance(recording value: String, for spec: ProfileQuestionSpec) {
        answers[spec.id] = value
        errorMessage = nil
        let nextIndex = index + 1
        if nextIndex < visibleQuestions.count {
            index = nextIndex
        } else {
            Haptics.success()
            onComplete()
        }
    }

    private func goBack() {
        errorMessage = nil
        if index > 0 {
            index -= 1
        } else {
            onBack?()
        }
    }
}

// MARK: - Explainer sheet

struct ProfileExplainerSheet: View {
    let explainer: ProfileExplainer
    let onContinue: () -> Void

    @Environment(\.openURL) private var openURL
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(explainer.title)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.haloTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($titleFocused)

                    ForEach(Array(explainer.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.body)
                            .foregroundColor(.haloTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let title = explainer.linkTitle, let url = explainer.linkURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label(title, systemImage: "person.wave.2")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Opens the Social Security counselor finder in your browser.")
                    }

                    Button("Continue") { onContinue() }
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .readableContentWidth()
            .background(Color.haloBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onContinue() }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { titleFocused = true }
            }
            .accessibilityAction(.escape) { onContinue() }
        }
    }
}

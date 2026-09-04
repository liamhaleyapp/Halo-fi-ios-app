//
//  BenefitsQuestionnaireView.swift
//  Halo-fi-IOS
//
//  The benefits questionnaire, start to finish, in one flow:
//    1. Before you start — what HaloFi does and does not do (estimates
//       only, nothing is ever sent to Social Security, free human
//       counselor), in the style of the AI consent screen. Start records
//       the promise (promise_accepted_at).
//    2. The questions — one per screen, branching on earlier answers, no
//       "question n of m" counting (the count changes as branches resolve).
//    3. Your benefits profile — the summary the user can edit, with Done.
//  Reached from the Benefits tab (no lane yet) and from Settings → Benefits
//  profile → Redo the questionnaire.
//

import SwiftUI

struct BenefitsQuestionnaireView: View {
    @Environment(UserManager.self) private var userManager
    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss

    /// Called after Done on the summary (or Not now on the intro).
    let onFinished: () -> Void

    private enum Phase { case intro, questions, summary }
    @State private var phase: Phase = .intro
    @State private var isStarting = false
    @State private var startError: String?
    @State private var showingDetails = false
    @State private var showingLeave = false
    @State private var isSavingAnswers = false
    @State private var saveError: String?
    @State private var saveErrorThenSummary = true
    /// Answers collected during the questions; saved on completion or
    /// "Save answers", discarded on "Don't save".
    @State private var collected: BenefitsProfilePatch = .none
    @AccessibilityFocusState private var titleFocused: Bool

    private static let questions: [ProfileQuestionSpec] = ProfileQuestions.v1.filter { $0.field != "promise_accepted_at" }

    var body: some View {
        Group {
            switch phase {
            case .intro:
                intro
            case .questions:
                ProfileQuestionsView(
                    questions: Self.questions,
                    embeddedInOnboarding: false,
                    onAnswer: { patch in collected = collected.merging(patch) },
                    onBack: { phase = .intro },
                    onComplete: { Task { await saveCollected(thenShowSummary: true) } }
                )
                .navigationTitle("Benefits questionnaire")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { showingLeave = true } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Leave questionnaire")
                        .accessibilityHint("Asks whether to save the answers so far.")
                    }
                }
                .accessibilityAction(.escape) { showingLeave = true }
                .confirmationDialog("Leave the questionnaire?", isPresented: $showingLeave, titleVisibility: .visible) {
                    Button("Save answers so far") { Task { await saveCollected(thenShowSummary: false) } }
                    Button("Don't save", role: .destructive) { collected = .none; onFinished() }
                    Button("Keep going", role: .cancel) {}
                } message: {
                    Text(collected.isEmpty ? "Nothing has been saved yet." : "Your answers so far can be saved now and finished later in Settings.")
                }
                .overlay { if isSavingAnswers { ProgressView("Saving…").padding().background(.thinMaterial).cornerRadius(12) } }
                .alert("Couldn't save your answers", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                    Button("Try again") { Task { await saveCollected(thenShowSummary: saveErrorThenSummary) } }
                    Button("Leave without saving", role: .destructive) { collected = .none; onFinished() }
                    Button("Keep going", role: .cancel) {}
                } message: {
                    Text(saveError ?? "")
                }
            case .summary:
                BenefitsProfileView(onDone: {
                    Task {
                        await userManager.refreshCapabilities()
                        await dataManager.refresh()
                        onFinished()
                    }
                })
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(phase == .questions)
    }

    private func saveCollected(thenShowSummary: Bool) async {
        isSavingAnswers = true
        defer { isSavingAnswers = false }
        if !collected.isEmpty {
            do {
                try await userManager.updateBenefitsProfile(collected)
                collected = .none
            } catch {
                // Keep `collected` so Try again re-sends the same answers.
                saveErrorThenSummary = thenShowSummary
                saveError = error.localizedDescription
                UIAccessibility.post(notification: .announcement, argument: "Couldn't save your answers. \(error.localizedDescription)")
                return
            }
        }
        await userManager.refreshCapabilities()
        dataManager.markStale()
        if thenShowSummary {
            phase = .summary
        } else {
            await dataManager.refresh()
            onFinished()
        }
    }

    // MARK: - 1. Before you start

    private var intro: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("HaloFiLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .padding(.top, 16)
                    .accessibilityHidden(true)

                Text("Benefits questionnaire")
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(.haloTextPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)

                // One short block for VoiceOver: what it is, the two rules
                // that matter, and that everything can change later.
                VStack(alignment: .leading, spacing: 10) {
                    Text("A few one-tap questions about your Social Security benefits. They decide what HaloFi shows you.")
                        .foregroundColor(.haloTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Everything is an estimate; Social Security decides. Nothing is ever sent to them. You can change any answer later.")
                        .foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .accessibilityElement(children: .combine)

                if showingDetails {
                    VStack(alignment: .leading, spacing: 14) {
                        bullet("chart.bar.doc.horizontal", "Estimates only", "Every benefits number HaloFi shows is an estimate for education, not a determination and not legal advice. Social Security makes every actual decision.")
                        bullet("lock.shield", "Nothing goes to Social Security", "You report and hand in your own paperwork. HaloFi prepares, reminds and keeps the log.")
                        bullet("person.wave.2", "A free human when it matters", "Deeming, trusts, overpayments: HaloFi points you to a free Work Incentives counselor instead of guessing.")
                        bullet("pencil", "Change anything later", "Your answers live in Settings, Benefits profile. Skip any question you're unsure about.")
                    }
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showingDetails.toggle() }
                } label: {
                    Text(showingDetails ? "Hide details" : "More about this")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .underline()
                        .frame(minHeight: 44)
                }
                .accessibilityLabel(showingDetails ? "Hide details" : "More about this questionnaire")

                if let startError {
                    Text(startError)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 12) {
                    Button(action: start) {
                        HStack {
                            if isStarting { ProgressView().tint(.white) }
                            Text("I understand, start")
                                .font(.headline.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(16)
                    }
                    .disabled(isStarting)
                    .accessibilityHint("Records that you understand HaloFi gives estimates, then asks the first question.")

                    Button { onFinished() } label: {
                        Text("Not now")
                            .font(.subheadline)
                            .foregroundColor(.haloTextSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(isStarting)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle("Before you start")
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { titleFocused = true }
        }
    }

    private func bullet(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.indigo)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundColor(.haloTextPrimary)
                Text(body).font(.subheadline).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func start() {
        isStarting = true
        startError = nil
        Task {
            do {
                try await userManager.updateBenefitsProfile(BenefitsProfilePatch(promiseAcceptedAt: Date()))
                isStarting = false
                Haptics.engine.play(.tapLight)
                phase = .questions
            } catch {
                isStarting = false
                startError = "Couldn't save that. \(error.localizedDescription)"
                UIAccessibility.post(notification: .announcement, argument: startError ?? "")
            }
        }
    }
}

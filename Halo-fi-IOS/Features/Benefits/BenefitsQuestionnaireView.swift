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
                    onBack: { phase = .intro },
                    onComplete: {
                        Task {
                            await userManager.refreshCapabilities()
                            dataManager.markStale()
                            phase = .summary
                        }
                    }
                )
                .navigationTitle("Benefits questionnaire")
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

    // MARK: - 1. Before you start

    private var intro: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("HaloFiLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                Text("Benefits questionnaire")
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(.haloTextPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)

                VStack(alignment: .leading, spacing: 16) {
                    Text("A few questions about your Social Security benefits. Your answers decide which screens, reminders and estimates HaloFi shows you. Each one is a single tap, and you can skip any of them.")
                        .foregroundColor(.haloTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    bullet("chart.bar.doc.horizontal", "Estimates only", "Every number HaloFi shows about your benefits is an estimate for education. Social Security makes every actual decision, and HaloFi is not a substitute for their determinations or for legal advice.")
                    bullet("lock.shield", "Nothing goes to Social Security", "HaloFi never sends anything to Social Security. You report and hand in your own paperwork; the app prepares, reminds and keeps the log.")
                    bullet("person.wave.2", "A free human when it matters", "For questions like deeming, trusts or overpayments, HaloFi points you to a free Work Incentives counselor instead of guessing.")
                    bullet("pencil", "Change anything later", "Your answers live in Settings, Benefits profile. Nothing here is permanent.")
                }
                .padding(.horizontal, 24)

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

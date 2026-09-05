//
//  BenefitsProfileView.swift
//  Halo-fi-IOS
//
//  Settings → Benefits profile, and the summary at the end of the
//  questionnaire. Shows what the user told us (only the answered
//  questions, each tappable to change), one button for whatever is still
//  unanswered, the statutory-blind verification state with the BPQY
//  walkthrough, and the state picker (Q8) that onboarding defers here.
//  It is a summary, not the eight-question list.
//
//  Every benefits screen ends with "Talk to a free benefits counselor"
//  (hard product rule 6).
//

import SwiftUI

struct BenefitsProfileView: View {
    @Environment(UserManager.self) private var userManager
    @Environment(\.openURL) private var openURL

    /// When set, this is the summary at the END of the questionnaire: a
    /// Done button appears and "Redo the questionnaire" is hidden.
    var onDone: (() -> Void)? = nil

    @State private var editing: ProfileQuestionSpec?
    @State private var finishingRemaining = false
    @State private var showingBPQY = false
    @State private var stateCode: String = ""
    @State private var stateSaveError: String?

    // MARK: - Derived

    private var profile: BenefitsProfile { userManager.benefitsProfile }
    private var caps: UserCapabilities { userManager.capabilities }

    /// Answers-so-far keyed by question id, the shape `showIf` reads.
    private var answersById: [String: String] {
        var out: [String: String] = [:]
        for spec in ProfileQuestions.v1 {
            if let stored = profile.answer(for: spec.field) { out[spec.id] = stored }
        }
        return out
    }

    /// Questions with a stored answer, one per field.
    private var answered: [ProfileQuestionSpec] {
        ProfileQuestions.settingsRows.filter { profile.answer(for: $0.field) != nil }
    }

    /// Questions still relevant (their `showIf` holds for the answers so
    /// far) and not answered yet — what "Answer N more" counts.
    private var remaining: [ProfileQuestionSpec] {
        let answers = answersById
        var seen = Set<String>()
        return ProfileQuestions.v1.filter { spec in
            guard spec.field != "promise_accepted_at" else { return false }
            guard profile.answer(for: spec.field) == nil else { return false }
            guard spec.showIf(answers) else { return false }
            return seen.insert(spec.field).inserted
        }
    }

    /// Every unanswered question, relevant or not. The question screen
    /// applies `showIf` itself against the live answers, so a branch that
    /// opens mid-way (SSI → who shares your household) is asked in the
    /// same pass instead of needing another "Answer N more".
    private var unansweredAll: [ProfileQuestionSpec] {
        ProfileQuestions.v1.filter { spec in
            spec.field != "promise_accepted_at" && profile.answer(for: spec.field) == nil
        }
    }

    private var laneTitle: String {
        switch caps.lane {
        case .ssi: return caps.showsSSDILane ? "SSI and SSDI" : "SSI"
        case .ssdi: return "SSDI"
        case .none: return caps.benefitsUnanswered ? "Not set up yet" : "No SSI or SSDI"
        }
    }

    private var laneIcon: String {
        switch caps.lane {
        case .ssi: return "checkmark.shield.fill"
        case .ssdi: return "briefcase.fill"
        case .none: return caps.benefitsUnanswered ? "questionmark.circle.fill" : "minus.circle.fill"
        }
    }

    private var laneTint: Color {
        switch caps.lane {
        case .ssi: return .green
        case .ssdi: return .blue
        case .none: return .gray
        }
    }

    private var overviewLine: String { Self.overviewLine(capabilities: caps, profile: profile) }

    /// One line that says what the answers add up to. Shared with the
    /// Benefits tab's "Your benefits profile" row.
    static func overviewLine(capabilities caps: UserCapabilities, profile: BenefitsProfile) -> String {
        switch caps.lane {
        case .ssi:
            var parts = [caps.showsSSDILane ? "SSI and SSDI" : "SSI"]
            parts.append(caps.blindStatus == "yes" ? "statutory blindness verified" : "Blind Work Expenses locked until verified")
            if let work = profile.workStatus {
                parts.append(work == "working" ? "working now" : work == "starting_soon" ? "starting work soon" : "not working right now")
            }
            return parts.joined(separator: ", ") + "."
        case .ssdi:
            var parts = ["SSDI", "work expenses count as IRWE"]
            if let work = profile.workStatus {
                parts.append(work == "working" ? "working now" : work == "starting_soon" ? "starting work soon" : "not working right now")
            }
            return parts.joined(separator: ", ") + "."
        case .none:
            return caps.benefitsUnanswered
                ? "A few one-tap questions decide what HaloFi shows you."
                : "No SSI or SSDI, so there is no Benefits tab. Change an answer and it comes back."
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            Section {
                laneCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if answered.isEmpty {
                if onDone == nil {
                    Section {
                        NavigationLink {
                            BenefitsQuestionnaireView(onFinished: { editing = nil })
                        } label: {
                            Label("Start the questionnaire", systemImage: "list.bullet.clipboard")
                                .font(.headline)
                                .frame(minHeight: 44)
                        }
                        .accessibilityHint("About a minute. One question per screen, every one skippable.")
                    } footer: {
                        Text("Nothing here is sent to Social Security.")
                    }
                }
            } else {
                Section {
                    ForEach(answered) { spec in
                        Button {
                            editing = spec
                        } label: {
                            answerRow(spec)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("What you told us")
                } footer: {
                    Text("Tap an answer to change it. Halo uses these to decide which screens and estimates to show. Nothing here is sent to Social Security.")
                }

                if !remaining.isEmpty {
                    Section {
                        Button {
                            finishingRemaining = true
                        } label: {
                            Label(remainingTitle, systemImage: "arrow.right.circle.fill")
                                .font(.headline)
                                .frame(minHeight: 44)
                        }
                        .accessibilityHint("Asks only the questions you have not answered yet.")
                    } footer: {
                        Text("Skipped earlier. Each one is a single tap.")
                    }
                }

                if onDone == nil {
                    Section {
                        NavigationLink {
                            BenefitsQuestionnaireView(onFinished: { editing = nil })
                        } label: {
                            Label("Redo the questionnaire", systemImage: "arrow.counterclockwise")
                                .frame(minHeight: 44)
                        }
                        .accessibilityHint("Walks through every question again, one per screen.")
                    }
                }
            }

            if caps.lane == .ssi || profile.blindStatus != nil {
                Section {
                    HStack {
                        Text("Statutory blindness")
                        Spacer()
                        Text(caps.blindStatusTitle)
                            .foregroundColor(.haloTextSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Statutory blindness. \(caps.blindStatusTitle)")

                    if caps.bweLocked {
                        Button {
                            showingBPQY = true
                        } label: {
                            Label("How to check with Social Security", systemImage: "doc.text.magnifyingglass")
                        }
                        .accessibilityHint("Explains how to get a Benefits Planning Query. Blind Work Expense features unlock once Social Security's record confirms statutory blindness.")
                    }
                } header: {
                    Text("Verification")
                } footer: {
                    if caps.bweLocked {
                        Text("Blind Work Expenses are locked until Social Security's record confirms statutory blindness. You can still log Impairment-Related Work Expenses.")
                    }
                }
            }

            Section {
                Picker("State", selection: $stateCode) {
                    Text("Not set").tag("")
                    ForEach(USStates.codes, id: \.self) { code in
                        Text(USStates.name(for: code)).tag(code)
                    }
                }
                .accessibilityHint("Used for state supplement notes and to prefill the counselor finder.")
                .onChange(of: stateCode) { _, newValue in
                    saveState(newValue)
                }
                if let err = stateSaveError {
                    Text(err).foregroundStyle(.red).font(.callout)
                }
            } header: {
                Text("Where you live")
            }

            Section {
                Button {
                    openURL(ProfileExplainer.wipaURL)
                } label: {
                    Label("Talk to a free benefits counselor", systemImage: "person.wave.2")
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Opens the Social Security counselor finder in your browser.")
            } footer: {
                Text("Estimate for education only — Social Security makes all actual decisions.")
            }

            if let onDone {
                Section {
                    Button(action: onDone) {
                        Text("Done")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityHint("Finishes the questionnaire and opens the Benefits tab built from these answers.")
                }
            }
        }
        .navigationTitle("Benefits profile")
        .navigationBarTitleDisplayMode(onDone == nil ? .large : .inline)
        .navigationBarBackButtonHidden(onDone != nil)
        .onAppear {
            stateCode = profile.stateCode ?? ""
            Task { await userManager.refreshCapabilities() }
        }
        .navigationDestination(item: $editing) { spec in
            ProfileQuestionsView(
                questions: [spec],
                embeddedInOnboarding: false,
                ignoreVisibility: true,
                onComplete: {
                    editing = nil
                    // The intended flow: changing one answer can open a
                    // follow-up ("Yes, I receive a payment" → "Which
                    // benefit?"). Ask it now rather than parking it behind
                    // "Answer 1 more question".
                    Task {
                        await userManager.refreshCapabilities()
                        let followUps = remaining
                        guard !followUps.isEmpty else { return }
                        UIAccessibility.post(
                            notification: .announcement,
                            argument: followUps.count == 1 ? "One more question." : "\(followUps.count) more questions."
                        )
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        finishingRemaining = true
                    }
                }
            )
        }
        .navigationDestination(isPresented: $finishingRemaining) {
            ProfileQuestionsView(
                questions: unansweredAll,
                embeddedInOnboarding: false,
                onComplete: {
                    finishingRemaining = false
                    Task { await userManager.refreshCapabilities() }
                }
            )
            .navigationTitle("A few more questions")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingBPQY) {
            ProfileExplainerSheet(explainer: .bpqyWalkthrough) { showingBPQY = false }
        }
    }

    // MARK: - Pieces

    private var remainingTitle: String {
        let n = remaining.count
        return n == 1 ? "Answer 1 more question" : "Answer \(n) more questions"
    }

    /// The tinted summary at the top: which lane, in words, plus one line
    /// of what that means. Read as a single header by VoiceOver.
    private var laneCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: laneIcon)
                .font(.title2.weight(.semibold))
                .foregroundColor(laneTint)
                .frame(width: 44, height: 44)
                .background(laneTint.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(onDone != nil ? "Here's your benefits profile" : "Your benefits")
                    .font(.subheadline)
                    .foregroundColor(.haloTextSecondary)
                Text(laneTitle)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.haloTextPrimary)
                Text(overviewLine)
                    .font(.subheadline)
                    .foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(laneTint.opacity(0.35), lineWidth: 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your benefits: \(laneTitle). \(overviewLine)")
        .accessibilityAddTraits(.isHeader)
    }

    /// One stored answer: the question as a small caption, the answer as
    /// the main line, a chevron because it opens the question to change it.
    private func answerRow(_ spec: ProfileQuestionSpec) -> some View {
        let answer = currentAnswerTitle(for: spec)
        return HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.shortTitle)
                    .font(.caption)
                    .foregroundColor(.haloTextSecondary)
                Text(answer)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.haloTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.haloTextTertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spec.shortTitle): \(answer)")
        .accessibilityHint("Changes this answer.")
        .accessibilityAddTraits(.isButton)
    }

    private func currentAnswerTitle(for spec: ProfileQuestionSpec) -> String {
        guard let stored = profile.answer(for: spec.field) else {
            return "Not answered"
        }
        return spec.options.first(where: { $0.id == stored })?.title ?? stored
    }

    private func saveState(_ code: String) {
        stateSaveError = nil
        guard code != (profile.stateCode ?? "") else { return }
        guard !code.isEmpty else { return }
        Task {
            do {
                try await userManager.updateBenefitsProfile(BenefitsProfilePatch(stateCode: code))
                Haptics.engine.play(.tapLight)
            } catch {
                stateSaveError = "Couldn't save your state. \(error.localizedDescription)"
                UIAccessibility.post(notification: .announcement, argument: stateSaveError ?? "")
            }
        }
    }
}

extension ProfileQuestionSpec: Hashable {
    static func == (lhs: ProfileQuestionSpec, rhs: ProfileQuestionSpec) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum USStates {
    static let codes: [String] = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL", "IN", "IA",
        "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM",
        "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA",
        "WV", "WI", "WY", "PR",
    ]

    private static let names: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
        "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois",
        "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
        "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
        "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon",
        "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
        "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia",
        "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming", "PR": "Puerto Rico",
    ]

    static func name(for code: String) -> String { names[code] ?? code }
}

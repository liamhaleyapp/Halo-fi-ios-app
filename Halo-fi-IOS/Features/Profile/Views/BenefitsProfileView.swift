//
//  BenefitsProfileView.swift
//  Halo-fi-IOS
//
//  Settings → Benefits profile. Edits the same answers as the onboarding
//  step (ProfileQuestions.v1), one question per screen, plus the state
//  picker (Q8) that onboarding defers here. The statutory-blind row shows
//  the verification state and the BPQY walkthrough.
//
//  Every benefits screen ends with "Talk to a free benefits counselor"
//  (hard product rule 6).
//

import SwiftUI

struct BenefitsProfileView: View {
    @Environment(UserManager.self) private var userManager
    @Environment(\.openURL) private var openURL

    @State private var editing: ProfileQuestionSpec?
    @State private var showingBPQY = false
    @State private var stateCode: String = ""
    @State private var stateSaveError: String?

    var body: some View {
        List {
            Section {
                ForEach(ProfileQuestions.settingsRows) { spec in
                    Button {
                        editing = spec
                    } label: {
                        row(spec)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Your answers")
            } footer: {
                Text("Halo uses these to decide which screens and estimates to show. Nothing here is sent to Social Security.")
            }

            Section {
                HStack {
                    Text("Statutory blindness")
                    Spacer()
                    Text(userManager.capabilities.blindStatusTitle)
                        .foregroundColor(.haloTextSecondary)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Statutory blindness. \(userManager.capabilities.blindStatusTitle)")

                if userManager.capabilities.bweLocked {
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
                if userManager.capabilities.bweLocked {
                    Text("Blind Work Expenses are locked until Social Security's record confirms statutory blindness. You can still log Impairment-Related Work Expenses.")
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
        }
        .navigationTitle("Benefits profile")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            stateCode = userManager.benefitsProfile.stateCode ?? ""
            Task { await userManager.refreshCapabilities() }
        }
        .navigationDestination(item: $editing) { spec in
            ProfileQuestionsView(
                questions: [spec],
                embeddedInOnboarding: false,
                onComplete: { editing = nil }
            )
        }
        .sheet(isPresented: $showingBPQY) {
            ProfileExplainerSheet(explainer: .bpqyWalkthrough) { showingBPQY = false }
        }
    }

    private func row(_ spec: ProfileQuestionSpec) -> some View {
        let answer = currentAnswerTitle(for: spec)
        return HStack {
            Text(spec.shortTitle)
                .foregroundColor(.haloTextPrimary)
            Spacer()
            Text(answer)
                .foregroundColor(.haloTextSecondary)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.haloTextTertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spec.shortTitle). \(answer)")
        .accessibilityHint("Opens the question so you can change your answer.")
        .accessibilityAddTraits(.isButton)
    }

    private func currentAnswerTitle(for spec: ProfileQuestionSpec) -> String {
        guard let stored = userManager.benefitsProfile.answer(for: spec.field) else {
            return "Not answered"
        }
        return spec.options.first(where: { $0.id == stored })?.title ?? stored
    }

    private func saveState(_ code: String) {
        stateSaveError = nil
        guard code != (userManager.benefitsProfile.stateCode ?? "") else { return }
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

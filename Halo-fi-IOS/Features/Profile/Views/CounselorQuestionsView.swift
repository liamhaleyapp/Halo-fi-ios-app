//
//  CounselorQuestionsView.swift
//  Halo-fi-IOS
//
//  Settings → Questions for my counselor. Every expense the user flagged
//  "Not sure this counts? Ask my counselor" in one list, with the WIPA
//  finder at the end (hard product rule 6).
//

import SwiftUI

struct CounselorQuestionsView: View {
    @Environment(\.openURL) private var openURL
    @State private var questions: [SSIManualDeduction] = []
    @State private var isLoading = true
    @State private var loadError: String?

    private let ssiService: SSIServiceProtocol = SSIService.shared

    var body: some View {
        List {
            Section {
                if isLoading {
                    ProgressView("Loading…")
                } else if let loadError {
                    Text(loadError).foregroundStyle(.red)
                } else if questions.isEmpty {
                    Text("Nothing flagged yet. When you log a work expense and tap \"Not sure this counts? Ask my counselor\", it shows up here so you can bring the list to your next call.")
                        .foregroundColor(.haloTextSecondary)
                } else {
                    ForEach(questions) { q in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(q.description).font(.body.weight(.semibold))
                            Text("\(VoiceOverFormatter.dollars(q.amountCents)) on \(q.occurredOn.prefix(10)). Logged as \(q.exclusionType.rawValue.uppercased()).")
                                .font(.callout)
                                .foregroundColor(.haloTextSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(q.description). \(VoiceOverFormatter.dollars(q.amountCents)). Logged as \(q.exclusionType.rawValue.uppercased()).")
                    }
                }
            } header: {
                Text("Ask a counselor whether these count")
            } footer: {
                Text("A Work Incentives counselor can tell you for sure. HaloFi gives estimates and education, not decisions.")
            }

            Section {
                Button {
                    InAppBrowser.open(ProfileExplainer.wipaURL)
                } label: {
                    Label("Talk to a free benefits counselor", systemImage: "person.wave.2")
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Opens the Social Security counselor finder inside the app. Close returns here.")
            }
        }
        .navigationTitle("Questions for my counselor")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            questions = try await ssiService.fetchCounselorQuestions()
        } catch {
            loadError = "Couldn't load your questions. \(error.localizedDescription)"
        }
    }
}

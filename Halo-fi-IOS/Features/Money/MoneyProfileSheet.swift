//
//  MoneyProfileSheet.swift
//  Halo-fi-IOS
//
//  "Finish setting up" (2026-09-05): the four money questions Halo used to
//  ask by voice before it would answer anything. Now a screen, offered once
//  after the first account is linked, and reachable again from the Agent
//  tab, Needs your attention, and Settings → Money profile. Every
//  question is skippable; each answer saves the moment it is chosen.
//

import SwiftUI

extension Notification.Name {
    /// Posted after a bank link or a manual account is saved.
    static let accountLinked = Notification.Name("AccountLinked")
}

enum MoneyProfilePrompt {
    private static let key = "moneyProfileOfferedAfterLink"
    /// The after-link offer happens once per install.
    static func shouldOfferAfterLink(remaining: Int) -> Bool {
        remaining > 0 && !UserDefaults.standard.bool(forKey: key)
    }
    static func markOffered() { UserDefaults.standard.set(true, forKey: key) }
}

struct MoneyProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Onboarding-style header above the questions; Settings uses the nav title.
    var showsIntro = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showsIntro {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Finish setting up")
                            .font(.haloTitle)
                            .foregroundColor(.haloTextPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Four quick questions. They help Halo tailor your budget and recognize rent. Skip any of them.")
                            .font(.subheadline)
                            .foregroundColor(.haloTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                ProfileQuestionsView(
                    questions: ProfileQuestions.money,
                    embeddedInOnboarding: showsIntro,
                    ignoreVisibility: !showsIntro,
                    onComplete: { dismiss() }
                )
            }
            .background(Color.haloBackground.ignoresSafeArea())
            .navigationTitle(showsIntro ? "" : "Money profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(showsIntro ? "Later" : "Done") { dismiss() }
                        .accessibilityHint("Closes this. You can answer any time from Settings, under Money profile.")
                }
            }
        }
        .accessibilityAction(.escape) { dismiss() }
    }
}

/// One row on the Agent tab while questions remain: the answers pay off
/// most in Halo's replies, so that is where the reminder lives.
struct MoneyProfilePromptCard: View {
    let remaining: Int
    let onOpen: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    HaloIconTile(icon: "person.text.rectangle.fill", tint: .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Finish setting up").font(.haloRowTitle).foregroundColor(.haloTextPrimary)
                        Text("\(remaining) quick question\(remaining == 1 ? "" : "s") help Halo tailor answers.")
                            .font(.subheadline).foregroundColor(.haloTextSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the questions.")
            Button(action: onNotNow) {
                Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundColor(.haloTextSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Not now")
            .accessibilityHint("Hides this until the next time you open the app.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .haloCard()
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityIdentifier("moneyProfilePrompt")
    }
}

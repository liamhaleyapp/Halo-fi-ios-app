//
//  FieldOfficeView.swift
//  Halo-fi-IOS
//
//  WP6 — Settings → My field office. "How does your office like to
//  receive these?" (portal · fax · mail · paper receipts) + free notes.
//  Guidance text on the Monthly package screen changes per channel.
//  HaloFi never transmits anything to SSA; this only changes the steps.
//

import SwiftUI

struct FieldOfficeChannel: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let icon: String

    static let all: [FieldOfficeChannel] = [
        FieldOfficeChannel(id: "portal", title: "Upload through my Social Security", detail: "The PDF goes in at ssa.gov.", icon: "arrow.up.doc.fill"),
        FieldOfficeChannel(id: "fax", title: "Fax", detail: "Print it, then fax it to the office.", icon: "printer.fill"),
        FieldOfficeChannel(id: "mail", title: "Mail", detail: "Print, sign and mail copies.", icon: "envelope.fill"),
        FieldOfficeChannel(id: "paper", title: "They want original paper receipts", detail: "Bring the envelope and the printed package.", icon: "tray.full.fill"),
        FieldOfficeChannel(id: "unsure", title: "I'm not sure yet", detail: "Halo shows how to ask.", icon: "questionmark.circle.fill"),
    ]

    static func title(for id: String?) -> String {
        all.first { $0.id == id }?.title ?? "Not set"
    }
}

/// The picker itself — shared by Settings and the first-run sheet.
struct FieldOfficeChannelPicker: View {
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(FieldOfficeChannel.all) { channel in
                Button {
                    selection = channel.id
                    Haptics.engine.play(.tapLight)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: channel.icon).font(.title3)
                            .foregroundColor(selection == channel.id ? .white : .haloTextSecondary)
                            .frame(width: 32).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.title).font(.body.weight(.semibold))
                            Text(channel.detail).font(.caption)
                        }
                        .foregroundColor(selection == channel.id ? .white : .haloTextPrimary)
                        Spacer()
                        if selection == channel.id {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.white).accessibilityHidden(true)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(selection == channel.id ? Color.accentColor : Color.haloSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(channel.title). \(channel.detail)")
                .accessibilityAddTraits(selection == channel.id ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

struct FieldOfficeView: View {
    @Environment(UserManager.self) private var userManager
    @Environment(BudgetDataManager.self) private var dataManager

    @State private var selection: String?
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var status: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How does your office like to receive these?")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Your monthly work-expense package is prepared here and you hand it in. HaloFi never sends anything to Social Security.")
                    .font(.subheadline).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                FieldOfficeChannelPicker(selection: $selection)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes for yourself").font(.headline)
                    TextField("Window 3, ask for Rosa. Fax 555-0100.", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Notes about your field office")
                }

                Button { Task { await save() } } label: {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 56)
                    } else {
                        Text("Save").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || selection == nil)

                if let status {
                    Text(status).font(.subheadline).foregroundColor(.haloTextSecondary)
                }

                if let guidance = dataManager.fieldOffice, guidance.isSet {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(guidance.title).font(.headline).accessibilityAddTraits(.isHeader)
                        ForEach(Array(guidance.steps.enumerated()), id: \.offset) { i, step in
                            Text("\(i + 1). \(step)").font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(guidance.neverSends).font(.caption).foregroundColor(.haloTextSecondary)
                    }
                    .padding(14)
                    .background(Color.haloSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(20)
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle("My field office")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selection = userManager.benefitsProfile.fieldOfficeChannel
            notes = userManager.benefitsProfile.fieldOfficeNotes ?? ""
        }
    }

    private func save() async {
        guard let selection else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            var patch = BenefitsProfilePatch()
            patch.fieldOfficeChannel = selection
            patch.fieldOfficeNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            try await userManager.updateBenefitsProfile(patch)
            await userManager.refreshCapabilities()
            dataManager.markStale()
            await dataManager.refresh()
            status = "Saved. The Monthly package screen now shows steps for \(FieldOfficeChannel.title(for: selection).lowercased())."
            Haptics.success()
            UIAccessibility.post(notification: .announcement, argument: status ?? "Saved.")
        } catch {
            status = "Couldn't save. \(error.localizedDescription)"
            Haptics.error()
            UIAccessibility.post(notification: .announcement, argument: status ?? "")
        }
    }
}

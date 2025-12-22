//
//  PreferenceDropdownSection.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct PreferenceDropdownSection: View {
    let title: String
    let subtitle: String
    let icon: String
    let options: [SelectionOption]
    @Binding var selectedId: String

    @State private var showingSheet = false

    private var selectedTitle: String {
        options.first(where: { $0.id == selectedId })?.title ?? "Select"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(Color.accentColor)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            // Trigger row - left-aligned value, chevron on right
            Button {
                showingSheet = true
            } label: {
                HStack {
                    Text(selectedTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title): \(selectedTitle)")
            .accessibilityHint("Tap to change \(title)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(16)
        .sheet(isPresented: $showingSheet) {
            SelectionListView(
                title: title,
                options: options,
                selectedId: $selectedId
            )
            .presentationDetents([.medium, .large])
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 16) {
            PreferenceDropdownSection(
                title: "Voice Language",
                subtitle: "Choose your preferred language",
                icon: "globe",
                options: [
                    .init(id: "en", title: "English"),
                    .init(id: "es", title: "Spanish", disabledReason: "Coming Soon"),
                    .init(id: "fr", title: "French")
                ],
                selectedId: .constant("en")
            )

            PreferenceDropdownSection(
                title: "Theme Mode",
                subtitle: "Select your preferred visual theme",
                icon: "paintbrush",
                options: [
                    .init(id: "system", title: "System"),
                    .init(id: "light", title: "Light"),
                    .init(id: "dark", title: "Dark")
                ],
                selectedId: .constant("system")
            )
        }
        .padding()
    }
}

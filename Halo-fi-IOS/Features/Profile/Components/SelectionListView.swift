//
//  SelectionListView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct SelectionListView: View {
    let title: String
    let options: [SelectionOption]
    @Binding var selectedId: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(options) { option in
                    let isSelected = option.id == selectedId
                    let isDisabled = option.disabledReason != nil

                    Button {
                        guard !isDisabled else { return }
                        selectedId = option.id
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .foregroundStyle(.primary)
                                if let reason = option.disabledReason {
                                    Text(reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if let subtitle = option.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(Color(.tertiarySystemFill))
                    .disabled(isDisabled)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Color(.systemBackground))
    }
}

#Preview {
    SelectionListView(
        title: "Voice Language",
        options: [
            .init(id: "en", title: "English"),
            .init(id: "es", title: "Spanish", disabledReason: "Coming Soon"),
            .init(id: "fr", title: "French", subtitle: "Beta")
        ],
        selectedId: .constant("en")
    )
}

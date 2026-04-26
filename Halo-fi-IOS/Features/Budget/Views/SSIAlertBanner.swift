//
//  SSIAlertBanner.swift
//  Halo-fi-IOS
//
//  Renders one row of the SSI alerts engine output (Phase 5).
//  Severity drives chrome — critical is loudest (red), good is
//  reassuring (green). Action button only appears when the entry
//  exposes an actionLabel; tapping fires the closure passed in.
//
//  Each banner combines into a single VoiceOver element so screen-
//  reader users hear "title. body. action: <label>." in one
//  swipe instead of three.
//
//  The property name is `entry` (not `alert`) to avoid colliding
//  with SwiftUI's View.alert(...) modifier.
//

import SwiftUI

struct SSIAlertBanner: View {
    let entry: SSIAlert
    let onAction: (() -> Void)?

    init(entry: SSIAlert, onAction: (() -> Void)? = nil) {
        self.entry = entry
        self.onAction = onAction
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(entry.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let label = entry.actionLabel, onAction != nil {
                    Button(label) { onAction?() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                        .padding(.top, 2)
                        .accessibilityHint("Opens the related screen.")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(combinedAccessibilityLabel)
    }

    // MARK: - Severity-driven chrome

    private var iconName: String {
        switch entry.severity {
        case "critical": return "exclamationmark.triangle.fill"
        case "warn":     return "exclamationmark.circle.fill"
        case "good":     return "checkmark.seal.fill"
        default:         return "info.circle.fill"  // "info"
        }
    }

    private var iconColor: Color {
        switch entry.severity {
        case "critical": return .red
        case "warn":     return .orange
        case "good":     return .green
        default:         return .blue
        }
    }

    private var backgroundColor: Color {
        switch entry.severity {
        case "critical": return Color.red.opacity(0.12)
        case "warn":     return Color.orange.opacity(0.12)
        case "good":     return Color.green.opacity(0.12)
        default:         return Color.blue.opacity(0.10)
        }
    }

    private var borderColor: Color {
        switch entry.severity {
        case "critical": return Color.red.opacity(0.30)
        case "warn":     return Color.orange.opacity(0.30)
        case "good":     return Color.green.opacity(0.30)
        default:         return Color.blue.opacity(0.25)
        }
    }

    private var combinedAccessibilityLabel: String {
        var parts = [
            "\(severityWord) alert.",
            entry.title + ".",
            entry.body,
        ]
        if let label = entry.actionLabel, onAction != nil {
            parts.append("Action: \(label).")
        }
        return parts.joined(separator: " ")
    }

    private var severityWord: String {
        switch entry.severity {
        case "critical": return "Critical"
        case "warn":     return "Warning"
        case "good":     return "Status"
        default:         return "Info"
        }
    }
}

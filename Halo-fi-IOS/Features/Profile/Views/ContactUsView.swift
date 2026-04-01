//
//  ContactUsView.swift
//  Halo-fi-IOS
//
//  Unified contact form for support, bugs, and feature requests.
//

import SwiftUI
import UIKit

enum ContactTopic: String, CaseIterable, Identifiable {
    case support = "support"
    case bug = "bug"
    case feature = "feature"
    case other = "other"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .support: return "Support Request"
        case .bug: return "Bug Report"
        case .feature: return "Feature Request"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .support: return "envelope.fill"
        case .bug: return "ant.fill"
        case .feature: return "lightbulb.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .support: return .blue
        case .bug: return .orange
        case .feature: return .yellow
        case .other: return .gray
        }
    }
}

struct ContactUsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserManager.self) private var userManager

    @State private var selectedTopic: ContactTopic = .support
    @State private var message = ""
    @State private var isSending = false
    @State private var showingResult = false
    @State private var resultMessage = ""
    @State private var resultSuccess = false

    private let networkService = NetworkService.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ModalHeader(title: "Contact Us", onDone: { dismiss() })

                ScrollView {
                    VStack(spacing: 24) {
                        // Topic Picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Topic")
                                .font(.headline)
                                .foregroundColor(.white)

                            HStack(spacing: 10) {
                                ForEach(ContactTopic.allCases) { topic in
                                    Button {
                                        selectedTopic = topic
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: topic.icon)
                                                .font(.title3)
                                                .foregroundColor(selectedTopic == topic ? topic.color : .gray)
                                            Text(topic.label)
                                                .font(.caption2)
                                                .foregroundColor(selectedTopic == topic ? .white : .gray)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(selectedTopic == topic ? Color.gray.opacity(0.2) : Color.clear)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(selectedTopic == topic ? topic.color.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .accessibilityLabel(topic.label)
                                    .accessibilityAddTraits(selectedTopic == topic ? .isSelected : [])
                                }
                            }
                        }

                        // Message
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Message")
                                .font(.headline)
                                .foregroundColor(.white)

                            TextField("Tell us what's on your mind...", text: $message, axis: .vertical)
                                .textFieldStyle(CustomTextFieldStyle())
                                .lineLimit(5...10)
                        }

                        // Send
                        ActionButton(
                            title: isSending ? "Sending..." : "Send Message",
                            gradient: LinearGradient(
                                colors: [Color.teal, Color.blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        ) {
                            Task { await sendMessage() }
                        }
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                        .opacity(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1.0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                Spacer()
            }
        }
        .alert(resultSuccess ? "Message Sent!" : "Error", isPresented: $showingResult) {
            Button("OK") {
                if resultSuccess { dismiss() }
            }
        } message: {
            Text(resultMessage)
        }
    }

    private func sendMessage() async {
        isSending = true
        defer { isSending = false }

        let device = UIDevice.current
        let deviceInfo = "\(device.model), iOS \(device.systemVersion)"

        struct ContactBody: Encodable {
            let topic: String
            let message: String
            let device_info: String
        }

        struct ContactResponse: Codable {
            let success: Bool
            let message: String
        }

        do {
            let body = ContactBody(
                topic: selectedTopic.rawValue,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                device_info: deviceInfo
            )
            let requestBody = try JSONEncoder().encode(body)

            let response: ContactResponse = try await networkService.authenticatedRequest(
                endpoint: "/support/contact",
                method: .POST,
                body: requestBody,
                responseType: ContactResponse.self
            )

            resultSuccess = response.success
            resultMessage = response.message
        } catch {
            resultSuccess = false
            resultMessage = "Unable to send your message. Please try again."
        }

        showingResult = true
    }
}

#Preview {
    ContactUsView()
        .environment(UserManager())
}

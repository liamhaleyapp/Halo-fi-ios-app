//
//  BiometricEnrollmentSheet.swift
//  Halo-fi-IOS
//
//  Post-sign-in offer to enable Face ID / Touch ID. Either button dismisses;
//  the parent view-model wires the choice into the keychain save and the
//  deferred routing action.
//

import SwiftUI
import LocalAuthentication

struct BiometricEnrollmentSheet: View {
  let biometryType: LABiometryType
  let onChoice: (Bool) -> Void

  @Environment(\.dismiss) private var dismiss

  private var biometryName: String {
    switch biometryType {
    case .faceID: return "Face ID"
    case .touchID: return "Touch ID"
    default: return "biometrics"
    }
  }

  private var iconName: String {
    switch biometryType {
    case .faceID: return "faceid"
    case .touchID: return "touchid"
    default: return "lock.shield"
    }
  }

  var body: some View {
    VStack(spacing: 24) {
      Spacer().frame(height: 8)

      Image(systemName: iconName)
        .font(.system(size: 64))
        .foregroundStyle(
          LinearGradient(
            colors: [Color.purple, Color.indigo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .accessibilityHidden(true)

      VStack(spacing: 8) {
        Text("Sign in faster with \(biometryName)")
          .font(.title2)
          .fontWeight(.bold)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)

        Text("Skip the typing next time. Open the app and \(biometryName) signs you in automatically.")
          .font(.body)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 8)

        Text("You can change this anytime in Settings.")
          .font(.footnote)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.top, 4)
      }

      Spacer()

      VStack(spacing: 12) {
        Button {
          onChoice(true)
          dismiss()
        } label: {
          Text("Enable \(biometryName)")
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
              LinearGradient(
                colors: [Color.purple, Color.indigo],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .cornerRadius(16)
        }
        .accessibilityHint("Enables biometric sign-in for next time")

        Button {
          onChoice(false)
          dismiss()
        } label: {
          Text("Not Now")
            .font(.body)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .accessibilityHint("Skip enabling biometric sign-in")
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 32)
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
    .interactiveDismissDisabled(false)
  }
}

#Preview {
  Color.haloBackground
    .ignoresSafeArea()
    .sheet(isPresented: .constant(true)) {
      BiometricEnrollmentSheet(biometryType: .faceID) { _ in }
    }
}

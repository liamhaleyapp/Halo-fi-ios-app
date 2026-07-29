//
//  AuthFormField.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct AuthFormField: View {
  let title: String
  let placeholder: String
  @Binding var text: String
  let isSecure: Bool
  let keyboardType: UIKeyboardType
  let textContentType: UITextContentType?
  let onFocusChange: ((Bool) -> Void)?

  @FocusState private var isFocused: Bool

  init(
    title: String,
    placeholder: String,
    text: Binding<String>,
    isSecure: Bool = false,
    keyboardType: UIKeyboardType = .default,
    textContentType: UITextContentType? = nil,
    onFocusChange: ((Bool) -> Void)? = nil
  ) {
    self.title = title
    self.placeholder = placeholder
    self._text = text
    self.isSecure = isSecure
    self.keyboardType = keyboardType
    self.textContentType = textContentType
    self.onFocusChange = onFocusChange
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
        .foregroundColor(.haloTextPrimary)
        .accessibilityHidden(true)

      Group {
        if isSecure {
          SecureField(placeholder, text: $text)
        } else {
          TextField(placeholder, text: $text)
        }
      }
      .textFieldStyle(CustomTextFieldStyle())
      .keyboardType(keyboardType)
      .autocapitalization(autocapitalizationType)
      .textContentType(textContentType)
      .focused($isFocused)
      .onChange(of: isFocused) { _, newValue in
        onFocusChange?(newValue)
      }
      .accessibilityLabel(title)
      .accessibilityHint("Enter your \(title.lowercased())")
      .accessibilityValue(accessibilityValueText)
    }
  }
  
  private var accessibilityValueText: String {
    if isSecure {
      return text.isEmpty ? "No \(title.lowercased()) entered" : "\(title) entered"
    } else {
      return text.isEmpty ? placeholder : text
    }
  }

  private var autocapitalizationType: UITextAutocapitalizationType {
    switch textContentType {
    case .givenName, .familyName, .name, .middleName, .nickname:
      return .words
    default:
      return .none
    }
  }
}

#Preview {
  ZStack {
    Color.haloBackground.ignoresSafeArea()
    VStack(spacing: 20) {
      AuthFormField(
        title: "Email",
        placeholder: "Enter your email",
        text: .constant(""),
        keyboardType: .emailAddress
      )
      
      AuthFormField(
        title: "Password",
        placeholder: "Enter your password",
        text: .constant(""),
        isSecure: true
      )
    }
    .padding()
  }
}

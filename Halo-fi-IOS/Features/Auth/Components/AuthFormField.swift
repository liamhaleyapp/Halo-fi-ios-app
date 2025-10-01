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
  
  init(title: String, placeholder: String, text: Binding<String>, isSecure: Bool = false, keyboardType: UIKeyboardType = .default) {
    self.title = title
    self.placeholder = placeholder
    self._text = text
    self.isSecure = isSecure
    self.keyboardType = keyboardType
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
        .foregroundColor(.white)
      
      Group {
        if isSecure {
          SecureField(placeholder, text: $text)
        } else {
          TextField(placeholder, text: $text)
        }
      }
      .textFieldStyle(CustomTextFieldStyle())
      .keyboardType(keyboardType)
      .autocapitalization(isSecure ? .none : .none)
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
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

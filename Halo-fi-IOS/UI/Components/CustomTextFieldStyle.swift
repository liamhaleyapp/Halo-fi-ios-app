//
//  CustomTextFieldStyle.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct CustomTextFieldStyle: TextFieldStyle {
  func _body(configuration: TextField<Self._Label>) -> some View {
    configuration
      .padding(.horizontal, 16)
      .padding(.vertical, 16)
      .background(Color.haloSecondaryBackground)
      .cornerRadius(12)
      .foregroundColor(.haloTextPrimary)
      .accentColor(.blue)
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.haloSeparator, lineWidth: 1)
      )
  }
}

#Preview {
  ZStack {
    Color.haloBackground.ignoresSafeArea()
    VStack(spacing: 20) {
      TextField("Email", text: .constant(""))
        .textFieldStyle(CustomTextFieldStyle())
      
      SecureField("Password", text: .constant(""))
        .textFieldStyle(CustomTextFieldStyle())
    }
    .padding()
  }
}

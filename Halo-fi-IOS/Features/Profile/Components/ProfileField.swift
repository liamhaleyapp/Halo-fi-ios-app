//
//  ProfileField.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct ProfileField: View {
  let title: String
  @Binding var value: String
  let placeholder: String
  let icon: String
  var keyboardType: UIKeyboardType = .default
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: icon)
          .font(.title3)
          .foregroundColor(.blue)
          .frame(width: 20, height: 20)
        
        Text(title)
          .font(.headline)
          .foregroundColor(.white)
        
        Spacer()
      }
      
      TextField(placeholder, text: $value)
        .textFieldStyle(CustomTextFieldStyle())
        .keyboardType(keyboardType)
        .autocapitalization(.none)
        .disableAutocorrection(true)
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    VStack(spacing: 20) {
      ProfileField(
        title: "Full Name",
        value: .constant("John Doe"),
        placeholder: "Enter your full name",
        icon: "person.fill"
      )
      
      ProfileField(
        title: "Email",
        value: .constant("john@example.com"),
        placeholder: "Enter your email",
        icon: "envelope.fill",
        keyboardType: .emailAddress
      )
    }
    .padding()
  }
}

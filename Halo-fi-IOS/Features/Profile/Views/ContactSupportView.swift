//
//  ContactSupportView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Contact Support View
struct ContactSupportView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var message = ""
  @State private var showingSent = false
  
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 0) {
        ModalHeader(title: "Contact Support", onDone: { dismiss() })
        
        VStack(spacing: 20) {
          VStack(alignment: .leading, spacing: 12) {
            Text("How can we help you?")
              .font(.body)
              .foregroundColor(.white)
            
            TextField("Your message...", text: $message, axis: .vertical)
              .textFieldStyle(CustomTextFieldStyle())
              .lineLimit(4...8)
          }
          .padding(.horizontal, 20)
          
          ActionButton(
            title: "Send Message",
            gradient: LinearGradient(
              colors: [Color.teal, Color.blue],
              startPoint: .leading,
              endPoint: .trailing
            )
          ) {
            showingSent = true
          }
          .padding(.horizontal, 20)
          .disabled(message.isEmpty)
          
          Spacer()
        }
        
        Spacer()
      }
    }
    .alert("Message Sent!", isPresented: $showingSent) {
      Button("OK") { }
    } message: {
      Text("We'll get back to you within 24 hours.")
    }
  }
}

// MARK: - Preview
#Preview {
  ContactSupportView()
}

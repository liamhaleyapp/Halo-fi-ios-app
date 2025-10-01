//
//  BugReportView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Bug Report View
struct BugReportView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var bugDescription = ""
  @State private var showingSent = false
  
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 0) {
        ModalHeader(title: "Report a Bug / Feedback", onDone: { dismiss() })
        
        VStack(spacing: 20) {
          VStack(alignment: .leading, spacing: 12) {
            Text("Help us improve Halo Fi")
              .font(.body)
              .foregroundColor(.white)
            
            TextField("Describe the issue or share your feedback...", text: $bugDescription, axis: .vertical)
              .textFieldStyle(CustomTextFieldStyle())
              .lineLimit(4...8)
          }
          .padding(.horizontal, 20)
          
          ActionButton(
            title: "Submit Report",
            gradient: LinearGradient(
              colors: [Color.teal, Color.blue],
              startPoint: .leading,
              endPoint: .trailing
            )
          ) {
            showingSent = true
          }
          .padding(.horizontal, 20)
          .disabled(bugDescription.isEmpty)
          
          Spacer()
        }
        
        Spacer()
      }
    }
    .alert("Report Submitted!", isPresented: $showingSent) {
      Button("OK") { }
    } message: {
      Text("Thank you for helping us improve Halo Fi!")
    }
  }
}

// MARK: - Preview
#Preview {
  BugReportView()
}

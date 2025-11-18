//
//  ForgotPasswordView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct ForgotPasswordView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(UserManager.self) private var userManager
  @State private var email = ""
  @State private var isLoading = false
  @State private var showingSuccess = false
  
  var body: some View {
    NavigationView {
      ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 24) {
          // Header
          VStack(spacing: 16) {
            Image(systemName: "lock.rotation")
              .font(.system(size: 60))
              .foregroundColor(.blue)
            
            Text("Reset Password")
              .font(.largeTitle)
              .fontWeight(.bold)
              .foregroundColor(.white)
            
            Text("Enter your email and we'll send you a link to reset your password")
              .font(.body)
              .foregroundColor(.gray)
              .multilineTextAlignment(.center)
          }
          
          // Email Field
          VStack(alignment: .leading, spacing: 8) {
            Text("Email")
              .font(.headline)
              .foregroundColor(.white)
            
            TextField("Enter your email", text: $email)
              .textFieldStyle(CustomTextFieldStyle())
              .keyboardType(.emailAddress)
              .autocapitalization(.none)
          }
          
          // Reset Button
          Button(action: resetPassword) {
            HStack {
              if isLoading {
                ProgressView()
                  .progressViewStyle(CircularProgressViewStyle(tint: .white))
                  .scaleEffect(0.8)
              } else {
                Text("Send Reset Link")
                  .font(.headline)
                  .fontWeight(.semibold)
              }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
              LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(16)
          }
          .disabled(isLoading || email.isEmpty)
          .opacity(email.isEmpty ? 0.6 : 1.0)
          
          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
      }
    }
    .navigationBarHidden(true)
    .alert("Reset Link Sent", isPresented: $showingSuccess) {
      Button("OK") {
        dismiss()
      }
    } message: {
      Text("Check your email for password reset instructions.")
    }
  }
  
  private func resetPassword() {
    Task {
      do {
        try await userManager.resetPassword(email: email)
        showingSuccess = true
      } catch {
        // TODO: Show error message
        print("Error resetting password: \(error)")
      }
    }
  }
}

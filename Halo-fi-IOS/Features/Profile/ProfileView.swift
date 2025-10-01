//
//  ProfileView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct ProfileView: View {
  @Environment(\.dismiss) var dismiss
  @State private var fullName = "Liam Haley"
  @State private var email = "liam.haley@example.com"
  @State private var phoneNumber = "+1 (555) 123-4567"
  @State private var dateOfBirth = Date()
  @State private var showingDatePicker = false
  @State private var hasChanges = false
  
  var body: some View {
    ZStack {
      // Dark background
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 0) {
        // Header
        ProfileHeader(onBack: { dismiss() })
        
        // Content
        ScrollView {
          VStack(spacing: 32) {
            // Personal Information Section
            VStack(spacing: 24) {
              ProfileField(
                title: "Full Name",
                value: $fullName,
                placeholder: "Enter your full name",
                icon: "person.fill"
              )
              
              ProfileField(
                title: "Email Address",
                value: $email,
                placeholder: "Enter your email",
                icon: "envelope.fill",
                keyboardType: .emailAddress
              )
              
              ProfileField(
                title: "Phone Number",
                value: $phoneNumber,
                placeholder: "Enter your phone number",
                icon: "phone.fill",
                keyboardType: .phonePad
              )
              
              // Date of Birth
              DateOfBirthField(selectedDate: dateOfBirth) {
                showingDatePicker = true
              }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(20)
            
            // Save Button
            SaveProfileButton(isEnabled: hasChanges, onSave: saveProfile)
            
            Spacer(minLength: 40)
          }
          .padding(.top, 10)
        }
      }
    }
    .navigationBarHidden(true)
    .sheet(isPresented: $showingDatePicker) {
      DatePickerSheet(selectedDate: $dateOfBirth)
    }
    .onChange(of: fullName) { _, _ in hasChanges = true }
    .onChange(of: email) { _, _ in hasChanges = true }
    .onChange(of: phoneNumber) { _, _ in hasChanges = true }
    .onChange(of: dateOfBirth) { _, _ in hasChanges = true }
  }
  
  private func saveProfile() {
    // TODO: Implement actual save logic
    // For now, just show success feedback
    
    // Haptic feedback
    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    impactFeedback.impactOccurred()
    
    // Reset changes flag
    hasChanges = false
    
    // TODO: Show success toast or alert
  }
}

#Preview {
  ProfileView()
}

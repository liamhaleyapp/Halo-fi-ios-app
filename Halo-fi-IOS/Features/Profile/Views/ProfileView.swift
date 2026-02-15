//
//  ProfileView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct ProfileView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(UserManager.self) private var userManager
  
  @State private var firstName = ""
  @State private var lastName = ""
  @State private var email = ""
  @State private var phoneNumber = ""
  @State private var dateOfBirth: Date?
  @State private var hasChanges = false
  @State private var isSaving = false
  @State private var isLoadingProfile = false
  @State private var showingDatePicker = false
  @State private var originalFirstName = ""
  @State private var originalLastName = ""
  @State private var originalEmail = ""
  @State private var originalDateOfBirth: Date?
  
  var body: some View {
    ScrollView {
      VStack(spacing: 32) {
        // Personal Information Section
        VStack(spacing: 24) {
          ProfileField(
            title: "First Name",
            value: $firstName,
            placeholder: "Enter your first name",
            icon: "person.fill"
          )

          ProfileField(
            title: "Last Name",
            value: $lastName,
            placeholder: "Enter your last name",
            icon: "person.fill"
          )

          ProfileField(
            title: "Email Address",
            value: $email,
            placeholder: "Enter your email",
            icon: "envelope.fill",
            keyboardType: .emailAddress,
            isDisabled: true
          )

          ProfileField(
            title: "Phone Number",
            value: $phoneNumber,
            placeholder: "Enter your phone number",
            icon: "phone.fill",
            keyboardType: .phonePad,
            isDisabled: true
          )

          // Date of Birth
          DateOfBirthField(selectedDate: dateOfBirth ?? Date()) {
            showingDatePicker = true
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(20)

        // Save Button
        SaveProfileButton(isEnabled: hasChanges && !isSaving, onSave: saveProfile)

        Spacer(minLength: 40)
      }
      .padding(.top, 10)
    }
    .navigationTitle("Profile")
    .navigationBarTitleDisplayMode(.large)
    .sheet(isPresented: $showingDatePicker) {
      DatePickerSheet(selectedDate: Binding(
        get: { dateOfBirth ?? Date() },
        set: { dateOfBirth = $0 }
      ))
    }
    .onAppear {
      loadUserData()
      // Fetch fresh profile data from server
      Task {
        await fetchProfileData()
      }
    }
    .onChange(of: firstName) { _, _ in checkForChanges() }
    .onChange(of: lastName) { _, _ in checkForChanges() }
    .onChange(of: dateOfBirth) { _, _ in checkForChanges() }
  }
  
  private func loadUserData() {
    guard let user = userManager.currentUser else { return }
    
    firstName = user.firstName
    lastName = user.lastName ?? ""
    email = user.email
    phoneNumber = user.phone ?? ""
    dateOfBirth = user.dateOfBirth
    
    // Store original values for change detection
    originalFirstName = user.firstName
    originalLastName = user.lastName ?? ""
    originalEmail = user.email
    originalDateOfBirth = user.dateOfBirth
  }
  
  private func fetchProfileData() async {
    isLoadingProfile = true
    
    do {
      try await userManager.fetchUserProfile()
      
      // Reload data after fetching
      await MainActor.run {
        loadUserData()
        isLoadingProfile = false
      }
    } catch {
      await MainActor.run {
        isLoadingProfile = false
      }
      // Silently fail - we'll still show cached data
      Logger.error("Error fetching profile: \(error)")
    }
  }
  
  private func checkForChanges() {
    // Note: email changes are not tracked since email updates require verification
    hasChanges = 
      firstName != originalFirstName ||
      lastName != originalLastName ||
      dateOfBirth != originalDateOfBirth
  }
  
  private func saveProfile() {
    Task {
      isSaving = true
      
      // Haptic feedback
      let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
      impactFeedback.impactOccurred()
      
      do {
        try await userManager.updateUserProfile(
          firstName: firstName,
          lastName: lastName.isEmpty ? nil : lastName,
          dateOfBirth: dateOfBirth
        )
        
        // Update original values after successful save
        await MainActor.run {
          originalFirstName = firstName
          originalLastName = lastName
          originalEmail = email
          originalDateOfBirth = dateOfBirth
          hasChanges = false
          isSaving = false
        }
        
        // TODO: Show success toast or alert
      } catch {
        await MainActor.run {
          isSaving = false
        }
        // TODO: Show error message
        Logger.error("Error saving profile: \(error)")
      }
    }
  }
}

#Preview {
  ProfileView()
}

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
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("Profile")
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Color.clear
                        .frame(width: 40, height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 30)
                
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
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "calendar")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                        .frame(width: 20, height: 20)
                                    
                                    Text("Date of Birth")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                }
                                
                                Button(action: {
                                    showingDatePicker = true
                                }) {
                                    HStack {
                                        Text(dateOfBirth, style: .date)
                                            .foregroundColor(.white)
                                            .padding(.leading, 16)
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.gray)
                                            .padding(.trailing, 16)
                                    }
                                    .frame(height: 50)
                                    .background(Color.gray.opacity(0.15))
                                    .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(20)
                        
                        // Save Button
                        Button(action: saveProfile) {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.white)
                                
                                Text("Save Changes")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color.purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                        .disabled(!hasChanges)
                        .opacity(hasChanges ? 1.0 : 0.5)
                        .padding(.horizontal, 20)
                        
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

// MARK: - Profile Field Component

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
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
                .keyboardType(keyboardType)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
    }
}

// MARK: - Date Picker Sheet

struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text("Select Date of Birth")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.top, 20)
                    
                    DatePicker(
                        "Date of Birth",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(WheelDatePickerStyle())
                    .accentColor(.blue)
                    .colorScheme(.dark)
                    
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    ProfileView()
} 
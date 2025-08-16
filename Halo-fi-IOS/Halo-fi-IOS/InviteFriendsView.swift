import SwiftUI

struct InviteFriendsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State Variables
    @State private var inviteEmail = ""
    @State private var invitePhone = ""
    @State private var showingInviteSent = false
    @State private var showingCopiedLink = false
    @State private var selectedInviteMethod: InviteMethod = .email
    
    // MARK: - Referral Data
    private let referralLink = "https://halofi.app/ref/user123"
    private let referralCode = "HALO123"
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    headerView
                    referralSummarySection
                    inviteSection
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .alert("Invite Sent!", isPresented: $showingInviteSent) {
            Button("OK") { }
        } message: {
            Text("Your friend will receive an invitation to join Halo Fi!")
        }
        .alert("Link Copied!", isPresented: $showingCopiedLink) {
            Button("OK") { }
        } message: {
            Text("Your referral link has been copied to the clipboard.")
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
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
            
            Text("Invite Friends")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Spacer()
            
            // Placeholder for balance
            Color.clear
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 15)
        .padding(.bottom, 20)
    }
    
    // MARK: - Referral Summary Section
    private var referralSummarySection: some View {
        VStack(spacing: 16) {
            // Incentive Text
            VStack(spacing: 8) {
                Text("Get $5 for every friend who joins!")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("Share Halo Fi with your friends and earn rewards together")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            
            // Referral Link Card
            VStack(spacing: 12) {
                Text("Your Referral Link")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 12) {
                    Text(referralLink)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Button(action: {
                        UIPasteboard.general.string = referralLink
                        showingCopiedLink = true
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(LinearGradient(colors: [Color.teal, Color.blue], startPoint: .leading, endPoint: .trailing))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                // Referral Code
                HStack(spacing: 12) {
                    Text("Referral Code:")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Text(referralCode)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                    
                    Spacer()
                    
                    Button(action: {
                        UIPasteboard.general.string = referralCode
                        showingCopiedLink = true
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Invite Section
    private var inviteSection: some View {
        VStack(spacing: 16) {
            Text("Send an Invite")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Invite Method Toggle
            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedInviteMethod = .email
                    }
                }) {
                    Text("Email")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(selectedInviteMethod == .email ? .white : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedInviteMethod == .email ? 
                                AnyShapeStyle(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing)) : 
                                AnyShapeStyle(Color.gray.opacity(0.1))
                        )
                }
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedInviteMethod = .phone
                    }
                }) {
                    Text("Phone")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(selectedInviteMethod == .phone ? .white : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedInviteMethod == .phone ? 
                                AnyShapeStyle(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing)) : 
                                AnyShapeStyle(Color.gray.opacity(0.1))
                        )
                }
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Input Field
            if selectedInviteMethod == .email {
                TextField("Enter email address", text: $inviteEmail)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            } else {
                TextField("Enter phone number", text: $invitePhone)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .keyboardType(.phonePad)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // Send Invite Button
            Button(action: {
                sendInvite()
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "paperplane.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Send Invite")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(LinearGradient(colors: [Color.teal, Color.blue], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(12)
            }
            .disabled(selectedInviteMethod == .email ? inviteEmail.isEmpty : invitePhone.isEmpty)
            .opacity(selectedInviteMethod == .email ? (inviteEmail.isEmpty ? 0.6 : 1.0) : (invitePhone.isEmpty ? 0.6 : 1.0))
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Helper Functions
    private func sendInvite() {
        // TODO: Implement actual invite sending logic
        showingInviteSent = true
        
        // Clear the input field
        if selectedInviteMethod == .email {
            inviteEmail = ""
        } else {
            invitePhone = ""
        }
    }
}

// MARK: - Models
enum InviteMethod {
    case email, phone
}

#Preview {
    InviteFriendsView()
}

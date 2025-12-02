//
//  AccountsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct AccountsView: View {
  @Environment(\.dismiss) private var dismiss
  
  // MARK: - State Variables
  @State private var showingLinkNewAccount = false
  
  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        LinkNewAccountSection {
          showingLinkNewAccount = true
        }
        
        // TODO: Add institutions list here when ready
        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 20)
      .navigationTitle("Accounts")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "chevron.left")
              Text("Settings")
            }
          }
          .accessibilityLabel("Back to Settings")
        }
      }
    }
    .fullScreenCover(isPresented: $showingLinkNewAccount) {
      PlaidOnboardingScreen(
        onComplete: {
          showingLinkNewAccount = false
        },
        onBack: {
          showingLinkNewAccount = false
        }
      )
    }
  }
}


#Preview {
  AccountsView()
}

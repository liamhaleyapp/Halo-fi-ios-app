//
//  PlaidOnboardingView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct PlaidOnboardingView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var plaidManager = PlaidManager()
  @State private var isLoading = true
  @State private var showingError = false
  @State private var errorMessage = ""
  
  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        // Header
        PlaidHeader(onCancel: { dismiss() })
        
        // Plaid WebView
        if isLoading {
          PlaidLoadingView()
        } else {
          Button("Connect") {
            Task {
              try await plaidManager.createLinkToken()
            }
          }
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(
            LinearGradient(
              colors: [Color.indigo, Color.purple],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
        }
      }
      .navigationBarHidden(true)
    }
    .onAppear {
      startPlaidFlow()
    }
    .alert("Connection Error", isPresented: $showingError) {
      Button("OK") { }
    } message: {
      Text(errorMessage)
    }
  }
  
  // MARK: - Plaid Flow Methods
  private func startPlaidFlow() {
    Task {
      do {
        try await plaidManager.createLinkToken()
        await MainActor.run {
          isLoading = false
        }
      } catch {
        await MainActor.run {
          errorMessage = "Failed to start bank connection: \(error.localizedDescription)"
          showingError = true
          isLoading = false
        }
      }
    }
  }
  
  private func handlePlaidSuccess(_ publicToken: String) {
    Task {
      do {
        try await plaidManager.exchangePublicToken(publicToken)
        await MainActor.run {
          // Success - dismiss and return to main app
          dismiss()
        }
      } catch {
        await MainActor.run {
          errorMessage = "Failed to complete connection: \(error.localizedDescription)"
          showingError = true
          isLoading = false
        }
      }
    }
  }
  
  private func handlePlaidExit(_ error: PlaidError?) {
    if let error = error {
      errorMessage = "Connection failed: \(error.localizedDescription)"
      showingError = true
      isLoading = false
    } else {
      // User cancelled - just dismiss
      dismiss()
    }
  }
}

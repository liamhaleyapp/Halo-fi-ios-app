//
//  PlaidIntroView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/1/25.
//

import SwiftUI

struct PlaidIntroView: View {
  let action: () -> Void
  var body: some View {
  
    ScrollView {
      VStack(spacing: 24) {
        // Icon
        Image(systemName: "lock.shield.fill")
          .font(.system(size: 64))
          .foregroundStyle(.blue)
          .padding(.top, 40)
        
        // Title
        Text("Connect Your Bank Account")
          .font(.largeTitle)
          .fontWeight(.bold)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)
        
        // Description
        VStack(spacing: 12) {
          Text("Securely connect your accounts to get personalized financial insights and manage your money in one place.")
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
          
          Text("Your data is encrypted and protected with bank-level security.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
        
        Spacer(minLength: 20)
        
        // Start button
        Button(action: action) {
          HStack(spacing: 12) {
            Image(systemName: "arrow.right.circle.fill")
              .font(.headline)
            Text("Start Connection")
              .font(.headline)
              .fontWeight(.semibold)
          }
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 56)
          .background(Color.accentColor)
          .cornerRadius(16)
        }
        .accessibilityLabel("Start bank connection")
        .accessibilityHint("Opens secure bank connection interface")
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
      }
      .padding(.top, 20)
    }
  }
}

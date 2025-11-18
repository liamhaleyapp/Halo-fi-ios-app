//
//  SignInDebugMenu.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/18/25.
//

import SwiftUI

#if DEBUG
struct SignInDebugMenu: View {
  let quickTestLogin: () -> Void
  let mockUserLogin: () -> Void
  let testSubscriptionFlow: () -> Void
  let testPlaidFlow: () -> Void
  let clearUserData: () -> Void
  
  var body: some View {
    VStack(spacing: 12) {
      Divider()
        .background(Color.gray.opacity(0.3))
      
      Text("DEBUG MENU")
        .font(.caption)
        .foregroundColor(.orange)
        .fontWeight(.bold)
      
      VStack(spacing: 8) {
        Button("🚀 Quick Test Login") {
          quickTestLogin()
        }
        .foregroundColor(.green)
        .font(.caption)
        
        Button("👤 Mock User Login") {
          mockUserLogin()
        }
        .foregroundColor(.blue)
        .font(.caption)
        
        Button("💳 Test Subscription Flow") {
          testSubscriptionFlow()
        }
        .foregroundColor(.purple)
        .font(.caption)
        
        Button("🏦 Test Plaid Flow") {
          testPlaidFlow()
        }
        .foregroundColor(.cyan)
        .font(.caption)
        
        Button("🔧 Clear User Data") {
          clearUserData()
        }
        .foregroundColor(.red)
        .font(.caption)
      }
    }
    .padding(.top, 10)
  }
}
#endif

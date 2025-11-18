//
//  AboutView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct AboutView: View {
  @Environment(\.dismiss) private var dismiss
  
  @State private var showingTeam = false
  @State private var showingTerms = false
  @State private var showingPrivacy = false
  @State private var showingContactSupport = false
  @State private var showingBugReport = false
  
  var body: some View {
    ZStack {
      // Background - ensure it covers the entire screen
      Color.black
        .ignoresSafeArea(.all, edges: .all)
      
      VStack(spacing: 0) {
        AboutHeader(onBack: { dismiss() })
        
        ScrollView {
          VStack(spacing: 12) {
            WhatIsHaloFiSection()
            OurMissionSection()
            MeetTheTeamButtonSection { showingTeam = true }
            DataSecuritySection()
            LegalAndSupportSection(
              onTermsTap: { showingTerms = true },
              onPrivacyTap: { showingPrivacy = true },
              onContactSupportTap: { showingContactSupport = true },
              onBugReportTap: { showingBugReport = true }
            )
            AppVersionSection()
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 100)
        }
        
        Spacer()
      }
    }
    .sheet(isPresented: $showingTeam) {
      TeamView()
    }
    .sheet(isPresented: $showingTerms) {
      TermsView()
    }
    .sheet(isPresented: $showingPrivacy) {
      PrivacyView()
    }
    .sheet(isPresented: $showingContactSupport) {
      ContactSupportView()
    }
    .sheet(isPresented: $showingBugReport) {
      BugReportView()
    }
  }
}

#Preview {
  AboutView()
}

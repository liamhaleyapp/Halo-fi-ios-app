//
//  AboutContentSections.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - What is Halo Fi Section
struct WhatIsHaloFiSection: View {
  var body: some View {
    InfoCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("What is Halo Fi?")
          .font(.headline)
          .foregroundColor(.gray)
        
        Text("Your voice-first financial assistant, designed to make understanding your finances simple, clear, and accessible. Halo Fi empowers everyone, especially those who are visually impaired, with intuitive and supportive tools built around voice and ease of use.")
          .font(.body)
          .foregroundColor(.white)
          .multilineTextAlignment(.leading)
          .lineLimit(nil)
      }
    }
  }
}

// MARK: - Our Mission Section
struct OurMissionSection: View {
  var body: some View {
    InfoCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Our Mission")
          .font(.headline)
          .foregroundColor(.gray)
        
        Text("To bring visibility to personal finances through accessible and intelligent technology—empowering everyone, especially those with visual impairments.")
          .font(.body)
          .foregroundColor(.white)
          .multilineTextAlignment(.leading)
          .lineLimit(nil)
      }
    }
  }
}

// MARK: - Meet the Team Button Section
struct MeetTheTeamButtonSection: View {
  let onTap: () -> Void
  
  var body: some View {
    ActionButton(
      title: "Meet the Team",
      gradient: LinearGradient(
        colors: [Color.indigo, Color.purple],
        startPoint: .leading,
        endPoint: .trailing
      )
    ) {
      onTap()
    }
  }
}

// MARK: - Data Security Section
struct DataSecuritySection: View {
  var body: some View {
    InfoCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Data Security")
          .font(.headline)
          .foregroundColor(.gray)
        
        HStack(spacing: 12) {
          Image(systemName: "lock.shield.fill")
            .foregroundColor(.teal)
            .font(.title3)
          
          Text("End-to-end encryption")
            .font(.body)
            .foregroundColor(.white)
          
          Spacer()
        }
      }
    }
  }
}

// MARK: - Legal and Support Section
struct LegalAndSupportSection: View {
  let onTermsTap: () -> Void
  let onPrivacyTap: () -> Void
  let onContactSupportTap: () -> Void
  let onBugReportTap: () -> Void
  
  var body: some View {
    VStack(spacing: 16) {
      // Legal Links
      VStack(spacing: 12) {
        Button(action: onTermsTap) {
          HStack {
            Text("Terms of Service")
              .font(.body)
              .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundColor(.gray)
              .font(.caption)
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .background(Color.gray.opacity(0.1))
          .cornerRadius(16)
        }
        
        Button(action: onPrivacyTap) {
          HStack {
            Text("Privacy Policy")
              .font(.body)
              .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundColor(.gray)
              .font(.caption)
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .background(Color.gray.opacity(0.1))
          .cornerRadius(16)
        }
      }
      
      // Support & Feedback
      VStack(spacing: 12) {
        Button(action: onContactSupportTap) {
          HStack {
            Text("Contact Support")
              .font(.body)
              .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundColor(.gray)
              .font(.caption)
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .background(Color.gray.opacity(0.1))
          .cornerRadius(16)
        }
        
        Button(action: onBugReportTap) {
          HStack {
            Text("Report a Bug / Feedback")
              .font(.body)
              .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundColor(.gray)
              .font(.caption)
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .background(Color.gray.opacity(0.1))
          .cornerRadius(16)
        }
      }
    }
  }
}

// MARK: - App Version Section
struct AppVersionSection: View {
  var body: some View {
    VStack(spacing: 16) {
      // App Version
      HStack {
        Text("App Version: v1.0.0")
          .font(.body)
          .foregroundColor(.gray)
        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .background(Color.gray.opacity(0.1))
      .cornerRadius(16)
    }
  }
}

// MARK: - Preview
#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    ScrollView {
      VStack(spacing: 12) {
        WhatIsHaloFiSection()
        OurMissionSection()
        MeetTheTeamButtonSection(onTap: {})
        DataSecuritySection()
        LegalAndSupportSection(
          onTermsTap: {},
          onPrivacyTap: {},
          onContactSupportTap: {},
          onBugReportTap: {}
        )
        AppVersionSection()
      }
      .padding()
    }
  }
}

//
//  TeamView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Team View
struct TeamView: View {
  @Environment(\.dismiss) private var dismiss
  
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 0) {
        ModalHeader(title: "Meet the Team", onDone: { dismiss() })
        
        // Content
        ScrollView {
          VStack(spacing: 20) {
            // Andrew Babin
            InfoCard {
              VStack(alignment: .leading, spacing: 12) {
                Text("Andrew Babin")
                  .font(.title2)
                  .fontWeight(.semibold)
                  .foregroundColor(.white)
                
                Text("Co-Founder")
                  .font(.headline)
                  .foregroundColor(.teal)
                
                Text("Diagnosed with Stargardt's disease at a young age, Andrew has never let vision loss define him. He embraced technology as a way to adapt and thrive, building a career in finance over the past five years. Passionate about AI, he explores how it can support daily life and create meaningful impact.")
                  .font(.body)
                  .foregroundColor(.white)
                  .multilineTextAlignment(.leading)
                  .lineLimit(nil)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            
            // Liam Haley
            InfoCard {
              VStack(alignment: .leading, spacing: 12) {
                Text("Liam Haley")
                  .font(.title2)
                  .fontWeight(.semibold)
                  .foregroundColor(.white)
                
                Text("Co-Founder")
                  .font(.headline)
                  .foregroundColor(.teal)
                
                Text("Liam is an AI developer and previous fintech startup founder. His 15-year friendship with Andrew gave him deep perspective on the challenges of vision loss. While not visually impaired himself, he brings technical expertise and startup experience to the mission of Halo Fi.")
                  .font(.body)
                  .foregroundColor(.white)
                  .multilineTextAlignment(.leading)
                  .lineLimit(nil)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            
            // Together Section
            InfoCard {
              VStack(alignment: .leading, spacing: 12) {
                Text("Together")
                  .font(.title2)
                  .fontWeight(.semibold)
                  .foregroundColor(.white)
                
                Text("Andrew and Liam combined their professional skills and life experiences to create Halo Fi—a voice-first financial assistant designed to bring clarity and accessibility to personal finance. Their vision is simple: build a tool that has no downside, only benefits, and can help hundreds of thousands gain clearer access to their finances.")
                  .font(.body)
                  .foregroundColor(.white)
                  .multilineTextAlignment(.leading)
                  .lineLimit(nil)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 20)
        }
        
        Spacer()
      }
    }
  }
}

// MARK: - Preview
#Preview {
  TeamView()
}

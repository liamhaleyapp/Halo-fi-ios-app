//
//  WebSocketTestView.swift
//  Halo-fi-IOS
//
//  Debug view for testing WebSocket connections with echo servers
//

import SwiftUI

#if DEBUG

struct WebSocketTestView: View {
  private let testManager = WebSocketTestManager.shared
  @State private var testMessage = "Hello, Echo Server!"
  @State private var selectedServer: WebSocketTestServer = .echoWebSocketOrg
  
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          // Connection Status
          VStack(spacing: 8) {
            Text("Connection Status")
              .font(.headline)
            
            HStack {
              Circle()
                .fill(testManager.connectionStatus.color)
                .frame(width: 12, height: 12)
              
              Text(testManager.connectionStatus.displayText)
                .font(.subheadline)
            }
          }
          .padding()
          .background(Color(.systemGray6))
          .cornerRadius(10)
          
          // Server Selection
          VStack(alignment: .leading, spacing: 8) {
            Text("Test Server")
              .font(.headline)
            
            Picker("Server", selection: $selectedServer) {
              Text(WebSocketTestServer.echoWebSocketOrg.name).tag(WebSocketTestServer.echoWebSocketOrg)
              Text(WebSocketTestServer.postmanEcho.name).tag(WebSocketTestServer.postmanEcho)
            }
            .pickerStyle(.segmented)
            .disabled(testManager.isConnected)
          }
          .padding()
          .background(Color(.systemGray6))
          .cornerRadius(10)
          
          // Connection Controls
          HStack(spacing: 12) {
            Button(action: {
              Task {
                do {
                  try await testManager.connectToEchoServer(selectedServer)
                } catch {
                  print("Connection error: \(error)")
                }
              }
            }) {
              Text("Connect")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(testManager.isConnected)
            
            Button(action: {
              testManager.disconnect()
            }) {
              Text("Disconnect")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(!testManager.isConnected)
          }
          
          // Test Message Input
          VStack(alignment: .leading, spacing: 8) {
            Text("Test Message")
              .font(.headline)
            
            TextField("Enter test message", text: $testMessage)
              .textFieldStyle(.roundedBorder)
            
            Button(action: {
              Task {
                do {
                  try await testManager.sendTestMessage(testMessage)
                } catch {
                  print("Send error: \(error)")
                }
              }
            }) {
              Text("Send Message")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(!testManager.isConnected)
          }
          .padding()
          .background(Color(.systemGray6))
          .cornerRadius(10)
          
          // Test Voice Message Formats
          if testManager.isConnected {
            VStack(alignment: .leading, spacing: 8) {
              Text("Test Voice Message Formats")
                .font(.headline)
              
              VStack(spacing: 8) {
                Button("Test VoiceStartMessage") {
                  Task {
                    do {
                      try await testManager.testVoiceStartMessage(
                        sessionId: UUID().uuidString,
                        userId: "test-user"
                      )
                    } catch {
                      print("Error: \(error)")
                    }
                  }
                }
                .buttonStyle(.bordered)
                
                Button("Test VoicePingMessage") {
                  Task {
                    do {
                      try await testManager.testVoicePingMessage()
                    } catch {
                      print("Error: \(error)")
                    }
                  }
                }
                .buttonStyle(.bordered)
                
                Button("Test VoiceEndMessage") {
                  Task {
                    do {
                      try await testManager.testVoiceEndMessage(
                        sessionId: UUID().uuidString
                      )
                    } catch {
                      print("Error: \(error)")
                    }
                  }
                }
                .buttonStyle(.bordered)
                
                Button("Test VoiceAudioMessage") {
                  Task {
                    do {
                      let dummyAudio = Data([0x00, 0x01, 0x02, 0x03])
                      try await testManager.testVoiceAudioMessage(
                        sessionId: UUID().uuidString,
                        audioData: dummyAudio
                      )
                    } catch {
                      print("Error: \(error)")
                    }
                  }
                }
                .buttonStyle(.bordered)
              }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
          }
          
          // Run Test Suite
          Button(action: {
            Task {
              await testManager.runTestSuite()
            }
          }) {
            Text("Run Full Test Suite")
              .frame(maxWidth: .infinity)
              .padding()
              .background(Color.purple)
              .foregroundColor(.white)
              .cornerRadius(8)
          }
          .disabled(!testManager.isConnected)
          
          // Last Received Message
          if !testManager.lastReceivedMessage.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("Last Received Message")
                .font(.headline)
              
              Text(testManager.lastReceivedMessage)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
          }
          
          // Test Logs
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Test Logs")
                .font(.headline)
              
              Spacer()
              
              Button("Clear") {
                testManager.clearLogs()
              }
              .font(.caption)
            }
            
            ScrollView {
              VStack(alignment: .leading, spacing: 4) {
                ForEach(testManager.testLogs, id: \.self) { log in
                  Text(log)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
            }
            .frame(height: 200)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(8)
          }
          .padding()
          .background(Color(.systemGray6))
          .cornerRadius(10)
        }
        .padding()
      }
      .navigationTitle("WebSocket Test")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

#Preview {
  WebSocketTestView()
}

#endif

//
//  AgentChatView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/17/25.
//

import SwiftUI

struct AgentChatView: View {
  @ObservedObject private var agentManager = AgentWebSocketManager.shared
  @State private var messageText = ""
  @State private var messages: [ChatMessage] = []
  @State private var showingError = false
  @State private var errorMessage = ""
  @State private var lastProcessedResponse: String?
  @State private var lastProcessedError: String?
  @State private var lastProcessedAck: String?
  
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Connection Status Bar
        connectionStatusBar
        
        // Messages List
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
              ForEach(messages) { message in
                ChatBubble(message: message)
                  .id(message.id)
              }
              
              // Show streaming text if active
              if agentManager.isStreaming && !agentManager.streamingText.isEmpty {
                ChatBubble(message: ChatMessage(
                  id: UUID(),
                  text: agentManager.streamingText,
                  isFromUser: false,
                  timestamp: Date()
                ))
                .id("streaming")
              }
            }
            .padding()
          }
          .onChange(of: messages.count) { _ in
            withAnimation {
              proxy.scrollTo(messages.last?.id ?? messages.first?.id, anchor: .bottom)
            }
          }
          .onChange(of: agentManager.streamingText) { _ in
            withAnimation {
              proxy.scrollTo("streaming", anchor: .bottom)
            }
          }
        }
        
        // Input Area
        messageInputArea
      }
      .navigationTitle("AI Agent Chat")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: disconnect) {
            Text("Disconnect")
              .font(.caption)
          }
          .disabled(!agentManager.isConnected)
        }
      }
    }
    .onAppear {
      setupCallbacks()
      Task {
        await connect()
      }
    }
    .onDisappear {
      disconnect()
    }
    .onChange(of: agentManager.lastAgentResponse) { newResponse in
      if let response = newResponse, response != lastProcessedResponse {
        lastProcessedResponse = response
        addMessage(text: response, isFromUser: false)
      }
    }
    .onChange(of: agentManager.lastError) { newError in
      if let error = newError, error != lastProcessedError {
        lastProcessedError = error
        addMessage(text: "Error: \(error)", isFromUser: false)
      }
    }
    .onChange(of: agentManager.connectionAckMessage) { newAck in
      if let ack = newAck, ack != lastProcessedAck {
        lastProcessedAck = ack
        addSystemMessage(ack)
      }
    }
    .alert("Connection Error", isPresented: $showingError) {
      Button("OK") { }
    } message: {
      Text(errorMessage)
    }
  }
  
  // MARK: - Views
  
  private var connectionStatusBar: some View {
    HStack {
      Circle()
        .fill(agentManager.isConnected ? Color.green : Color.red)
        .frame(width: 8, height: 8)
      
      Text(agentManager.isConnected ? "Connected" : "Disconnected")
        .font(.caption)
        .foregroundColor(.secondary)
      
      if let sessionId = agentManager.currentSessionId {
        Text("• Session: \(sessionId.prefix(8))...")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity)
    .background(Color(.systemGray6))
  }
  
  private var messageInputArea: some View {
    HStack(spacing: 12) {
      TextField("Type your message...", text: $messageText, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(1...4)
        .disabled(!agentManager.isConnected || agentManager.isStreaming)
      
      Button(action: sendMessage) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.title2)
          .foregroundColor(agentManager.isConnected && !messageText.isEmpty && !agentManager.isStreaming ? .blue : .gray)
      }
      .disabled(!agentManager.isConnected || messageText.isEmpty || agentManager.isStreaming)
    }
    .padding()
    .background(Color(.systemBackground))
  }
  
  // MARK: - Actions
  
  private func connect() async {
    do {
      try await agentManager.connect()
      addSystemMessage("Connected to AI agent")
    } catch {
      await MainActor.run {
        errorMessage = error.localizedDescription
        showingError = true
      }
    }
  }
  
  private func disconnect() {
    agentManager.disconnect()
    addSystemMessage("Disconnected from AI agent")
  }
  
  private func sendMessage() {
    guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    
    let userMessage = messageText
    messageText = ""
    
    // Add user message to chat
    addMessage(text: userMessage, isFromUser: true)
    
    // Send to agent
    Task {
      do {
        // Example context - you can customize this
        let context: [String: AnyCodable] = [
          "platform": AnyCodable("ios"),
          "timestamp": AnyCodable(Date().timeIntervalSince1970)
        ]
        
        try await agentManager.sendMessage(userMessage, context: context)
      } catch {
        await MainActor.run {
          errorMessage = "Failed to send message: \(error.localizedDescription)"
          showingError = true
        }
      }
    }
  }
  
  private func setupCallbacks() {
    // Callbacks are now handled via @Published properties and onChange modifiers
    // This avoids the need to capture self in closures
  }
  
  private func addMessage(text: String, isFromUser: Bool) {
    withAnimation {
      messages.append(ChatMessage(
        id: UUID(),
        text: text,
        isFromUser: isFromUser,
        timestamp: Date()
      ))
    }
  }
  
  private func addSystemMessage(_ text: String) {
    withAnimation {
      messages.append(ChatMessage(
        id: UUID(),
        text: text,
        isFromUser: false,
        isSystem: true,
        timestamp: Date()
      ))
    }
  }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
  let id: UUID
  let text: String
  let isFromUser: Bool
  var isSystem: Bool = false
  let timestamp: Date
}

// MARK: - Chat Bubble View

struct ChatBubble: View {
  let message: ChatMessage
  
  var body: some View {
    HStack {
      if message.isFromUser {
        Spacer()
      }
      
      VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
        Text(message.text)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(
            message.isFromUser
              ? Color.blue
              : (message.isSystem ? Color.gray.opacity(0.2) : Color(.systemGray5))
          )
          .foregroundColor(
            message.isFromUser
              ? .white
              : (message.isSystem ? .secondary : .primary)
          )
          .cornerRadius(18)
        
        Text(message.timestamp, style: .time)
          .font(.caption2)
          .foregroundColor(.secondary)
      }
      .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.isFromUser ? .trailing : .leading)
      
      if !message.isFromUser {
        Spacer()
      }
    }
  }
}

#Preview {
  AgentChatView()
}

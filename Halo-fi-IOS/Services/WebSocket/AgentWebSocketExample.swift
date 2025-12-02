//
//  AgentWebSocketExample.swift
//  Halo-fi-IOS
//
//  Example usage of AgentWebSocketManager
//

import Foundation

// MARK: - Example Usage

/*
 Example of how to use the AgentWebSocketManager:
 
 // 1. Connect to the WebSocket
 Task {
     do {
         try await AgentWebSocketManager.shared.connect()
         print("Connected to agent WebSocket")
     } catch {
         print("Failed to connect: \(error)")
     }
 }
 
 // 2. Set up callbacks (optional)
 AgentWebSocketManager.shared.onAgentResponse = { response in
     print("Received agent response: \(response.message)")
     print("Status: \(response.status)")
 }
 
 AgentWebSocketManager.shared.onStreamChunk = { chunk in
     print("Stream chunk: \(chunk.chunk)")
     if chunk.complete == true {
         print("Stream complete!")
     }
 }
 
 AgentWebSocketManager.shared.onError = { error in
     print("Error: \(error.error) (Code: \(error.code))")
 }
 
 AgentWebSocketManager.shared.onConnectionAck = { ack in
     print("Connection acknowledged: \(ack.message)")
     print("Session ID: \(ack.sessionId ?? "none")")
 }
 
 // 3. Send a message to the agent
 Task {
     do {
         try await AgentWebSocketManager.shared.sendMessage(
             "What is my account balance?",
             context: ["user_id": AnyCodable("user-123")]
         )
     } catch {
         print("Failed to send message: \(error)")
     }
 }
 
 // 4. Disconnect when done
 AgentWebSocketManager.shared.disconnect()
 
 // You can also observe the published properties:
 // - isConnected: Bool
 // - connectionStatus: ConnectionStatus
 // - lastAgentResponse: String?
 // - lastError: String?
 // - currentSessionId: String?
 */


//
//  WebSocketConnect.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/17/25.
//

import Foundation

public enum WebSocketConnectionError: Error {
  case connectionError
  case transportError
  case encodingError
  case decodingError
  case disconnected
  case closed
}

public final class WebSocketConnection<Incoming: Decodable & Sendable, Outgoing: Encodable & Sendable>: NSObject, Sendable {
  private let webSocketTask: URLSessionWebSocketTask
  
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  
  internal init(
    webSocketTask: URLSessionWebSocketTask,
    encoder: JSONEncoder = JSONEncoder(),
    decoder: JSONDecoder = JSONDecoder()
  ) {
    self.webSocketTask = webSocketTask
    self.encoder = encoder
    self.decoder = decoder
    
    super.init()
    
    webSocketTask.resume()
  }
  
  deinit {
    webSocketTask.cancel(with: .goingAway, reason: nil)
  }
  
  private func receiveSingleMessage() async throws -> Incoming {
    let result = try await webSocketTask.receive()

    switch result {
    case let .data(messageData):
      Logger.debug("WebSocket RECV (binary): \(messageData.count) bytes")
      if let raw = String(data: messageData, encoding: .utf8) {
        Logger.debug("WebSocket RECV raw: \(raw)")
      }

      guard let message = try? decoder.decode(Incoming.self, from: messageData) else {
        Logger.error("WebSocket: Failed to decode binary message")
        throw WebSocketConnectionError.decodingError
      }

      return message

    case let .string(text):
      Logger.debug("WebSocket RECV (text): \(text)")

      guard
        let messageData = text.data(using: .utf8),
        let message = try? decoder.decode(Incoming.self, from: messageData)
      else {
        Logger.error("WebSocket: Failed to decode text message")
        throw WebSocketConnectionError.decodingError
      }

      return message

    @unknown default:
      assertionFailure("Unknown message type")

      webSocketTask.cancel(with: .unsupportedData, reason: nil)
      throw WebSocketConnectionError.decodingError
    }
  }
}

extension WebSocketConnection {
  func send(_ message: Outgoing) async throws {
    guard let messageData = try? encoder.encode(message) else {
      Logger.error("WebSocket: Failed to encode message")
      throw WebSocketConnectionError.encodingError
    }

    // Log the outgoing JSON
    let jsonString = String(data: messageData, encoding: .utf8) ?? ""
    Logger.debug("WebSocket SEND: \(jsonString)")

    do {
      // Send as STRING instead of binary data (servers typically expect JSON as text)
      try await webSocketTask.send(.string(jsonString))
      Logger.debug("WebSocket: Message sent successfully")
    } catch {
      Logger.error("WebSocket: Send failed - \(error)")
      throw WebSocketConnectionError.transportError
    }
  }
  
  func receive() async throws -> Incoming {
    return try await receiveSingleMessage()
  }
  
  func close() {
    webSocketTask.cancel(with: .goingAway, reason: nil)
  }
}

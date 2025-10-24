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
    switch try await webSocketTask.receive() {
    case let .data(messageData):
      guard let message = try? decoder.decode(Incoming.self, from: messageData) else {
        throw WebSocketConnectionError.decodingError
      }
      
      return message
      
    case let .string(text):
      guard
        let messageData = text.data(using: .utf8),
        let message = try? decoder.decode(Incoming.self, from: messageData)
      else {
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
      throw WebSocketConnectionError.encodingError
    }
    
    do {
      try await webSocketTask.send(.data(messageData))
    } catch {
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

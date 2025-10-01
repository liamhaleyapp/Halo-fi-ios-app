//
//  ConnectionStatus.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Connection Status Enum
enum ConnectionStatus {
    case connected
    case disconnected
    case pending
    
    var color: Color {
        switch self {
        case .connected: return .green
        case .disconnected: return .red
        case .pending: return .orange
        }
    }
    
    var displayText: String {
        switch self {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .pending: return "Pending"
        }
    }
}

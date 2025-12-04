//
//  EmptyResponse.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/4/25.
//

import Foundation

// MARK: - Empty Response
/// Empty response type for DELETE operations and other endpoints that return no body
struct EmptyResponse: Codable {
    init() {}
}



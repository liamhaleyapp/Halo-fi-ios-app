//
//  ManualAccountService.swift
//  Halo-fi-IOS
//
//  CRUD calls for /bank/manual-accounts. Mirrors BankService's pattern
//  (NetworkService injection, AuthError → BankError mapping) so callers
//  can handle errors uniformly.
//

import Foundation

@MainActor
final class ManualAccountService {
  static let shared = ManualAccountService()

  private let networkService: NetworkServiceProtocol

  init(networkService: NetworkServiceProtocol = NetworkService.shared) {
    self.networkService = networkService
  }

  private static let encoder: JSONEncoder = JSONEncoder()

  // MARK: - List

  func list() async throws -> [ManualAccount] {
    do {
      // Backend returns a top-level JSON array; wrap in a Codable
      // alias so authenticatedRequest's generic decode works.
      return try await networkService.authenticatedRequest(
        endpoint: APIEndpoints.Bank.manualAccounts,
        method: .GET,
        body: nil,
        responseType: [ManualAccount].self
      )
    } catch let authError as AuthError {
      if case .serverError(let code, _) = authError, code == 404 {
        return []
      }
      throw authError
    }
  }

  // MARK: - Create

  func create(_ payload: ManualAccountCreateRequest) async throws -> ManualAccount {
    let body = try Self.encoder.encode(payload)
    return try await networkService.authenticatedRequest(
      endpoint: APIEndpoints.Bank.manualAccounts,
      method: .POST,
      body: body,
      responseType: ManualAccount.self
    )
  }

  // MARK: - Update

  func update(id: UUID, payload: ManualAccountUpdateRequest) async throws -> ManualAccount {
    let body = try Self.encoder.encode(payload)
    return try await networkService.authenticatedRequest(
      endpoint: APIEndpoints.Bank.manualAccount(id.uuidString),
      method: .PATCH,
      body: body,
      responseType: ManualAccount.self
    )
  }

  // MARK: - Delete

  func delete(id: UUID) async throws {
    _ = try await networkService.authenticatedRequest(
      endpoint: APIEndpoints.Bank.manualAccount(id.uuidString),
      method: .DELETE,
      body: nil,
      responseType: SuccessResponse.self
    )
  }

  private struct SuccessResponse: Codable {
    let success: Bool
  }
}

//
//  WorkProfileService.swift
//  Halo-fi-IOS
//
//  Reads and writes the user's SSI work-context profile — drives
//  the BWE/IRWE classifier on the backend. Captured Phase 3a.
//
//  All bools are tri-state (Optional<Bool>):
//    - nil   = user hasn't been asked yet
//    - true  = explicit yes
//    - false = explicit no
//
//  Setting `commutes_to_workplace = false` server-side clears
//  `commute_methods` + `commute_days` automatically — the iOS form
//  just needs to send the bool change, dependent fields take care
//  of themselves.
//

import Foundation

struct WorkProfile: Codable, Equatable {
  var commutesToWorkplace: Bool?
  var commuteMethods: String?
  var commuteDays: String?
  var hasWorkServiceAnimal: Bool?
  var requiresWorkMeds: Bool?
  var usesAssistiveTechForWork: Bool?
  var workProfileCompletedAt: String?
  var fieldsUnset: Int

  enum CodingKeys: String, CodingKey {
    case commutesToWorkplace = "commutes_to_workplace"
    case commuteMethods = "commute_methods"
    case commuteDays = "commute_days"
    case hasWorkServiceAnimal = "has_work_service_animal"
    case requiresWorkMeds = "requires_work_meds"
    case usesAssistiveTechForWork = "uses_assistive_tech_for_work"
    case workProfileCompletedAt = "work_profile_completed_at"
    case fieldsUnset = "fields_unset"
  }

  static let empty = WorkProfile(
    commutesToWorkplace: nil,
    commuteMethods: nil,
    commuteDays: nil,
    hasWorkServiceAnimal: nil,
    requiresWorkMeds: nil,
    usesAssistiveTechForWork: nil,
    workProfileCompletedAt: nil,
    fieldsUnset: 4
  )
}

/// Partial-update payload for PUT /users/work-profile. Only fields
/// the caller wants to change should be set; the backend treats
/// every nil as "leave it alone" (different from the GET response
/// where nil means "value is null in the DB").
struct WorkProfileUpdate: Encodable {
  var commutesToWorkplace: Bool?
  var commuteMethods: String?
  var commuteDays: String?
  var hasWorkServiceAnimal: Bool?
  var requiresWorkMeds: Bool?
  var usesAssistiveTechForWork: Bool?

  enum CodingKeys: String, CodingKey {
    case commutesToWorkplace = "commutes_to_workplace"
    case commuteMethods = "commute_methods"
    case commuteDays = "commute_days"
    case hasWorkServiceAnimal = "has_work_service_animal"
    case requiresWorkMeds = "requires_work_meds"
    case usesAssistiveTechForWork = "uses_assistive_tech_for_work"
  }

  /// Encode only non-nil fields so unspecified keys don't show up in
  /// the JSON as `"key": null` and accidentally clear server values.
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(commutesToWorkplace, forKey: .commutesToWorkplace)
    try c.encodeIfPresent(commuteMethods, forKey: .commuteMethods)
    try c.encodeIfPresent(commuteDays, forKey: .commuteDays)
    try c.encodeIfPresent(hasWorkServiceAnimal, forKey: .hasWorkServiceAnimal)
    try c.encodeIfPresent(requiresWorkMeds, forKey: .requiresWorkMeds)
    try c.encodeIfPresent(usesAssistiveTechForWork, forKey: .usesAssistiveTechForWork)
  }
}

@MainActor
final class WorkProfileService {
  static let shared = WorkProfileService()
  private init() {}

  func fetch() async throws -> WorkProfile {
    try await NetworkService.shared.authenticatedRequest(
      endpoint: APIEndpoints.User.workProfile,
      method: .GET,
      responseType: WorkProfile.self
    )
  }

  func update(_ patch: WorkProfileUpdate) async throws -> WorkProfile {
    let body = try JSONEncoder().encode(patch)
    return try await NetworkService.shared.authenticatedRequest(
      endpoint: APIEndpoints.User.workProfile,
      method: .PUT,
      body: body,
      responseType: WorkProfile.self
    )
  }
}

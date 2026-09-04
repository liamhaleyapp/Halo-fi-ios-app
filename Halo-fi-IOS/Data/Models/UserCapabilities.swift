//
//  UserCapabilities.swift
//  Halo-fi-IOS
//
//  The ONE gating object every screen reads. Computed server-side from the
//  benefits profile (GET /auth/me and GET /users/me/capabilities) so views
//  never reason about raw `hasSsi` / `isBlind` booleans again.
//
//  Hard product rule: no BWE math for anyone whose statutory-blindness
//  status is not confirmed by SSA. `bweLocked` renders BWE features
//  visible-but-locked, with the BPQY walkthrough as the unlock path.
//

import Foundation

enum ExpenseType: String, Codable, Equatable {
    case bwe
    case irwe
    case none

    /// Spoken/visible name of the default work-expense type.
    var title: String {
        switch self {
        case .bwe: return "Blind Work Expense"
        case .irwe: return "Impairment-Related Work Expense"
        case .none: return "Work expense"
        }
    }
}

struct UserCapabilities: Codable, Equatable {
    var showsBenefitsLane: Bool
    var showsResourceCounter: Bool
    var showsSSDILane: Bool
    var expenseType: ExpenseType
    var bweLocked: Bool
    var coupleLimits: Bool
    var deemingReferral: Bool
    var showsWorkIncentives: Bool
    /// Echoed by the backend so the UI can explain WHY something is locked.
    var benefitType: String?
    var blindStatus: String?

    /// Safe default before the profile has loaded: nothing benefit-specific
    /// is shown, nothing is computed.
    static let none = UserCapabilities(
        showsBenefitsLane: false,
        showsResourceCounter: false,
        showsSSDILane: false,
        expenseType: .none,
        bweLocked: false,
        coupleLimits: false,
        deemingReferral: false,
        showsWorkIncentives: false,
        benefitType: nil,
        blindStatus: nil
    )

    init(
        showsBenefitsLane: Bool,
        showsResourceCounter: Bool,
        showsSSDILane: Bool,
        expenseType: ExpenseType,
        bweLocked: Bool,
        coupleLimits: Bool,
        deemingReferral: Bool,
        showsWorkIncentives: Bool,
        benefitType: String?,
        blindStatus: String?
    ) {
        self.showsBenefitsLane = showsBenefitsLane
        self.showsResourceCounter = showsResourceCounter
        self.showsSSDILane = showsSSDILane
        self.expenseType = expenseType
        self.bweLocked = bweLocked
        self.coupleLimits = coupleLimits
        self.deemingReferral = deemingReferral
        self.showsWorkIncentives = showsWorkIncentives
        self.benefitType = benefitType
        self.blindStatus = blindStatus
    }

    /// Tolerant decode: a missing or unknown field never fails the whole
    /// profile response — it just falls back to the safe default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showsBenefitsLane = try c.decodeIfPresent(Bool.self, forKey: .showsBenefitsLane) ?? false
        showsResourceCounter = try c.decodeIfPresent(Bool.self, forKey: .showsResourceCounter) ?? false
        showsSSDILane = try c.decodeIfPresent(Bool.self, forKey: .showsSSDILane) ?? false
        expenseType = (try? c.decodeIfPresent(ExpenseType.self, forKey: .expenseType)) ?? .none
        bweLocked = try c.decodeIfPresent(Bool.self, forKey: .bweLocked) ?? false
        coupleLimits = try c.decodeIfPresent(Bool.self, forKey: .coupleLimits) ?? false
        deemingReferral = try c.decodeIfPresent(Bool.self, forKey: .deemingReferral) ?? false
        showsWorkIncentives = try c.decodeIfPresent(Bool.self, forKey: .showsWorkIncentives) ?? false
        benefitType = try c.decodeIfPresent(String.self, forKey: .benefitType)
        blindStatus = try c.decodeIfPresent(String.self, forKey: .blindStatus)
    }

    /// Human wording for the statutory-blindness verification state.
    var blindStatusTitle: String {
        switch blindStatus {
        case "yes": return "Verified by Social Security"
        case "no": return "Not listed as statutorily blind"
        case "unverified": return "Unverified — check your award letter or BPQY"
        default: return "Not answered yet"
        }
    }
}

/// The raw benefits-profile answers, as the backend stores them. Optional
/// everywhere: an unanswered question is nil, never a guessed default.
struct BenefitsProfile: Codable, Equatable {
    var getsSsaPayment: String?
    var benefitType: String?
    var blindStatus: String?
    var householdType: String?
    var householdSize: Int?
    var workStatus: String?
    var hasAbleAccount: Bool?
    var stateCode: String?
    var ssiEligibleCouple: Bool?
    var accessMode: String?
    var promiseAcceptedAt: String?
    /// WP6 — how the field office likes to receive the monthly package.
    var fieldOfficeChannel: String?
    var fieldOfficeNotes: String?

    static let empty = BenefitsProfile()

    init(
        getsSsaPayment: String? = nil,
        benefitType: String? = nil,
        blindStatus: String? = nil,
        householdType: String? = nil,
        householdSize: Int? = nil,
        workStatus: String? = nil,
        hasAbleAccount: Bool? = nil,
        stateCode: String? = nil,
        ssiEligibleCouple: Bool? = nil,
        accessMode: String? = nil,
        promiseAcceptedAt: String? = nil,
        fieldOfficeChannel: String? = nil,
        fieldOfficeNotes: String? = nil
    ) {
        self.getsSsaPayment = getsSsaPayment
        self.benefitType = benefitType
        self.blindStatus = blindStatus
        self.householdType = householdType
        self.householdSize = householdSize
        self.workStatus = workStatus
        self.hasAbleAccount = hasAbleAccount
        self.stateCode = stateCode
        self.ssiEligibleCouple = ssiEligibleCouple
        self.accessMode = accessMode
        self.promiseAcceptedAt = promiseAcceptedAt
        self.fieldOfficeChannel = fieldOfficeChannel
        self.fieldOfficeNotes = fieldOfficeNotes
    }

    enum CodingKeys: String, CodingKey {
        case getsSsaPayment = "gets_ssa_payment"
        case benefitType = "benefit_type"
        case blindStatus = "blind_status"
        case householdType = "household_type"
        case householdSize = "household_size"
        case workStatus = "work_status"
        case hasAbleAccount = "has_able_account"
        case stateCode = "state_code"
        case ssiEligibleCouple = "ssi_eligible_couple"
        case accessMode = "access_mode"
        case promiseAcceptedAt = "promise_accepted_at"
        case fieldOfficeChannel = "field_office_channel"
        case fieldOfficeNotes = "field_office_notes"
    }

    /// The answer currently stored for a profile field, as the option id
    /// the question tree uses (so Settings can show "Married" not "spouse").
    func answer(for field: String) -> String? {
        switch field {
        case "gets_ssa_payment": return getsSsaPayment
        case "benefit_type": return benefitType
        case "blind_status": return blindStatus
        case "household_type": return householdType
        case "household_size": return householdSize.map { $0 >= 4 ? "4" : String($0) }
        case "work_status": return workStatus
        case "has_able_account": return hasAbleAccount.map { $0 ? "yes" : "no" }
        case "state_code": return stateCode
        case "ssi_eligible_couple": return ssiEligibleCouple.map { $0 ? "yes" : "no" }
        case "access_mode": return accessMode
        case "promise_accepted_at": return promiseAcceptedAt == nil ? nil : "accepted"
        default: return nil
        }
    }
}

/// A partial update for PATCH /users/me. Only fields that are set are
/// encoded, so one question at a time can be persisted idempotently.
struct BenefitsProfilePatch: Encodable, Equatable {
    var getsSsaPayment: String?
    var benefitType: String?
    var blindStatus: String?
    var householdType: String?
    var householdSize: Int?
    var workStatus: String?
    var hasAbleAccount: Bool?
    var stateCode: String?
    var ssiEligibleCouple: Bool?
    var accessMode: String?
    var promiseAcceptedAt: Date?
    var fieldOfficeChannel: String?
    var fieldOfficeNotes: String?

    static let none = BenefitsProfilePatch()

    var isEmpty: Bool { self == .none }

    enum CodingKeys: String, CodingKey {
        case getsSsaPayment = "gets_ssa_payment"
        case benefitType = "benefit_type"
        case blindStatus = "blind_status"
        case householdType = "household_type"
        case householdSize = "household_size"
        case workStatus = "work_status"
        case hasAbleAccount = "has_able_account"
        case stateCode = "state_code"
        case ssiEligibleCouple = "ssi_eligible_couple"
        case accessMode = "access_mode"
        case promiseAcceptedAt = "promise_accepted_at"
        case fieldOfficeChannel = "field_office_channel"
        case fieldOfficeNotes = "field_office_notes"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(getsSsaPayment, forKey: .getsSsaPayment)
        try c.encodeIfPresent(benefitType, forKey: .benefitType)
        try c.encodeIfPresent(blindStatus, forKey: .blindStatus)
        try c.encodeIfPresent(householdType, forKey: .householdType)
        try c.encodeIfPresent(householdSize, forKey: .householdSize)
        try c.encodeIfPresent(workStatus, forKey: .workStatus)
        try c.encodeIfPresent(hasAbleAccount, forKey: .hasAbleAccount)
        try c.encodeIfPresent(stateCode, forKey: .stateCode)
        try c.encodeIfPresent(ssiEligibleCouple, forKey: .ssiEligibleCouple)
        try c.encodeIfPresent(accessMode, forKey: .accessMode)
        if let when = promiseAcceptedAt {
            try c.encode(ISO8601DateFormatter().string(from: when), forKey: .promiseAcceptedAt)
        }
        try c.encodeIfPresent(fieldOfficeChannel, forKey: .fieldOfficeChannel)
        try c.encodeIfPresent(fieldOfficeNotes, forKey: .fieldOfficeNotes)
    }
}

/// Shape of GET /users/me/capabilities.
struct CapabilitiesResponse: Codable {
    let capabilities: UserCapabilities
    let benefitsProfile: BenefitsProfile?

    enum CodingKeys: String, CodingKey {
        case capabilities
        case benefitsProfile = "benefits_profile"
    }
}

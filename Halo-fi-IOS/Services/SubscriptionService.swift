// Subscription state belongs to the authenticated app session.
import Foundation
import RevenueCat
import StoreKit
import SwiftUI

@MainActor
protocol SubscriptionClient: AnyObject {
  var appUserID: String? { get }
  func logIn(_ userID: String) async throws
  func logOut() async throws
  func packages() async throws -> [Package]
  func customerInfo() async throws -> CustomerInfo
  func purchase(_ package: Package) async throws -> (CustomerInfo, Bool)
  func restore() async throws -> CustomerInfo
  func introEligible(_ productID: String) async -> Bool
}

@MainActor
final class RevenueCatSubscriptionClient: SubscriptionClient {
  var appUserID: String? { !UITestArchetype.isActive && Purchases.isConfigured ? Purchases.shared.appUserID : nil }
  func logIn(_ userID: String) async throws {
    guard !UITestArchetype.isActive, Purchases.isConfigured else { throw SubscriptionError.identityUnavailable }
    _ = try await Purchases.shared.logIn(userID)
  }
  func logOut() async throws {
    guard !UITestArchetype.isActive, Purchases.isConfigured, !Purchases.shared.isAnonymous else { return }
    _ = try await Purchases.shared.logOut()
  }
  func packages() async throws -> [Package] { try await Purchases.shared.offerings().current?.availablePackages ?? [] }
  func customerInfo() async throws -> CustomerInfo { try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent) }
  func purchase(_ package: Package) async throws -> (CustomerInfo, Bool) {
    let result = try await Purchases.shared.purchase(package: package)
    return (result.customerInfo, result.userCancelled)
  }
  func restore() async throws -> CustomerInfo { try await Purchases.shared.restorePurchases() }
  func introEligible(_ productID: String) async -> Bool {
    await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: [productID])[productID]?.status == .eligible
  }
}

/// Serializes all checkout operations and identity changes, including logout.
/// Once a purchase starts, the SDK keeps its identity until the operation returns.
@Observable @MainActor
final class SubscriptionSession {
  static let shared = SubscriptionSession()
  private(set) var userID: String?
  private(set) var revision = UUID()
  private var generation: UUID
  private var readyRevision: UUID?
  private let lifetime: SessionLifetime
  private let client: SubscriptionClient
  private var tail: Task<Void, Never>?

  init(client: SubscriptionClient? = nil, lifetime: SessionLifetime = .shared) {
    self.client = client ?? RevenueCatSubscriptionClient()
    self.lifetime = lifetime
    self.generation = lifetime.current
  }

  var isReady: Bool {
    userID != nil && readyRevision == revision && lifetime.isCurrent(generation)
  }

  func isCurrent(_ expected: UUID) -> Bool {
    revision == expected && lifetime.isCurrent(generation)
  }

  private func check(_ expected: UUID) throws {
    guard isCurrent(expected) else { throw CancellationError() }
  }

  private func enqueue<T>(_ operation: @escaping @MainActor () async throws -> T) -> Task<T, Error> {
    let previous = tail
    let task = Task { @MainActor in
      await previous?.value
      return try await operation()
    }
    tail = Task { @MainActor in _ = await task.result }
    return task
  }

  func selectUser(_ userID: String?) {
    guard self.userID != userID || !lifetime.isCurrent(generation) else { return }
    self.userID = userID
    generation = lifetime.current
    revision = UUID()
    readyRevision = nil
    let expected = revision
    let task = enqueue { [self] in
      try check(expected)
      if let userID {
        try await bind(userID, expected: expected)
      } else {
        try await client.logOut()
      }
    }
    Task { _ = await task.result }
  }

  private func bind(_ userID: String, expected: UUID) async throws {
    if client.appUserID != userID { try await client.logIn(userID) }
    try check(expected)
    guard client.appUserID == userID else { throw SubscriptionError.identityUnavailable }
    readyRevision = expected
  }

  func perform<T>(expectedRevision: UUID? = nil, canStart: @escaping @MainActor () -> Bool = { true }, _ operation: @escaping @MainActor (SubscriptionClient) async throws -> T) async throws -> T {
    let expected = expectedRevision ?? revision
    try check(expected)
    guard let userID else { throw SubscriptionError.identityUnavailable }
    return try await enqueue { [self] in
      try check(expected)
      guard canStart() else { throw CancellationError() }
      try await bind(userID, expected: expected)
      guard canStart() else { throw CancellationError() }
      let result = try await operation(client)
      try check(expected)
      return result
    }.value
  }

  func prepare() async throws { try await perform { _ in () } }
}

@Observable @MainActor
class SubscriptionService {
  private struct State {
    var subscription: SubscriptionStatus = .none
    var entitlements: Set<String> = []
    var info: CustomerInfo?
    var pending: String?
    var error: String?
  }
  private var state = State()
  private var stateOwner: UUID?
  private var cacheRevision = UUID()
  private var infoRevision = UUID()
  private var loadingOwner: UUID?
  private var loadingCount = 0
  private let session: SubscriptionSession
  private let pendingChange: @MainActor (String) async throws -> String?

  var currentSubscription: SubscriptionStatus {
    get { stateIsCurrent ? state.subscription : .none }
    set { stateOwner = session.revision; state.subscription = newValue }
  }
  var activeEntitlements: Set<String> {
    get { stateIsCurrent ? state.entitlements : [] }
    set { stateOwner = session.revision; state.entitlements = newValue }
  }
  var customerInfo: CustomerInfo? {
    get { stateIsCurrent ? state.info : nil }
    set { stateOwner = session.revision; state.info = newValue }
  }
  var pendingPlanChange: String? { stateIsCurrent ? state.pending : nil }
  var statusError: String? { stateIsCurrent ? state.error : nil }
  var isLoading: Bool {
    get { loadingOwner == session.revision && loadingCount > 0 }
    set { loadingOwner = session.revision; loadingCount = newValue ? 1 : 0 }
  }
  var canPresentPaywall: Bool { session.isReady }
  var sessionRevision: UUID { session.revision }
  func isCurrentSession(_ revision: UUID) -> Bool { session.isCurrent(revision) }
  private var stateIsCurrent: Bool { stateOwner == session.revision && session.isCurrent(session.revision) }
  var availablePackages: [Package] = []
  var availableProducts: [StoreProduct] = []

  init(session: SubscriptionSession? = nil, pendingChange: (@MainActor (String) async throws -> String?)? = nil) {
    self.session = session ?? .shared
    self.pendingChange = pendingChange ?? Self.storeKitPendingChange
  }

  private func check(_ owner: UUID, _ cache: UUID) throws {
    guard session.isCurrent(owner), cacheRevision == cache else { throw CancellationError() }
  }

  private func startLoading(_ owner: UUID) {
    if loadingOwner != owner { loadingOwner = owner; loadingCount = 0 }
    loadingCount += 1
  }
  private func stopLoading(_ owner: UUID, _ cache: UUID) {
    guard session.isCurrent(owner), cacheRevision == cache, loadingOwner == owner else { return }
    loadingCount = max(0, loadingCount - 1)
  }

  func initialize() async {
    let owner = session.revision, cache = cacheRevision
    startLoading(owner)
    defer { stopLoading(owner, cache) }
    do {
      let packages = try await session.perform { try await $0.packages() }
      try check(owner, cache)
      availablePackages = packages
      availableProducts = packages.map(\.storeProduct)
    } catch { /* Customer status must still refresh if offerings fail. */ }
    guard (try? check(owner, cache)) != nil else { return }
    await checkSubscriptionStatus()
  }

  func checkoutPlans(expectedRevision: UUID, canStart: @escaping @MainActor () -> Bool) async throws -> [SubscriptionPlan] {
    try await session.perform(expectedRevision: expectedRevision, canStart: canStart) { client in
      let packages = try await client.packages()
      var plans: [SubscriptionPlan] = []
      for package in packages where package.storeProduct.subscriptionPeriod != nil {
        let eligible = package.storeProduct.introductoryDiscount != nil
          ? await client.introEligible(package.storeProduct.productIdentifier) : false
        plans.append(SubscriptionPlan(package: package, introEligible: eligible))
      }
      return plans
    }
  }

  func prepareForPaywall() async -> Bool {
    let owner = session.revision, cache = cacheRevision
    do {
      try await session.prepare()
      try check(owner, cache)
      return canPresentPaywall
    } catch {
      recordFailure(owner: owner, cache: cache)
      return false
    }
  }

  func checkSubscriptionStatus() async {
    let owner = session.revision, cache = cacheRevision
    do {
      let info = try await session.perform { try await $0.customerInfo() }
      try check(owner, cache)
      apply(info)
      await checkPendingPlanChange()
    } catch {
      recordFailure(owner: owner, cache: cache)
    }
  }

  private func recordFailure(owner: UUID, cache: UUID) {
    guard (try? check(owner, cache)) != nil else { return }
    if !stateIsCurrent { state = State(); stateOwner = owner }
    state.error = "Could not refresh your subscription. Please try again."
  }

  private func apply(_ info: CustomerInfo) {
    if !stateIsCurrent { state = State() }
    stateOwner = session.revision
    infoRevision = UUID()
    state.info = info
    state.error = nil
    state.pending = nil
    state.entitlements = Set(info.entitlements.active.keys)
    if state.entitlements.isEmpty {
      state.subscription = info.entitlements.all.isEmpty ? .none : .expired
    } else if state.entitlements.contains(where: { $0.lowercased().contains("max") }) {
      state.subscription = .max
    } else if state.entitlements.contains(where: { $0.lowercased().contains("pro") }) {
      state.subscription = .pro
    } else if state.entitlements.contains(where: { $0.lowercased().contains("basic") }) {
      state.subscription = .basic
    } else {
      state.subscription = .active
    }
  }

  func purchase(package: Package, expectedRevision: UUID? = nil, canStart: @escaping @MainActor () -> Bool = { true }) async throws -> (success: Bool, customerInfo: CustomerInfo?) {
    let owner = expectedRevision ?? session.revision, cache = cacheRevision
    try check(owner, cache)
    startLoading(owner)
    defer { stopLoading(owner, cache) }
    do {
      let (info, cancelled) = try await session.perform(expectedRevision: owner, canStart: canStart) { try await $0.purchase(package) }
      try check(owner, cache)
      if cancelled { throw SubscriptionError.purchaseCancelled }
      apply(info)
      await checkPendingPlanChange()
      try check(owner, cache)
      return (true, info)
    } catch let error as ErrorCode where error == .productAlreadyPurchasedError {
      try check(owner, cache)
      try await restorePurchases(expectedRevision: owner, canStart: canStart)
      try check(owner, cache)
      if hasActiveSubscription { return (true, customerInfo) }
      throw SubscriptionError.purchaseFailed(error.localizedDescription)
    } catch {
      try check(owner, cache)
      if let code = error as? ErrorCode {
        if code == .paymentPendingError { throw SubscriptionError.paymentPending }
        if code == .purchaseCancelledError { throw SubscriptionError.purchaseCancelled }
      }
      if error is SubscriptionError || error is CancellationError { throw error }
      throw SubscriptionError.purchaseFailed(error.localizedDescription)
    }
  }

  func purchase(productId: String) async throws -> (success: Bool, customerInfo: CustomerInfo?) {
    guard let package = availablePackages.first(where: { $0.storeProduct.productIdentifier == productId }) else {
      throw SubscriptionError.productNotFound
    }
    return try await purchase(package: package)
  }

  func restorePurchases(expectedRevision: UUID? = nil, canStart: @escaping @MainActor () -> Bool = { true }) async throws {
    let owner = expectedRevision ?? session.revision, cache = cacheRevision
    try check(owner, cache)
    startLoading(owner)
    defer { stopLoading(owner, cache) }
    do {
      let info = try await session.perform(expectedRevision: owner, canStart: canStart) { try await $0.restore() }
      try check(owner, cache)
      apply(info)
      await checkPendingPlanChange()
      try check(owner, cache)
    } catch {
      try check(owner, cache)
      if error is CancellationError { throw error }
      throw SubscriptionError.restoreFailed(error.localizedDescription)
    }
  }

  func checkIntroEligibility(productId: String) async -> Bool {
    (try? await session.perform { await $0.introEligible(productId) }) ?? false
  }

  private var activeEntitlement: EntitlementInfo? {
    customerInfo?.entitlements.active.values.max {
      func rank(_ info: EntitlementInfo) -> Int {
        let name = info.identifier.lowercased()
        return name.contains("max") ? 3 : name.contains("pro") ? 2 : 1
      }
      return rank($0) < rank($1)
    }
  }
  var renewalDate: Date? { activeEntitlement?.expirationDate }
  var willRenew: Bool { activeEntitlement?.willRenew ?? false }
  var hasActiveSubscription: Bool { currentSubscription != .none && currentSubscription != .expired }

  func checkPendingPlanChange() async {
    let owner = session.revision, cache = cacheRevision, infoVersion = infoRevision
    guard let productID = activeEntitlement?.productIdentifier else { return }
    do {
      let pending = try await pendingChange(productID)
      try check(owner, cache)
      guard infoRevision == infoVersion else { return }
      state.pending = pending.map(planDisplayName)
    } catch { /* Preserve known state when StoreKit is temporarily unavailable. */ }
  }

  private static func storeKitPendingChange(_ productID: String) async throws -> String? {
    let products = try await Product.products(for: [productID])
    let statuses = try await products.first?.subscription?.status ?? []
    for status in statuses {
      guard case .verified(let info) = status.renewalInfo else { continue }
      if let next = info.autoRenewPreference, next != productID { return next }
    }
    return nil
  }

  private func planDisplayName(from productId: String) -> String {
    let id = productId.lowercased()
    let tier = id.contains("max") ? "Max" : id.contains("pro") ? "Pro" : id.contains("basic") ? "Basic" : "Unknown"
    return "\(tier) \(id.contains("yearly") ? "Yearly" : "Monthly")"
  }

  func clearCachedState() {
    cacheRevision = UUID()
    infoRevision = UUID()
    state = State()
    stateOwner = session.revision
    isLoading = false
  }
}

// MARK: - Supporting Types

enum SubscriptionStatus {
  case none
  case basic
  case pro
  case max
  case active  // Generic active subscription
  case expired
  
  var displayName: String {
    switch self {
    case .none: return "None"
    case .basic: return "Basic"
    case .pro: return "Pro"
    case .max: return "Max"
    case .active: return "Active"
    case .expired: return "Expired"
    }
  }
}

enum SubscriptionError: LocalizedError {
  case purchaseCancelled
  case paymentPending
  case productNotFound
  case productUnavailable
  case purchaseFailed(String)
  case restoreFailed(String)
  case identityUnavailable
  case unknown
  
  var errorDescription: String? {
    switch self {
    case .paymentPending:
      return "Your purchase is awaiting Apple approval or payment confirmation. Follow Apple’s instructions, then check your subscription again."
    case .purchaseCancelled:
      return "Purchase was cancelled"
    case .productNotFound:
      return "Product not found"
    case .productUnavailable:
      return "Product is not available at this time"
    case .purchaseFailed(let message):
      return "Purchase failed: \(message)"
    case .restoreFailed(let message):
      return "Restore failed: \(message)"
    case .identityUnavailable:
      return "Please sign in again to access subscriptions."
    case .unknown:
      return "An unknown error occurred"
    }
  }
}

extension SubscriptionService {
  static var previewActivePro: SubscriptionService {
    let service = SubscriptionService()
    
    // Fake a Pro subscription
    service.currentSubscription = .pro
    service.activeEntitlements = ["pro"]
    service.customerInfo = nil
    service.isLoading = false
    service.availablePackages = []
    service.availableProducts = []
    
    return service
  }
  
  static var previewNone: SubscriptionService {
    let service = SubscriptionService()
    service.currentSubscription = .none
    service.activeEntitlements = []
    service.isLoading = false
    return service
  }
}

/// Store-provided terms for a selectable auto-renewing plan.
struct SubscriptionPlan: Identifiable {
  let package: Package
  let title: String
  let detail: String
  let terms: String
  var id: String { package.identifier }

  init(package: Package, introEligible: Bool) {
    self.package = package
    let product = package.storeProduct
    title = product.localizedTitle.isEmpty ? "Subscription" : product.localizedTitle
    detail = product.localizedDescription
    let recurring = "\(product.localizedPriceString) every \(Self.period(product.subscriptionPeriod))"
    if introEligible, let offer = product.introductoryDiscount {
      terms = Self.offerTerms(price: offer.localizedPriceString, mode: offer.paymentMode,
                              period: offer.subscriptionPeriod, count: offer.numberOfPeriods,
                              recurring: recurring)
    } else {
      terms = "\(recurring)."
    }
  }

  static func period(_ period: RevenueCat.SubscriptionPeriod?, multiplier: Int = 1) -> String {
    guard let period else { return "billing period" }
    let count = period.value * multiplier
    let unit: String
    switch period.unit {
    case .day: unit = "day"
    case .week: unit = "week"
    case .month: unit = "month"
    case .year: unit = "year"
    @unknown default: unit = "billing period"
    }
    return count == 1 ? "1 \(unit)" : "\(count) \(unit)s"
  }

  static func offerTerms(price: String, mode: StoreProductDiscount.PaymentMode,
                         period: RevenueCat.SubscriptionPeriod, count: Int, recurring: String) -> String {
    switch mode {
    case .freeTrial:
      return "Free for \(Self.period(period, multiplier: count)), then \(recurring)."
    case .payUpFront:
      return "\(price) for the first \(Self.period(period, multiplier: count)), then \(recurring)."
    case .payAsYouGo:
      return "\(price) every \(Self.period(period)) for \(count) \(count == 1 ? "payment" : "payments"), then \(recurring)."
    @unknown default:
      return "\(recurring). Apple will confirm any available offer before you subscribe."
    }
  }
}

/// Owns checkout work independently of SwiftUI's view lifecycle. Closing a
/// screen invalidates queued admission; an already-started SDK purchase runs
/// to completion under its original identity even if the screen disappears.
@Observable @MainActor
final class SubscriptionCheckout {
  private let service: SubscriptionService
  let owner: UUID
  private var active = true
  private(set) var plans: [SubscriptionPlan] = []
  var selectedID: String?
  private(set) var isBusy = false
  private(set) var loaded = false
  private(set) var catalogError: String?
  private(set) var message: String?
  private(set) var awaitingConfirmation = false
  private(set) var completed = false

  init(service: SubscriptionService) {
    self.service = service
    owner = service.sessionRevision
  }

  var isCurrent: Bool { active && service.isCurrentSession(owner) }
  var selectedPlan: SubscriptionPlan? { plans.first { $0.id == selectedID } }
  var canPurchase: Bool { isCurrent && !isBusy && !awaitingConfirmation && selectedPlan != nil && !completed }

  func close() { active = false }

  func load() async {
    guard isCurrent, !isBusy, !completed else { return }
    isBusy = true
    defer { isBusy = false }
    catalogError = nil
    do {
      let result = try await service.checkoutPlans(expectedRevision: owner, canStart: { [self] in isCurrent })
      guard isCurrent else { return }
      plans = result
      if !plans.contains(where: { $0.id == selectedID }) { selectedID = nil }
      if plans.isEmpty { catalogError = "No subscription plans are available right now. You can try again or restore an existing purchase." }
    } catch {
      guard isCurrent else { return }
      plans = []
      selectedID = nil
      catalogError = "Could not load subscription plans. Please try again. You can still restore an existing purchase."
    }
    loaded = true
  }

  func purchase() async {
    guard canPurchase, let plan = selectedPlan else { return }
    isBusy = true
    message = nil
    defer { isBusy = false }
    do {
      _ = try await service.purchase(package: plan.package, expectedRevision: owner, canStart: { [self] in isCurrent })
      guard isCurrent else { return }
      if service.hasActiveSubscription {
        completed = true
      } else {
        awaitingConfirmation = true
        message = "Apple returned your purchase, but active access has not been confirmed yet. Check your subscription again."
      }
    } catch {
      guard isCurrent else { return }
      if case SubscriptionError.purchaseCancelled = error {
        message = "Purchase cancelled."
      } else if case SubscriptionError.paymentPending = error {
        awaitingConfirmation = true
        message = error.localizedDescription
      } else {
        awaitingConfirmation = true
        message = "We could not confirm the purchase result. Check your subscription before trying again."
      }
    }
  }

  func restore() async {
    guard isCurrent, !isBusy, !completed else { return }
    isBusy = true
    message = nil
    defer { isBusy = false }
    do {
      try await service.restorePurchases(expectedRevision: owner, canStart: { [self] in isCurrent })
      guard isCurrent else { return }
      if service.hasActiveSubscription { completed = true }
      else { message = "No active subscription was found to restore for this Apple Account." }
    } catch {
      guard isCurrent else { return }
      message = "Could not restore purchases. Please try again."
    }
  }

  func checkStatus() async {
    guard isCurrent, !isBusy, !completed else { return }
    isBusy = true
    defer { isBusy = false }
    await service.checkSubscriptionStatus()
    guard isCurrent else { return }
    if let error = service.statusError {
      message = error
    } else if service.hasActiveSubscription {
      completed = true
    } else {
      // A deferred Apple transaction can remain pending after a successful
      // status fetch. Do not turn a status check into another purchase prompt.
      message = "No active subscription is confirmed yet. If Apple is still processing your purchase, check again after approval. You can also restore purchases."
    }
  }
}

import XCTest
import RevenueCat
import StoreKit
@testable import Halo_fi_IOS

private final class SessionStubProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SessionIsolationTests: XCTestCase {
    private struct Reply: Codable { let ok: Bool }
    private let refresh = #"{"success":true,"access_token":"A-new","refresh_token":"A-new-refresh","token_type":"bearer","expires_in":3600}"#

    private func makeService() -> (NetworkService, MockTokenStorage, SessionLifetime, URLSession) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionStubProtocol.self]
        let session = URLSession(configuration: config)
        let store = MockTokenStorage()
        store.saveTokens(accessToken: "A-old", refreshToken: "A-refresh", expiresIn: 0)
        let lifetime = SessionLifetime()
        return (NetworkService(baseURL: "https://review.invalid", session: session, tokenStorage: store, lifetime: lifetime), store, lifetime, session)
    }

    func testRefreshCannotOverwriteNewAccount() async throws {
        let (service, store, lifetime, session) = makeService()
        defer { session.invalidateAndCancel() }
        let refresh = refresh
        var requests = 0
        SessionStubProtocol.handler = { request in
            if request.url!.path == "/auth/refresh-token" {
                lifetime.invalidate { store.saveTokens(accessToken: "B-token", refreshToken: "B-refresh", expiresIn: 3600) }
                return (200, refresh)
            }
            requests += 1
            return (401, "{}")
        }
        do {
            let _: Reply = try await service.authenticatedRequest(endpoint: "/resource", responseType: Reply.self)
            XCTFail("Old request must be cancelled")
        } catch is CancellationError { }
        XCTAssertEqual(store.accessToken, "B-token")
        XCTAssertEqual(requests, 1, "No retry from the old account")
    }

    func testSuccessfulRefreshDoesNotTurnServerFailureIntoSessionExpiry() async throws {
        let (service, store, _, session) = makeService()
        defer { session.invalidateAndCancel() }
        let refresh = refresh
        let expired = expectation(description: "Session remains valid")
        expired.isInverted = true
        let observer = NotificationCenter.default.addObserver(forName: .sessionExpired, object: nil, queue: nil) { _ in expired.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }
        SessionStubProtocol.handler = { request in
            if request.url!.path == "/auth/refresh-token" { return (200, refresh) }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer A-old" ? (401, "{}") : (500, "{}")
        }
        do {
            let _: Reply = try await service.authenticatedRequest(endpoint: "/resource", responseType: Reply.self)
            XCTFail("Expected server failure")
        } catch AuthError.serverError(let code, _) { XCTAssertEqual(code, 500) }
        XCTAssertEqual(store.accessToken, "A-new")
        await fulfillment(of: [expired], timeout: 0.1)
    }

    func testLateSuccessfulResponseIsDiscardedAfterSignOut() async throws {
        let (service, store, lifetime, session) = makeService()
        defer { session.invalidateAndCancel() }
        SessionStubProtocol.handler = { _ in
            lifetime.invalidate { store.clearTokens() }
            return (200, #"{"ok":true}"#)
        }
        do {
            let _: Reply = try await service.authenticatedRequest(endpoint: "/resource", responseType: Reply.self)
            XCTFail("Old data must not be returned")
        } catch is CancellationError { }
        XCTAssertNil(store.accessToken)
    }

    func testRawDownloadCannotRefreshSignedOutCredentials() async throws {
        let (service, store, lifetime, session) = makeService()
        defer { session.invalidateAndCancel() }
        let refresh = refresh
        SessionStubProtocol.handler = { request in
            if request.url!.path == "/auth/refresh-token" {
                lifetime.invalidate { store.clearTokens() }
                return (200, refresh)
            }
            return (401, "{}")
        }
        do {
            _ = try await service.authenticatedRawDataRequest(endpoint: "/export")
            XCTFail("Old download must be cancelled")
        } catch is CancellationError { }
        XCTAssertNil(store.accessToken)
    }
}

private actor DeferredBudgetService: BudgetServiceProtocol {
    let requested: XCTestExpectation
    private var continuation: CheckedContinuation<BudgetSuggestion?, Error>?
    init(requested: XCTestExpectation) { self.requested = requested }
    func getOverview(userTz: String?) async throws -> BudgetOverview { throw URLError(.notConnectedToInternet) }
    func fetchSuggestion() async throws -> BudgetSuggestion? {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            requested.fulfill()
        }
    }
    func complete(_ suggestion: BudgetSuggestion) { continuation?.resume(returning: suggestion); continuation = nil }
    func updateMonthlyIncome(_ update: MonthlyIncomeUpdate) async throws { }
    func updateCategoryLimit(categoryId: String, limitAmount: Double) async throws { }
    func dismissSuggestion() async throws { }
    func scaleBudget(percent: Double?, totalCents: Int?) async throws { }
    func applySuggestion() async throws { }
    func addCategory(code: String, limitAmount: Double) async throws { }
    func deleteCategory(categoryId: String) async throws { }
}

extension SessionIsolationTests {
    @MainActor
    func testBudgetClearRemovesIncomeAndRejectsLateSuggestion() async throws {
        let requested = expectation(description: "Old suggestion request started")
        let service = DeferredBudgetService(requested: requested)
        let manager = BudgetDataManager(service: service)
        let suggestion = BudgetSuggestion(id: "old-user", generatedAt: nil, windowDays: 90,
            totalIncomeCents: 100000, totalLimitCents: 80000, proposal: ["food": 80000],
            medians: [:], source: "history", appliedAt: nil)
        manager.suggestion = suggestion
        manager.incomeSummary = IncomeSummary(month: "2026-09", sources: [], workIncome: [],
            workIncomeGrossCents: 100000, workIncomeNetCents: 80000, benefitCents: 0,
            paychecksNeedingGross: 0, labels: [])
        let request = Task { await manager.fetchSuggestion() }
        await fulfillment(of: [requested], timeout: 2)
        manager.clearAllData()
        XCTAssertNil(manager.incomeSummary)
        XCTAssertNil(manager.suggestion)
        await service.complete(suggestion)
        await request.value
        XCTAssertNil(manager.suggestion, "A response from the previous session must be discarded")
    }
}

extension SessionIsolationTests {
    func testDeviceRevocationUsesCapturedAccountAfterSignInChanges() async throws {
        let (network, store, lifetime, session) = makeService()
        defer { session.invalidateAndCancel() }
        let request = try network.prepareDeviceRevocation(deviceToken: "device-token")
        lifetime.invalidate { store.saveTokens(accessToken: "B-token", refreshToken: "B-refresh", expiresIn: 3600) }
        SessionStubProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/me/devices/device-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer A-old")
            return (200, #"{"ok":true}"#)
        }
        try await network.sendDeviceRevocation(request)
        XCTAssertEqual(store.accessToken, "B-token")
    }

    @MainActor
    func testSignOutRevokesAfterLateRegistrationWithoutRestoringRegisteredFlag() async throws {
        let (network, store, lifetime, session) = makeService()
        defer { session.invalidateAndCancel() }
        let suite = "PushIsolation-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("device-token", forKey: "pushDeviceToken.v1")
        let started = expectation(description: "Registration in flight")
        let finish = DispatchSemaphore(value: 0)
        var deleted = false
        var unregistered = false
        SessionStubProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer A-old")
            if request.httpMethod == "POST" {
                started.fulfill()
                XCTAssertEqual(finish.wait(timeout: .now() + 5), .success)
            } else {
                XCTAssertEqual(request.httpMethod, "DELETE")
                deleted = true
            }
            return (200, #"{"ok":true}"#)
        }
        let registrar = PushRegistrar(network: network, defaults: defaults, lifetime: lifetime,
                                      unregister: { unregistered = true })
        registrar.isSignedIn = true
        await fulfillment(of: [started], timeout: 2)
        let cleanup = registrar.forget()
        lifetime.invalidate { store.clearTokens() }
        XCTAssertFalse(registrar.isRegistered)
        XCTAssertTrue(unregistered)
        finish.signal()
        await cleanup.value
        XCTAssertTrue(deleted)
        XCTAssertFalse(registrar.isRegistered)
        XCTAssertFalse(registrar.isSignedIn)
        XCTAssertNil(store.accessToken)
    }

    func testRevocationFailureDoesNotRefreshDepartedCredentials() async throws {
        let (network, store, lifetime, session) = makeService()
        defer { session.invalidateAndCancel() }
        let request = try network.prepareDeviceRevocation(deviceToken: "device-token")
        lifetime.invalidate { store.saveTokens(accessToken: "B-token", refreshToken: "B-refresh", expiresIn: 3600) }
        var requests = 0
        SessionStubProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.httpMethod, "DELETE")
            return (401, "{}")
        }
        do {
            try await network.sendDeviceRevocation(request)
            XCTFail("Expected revocation failure")
        } catch { }
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(store.accessToken, "B-token")
    }
}

import UserNotifications

private final class DeferredNotificationCenter: NotificationScheduling {
    var delegate: (any UNUserNotificationCenterDelegate)?
    var requests: [UNNotificationRequest] = []
    var delivered: [String] = ["old-delivered"]
    let pauseAt: String
    let paused: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    init(pauseAt: String, paused: XCTestExpectation) { self.pauseAt = pauseAt; self.paused = paused }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { requests }
    func authorizationStatus() async -> UNAuthorizationStatus {
        if pauseAt == "permission" { await pause() }
        return .authorized
    }
    func add(_ request: UNNotificationRequest) async throws {
        if pauseAt == "add" { await pause() }
        requests.append(request)
    }
    private func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            paused.fulfill()
        }
    }
    func resume() { continuation?.resume(); continuation = nil }
    func removePendingNotificationRequests(withIdentifiers ids: [String]) { requests.removeAll { ids.contains($0.identifier) } }
    func removeDeliveredNotifications(withIdentifiers ids: [String]) { delivered.removeAll { ids.contains($0) } }
    func removeAllPendingNotificationRequests() { requests = [] }
    func removeAllDeliveredNotifications() { delivered = [] }
}

extension SessionIsolationTests {
    @MainActor
    func testSignOutClearsNotificationsAndRejectsPausedPlans() async throws {
        for phase in ["permission", "add"] {
            let paused = expectation(description: "Paused at \(phase)")
            let center = DeferredNotificationCenter(pauseAt: phase, paused: paused)
            let suite = "NotificationIsolation-\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let lifetime = SessionLifetime()
            var signedIn = true
            let scheduler = ReminderNotificationScheduler(center: center, defaults: defaults, lifetime: lifetime,
                                                           signedIn: { signedIn }, pushRegistered: { false })
            let card = AttentionCard(id: "old-account-card", kind: "bill_confirm", priority: 40,
                                     title: "Review a bill", line: "", actionType: "confirm_bill",
                                     payload: AttentionCard.Payload(), learn: false, tone: "watch")
            let task = Task { await scheduler.plan(cards: [card]) }
            await fulfillment(of: [paused], timeout: 2)
            defaults.set(Data("old-history".utf8), forKey: "notificationHistory.v2")
            ReminderNotificationScheduler.pendingAttentionOpen = true
            signedIn = false
            scheduler.clearForSignOut()
            lifetime.invalidate { }
            center.resume()
            await task.value
            XCTAssertTrue(center.requests.isEmpty)
            XCTAssertTrue(center.delivered.isEmpty)
            XCTAssertNil(defaults.data(forKey: "notificationHistory.v2"))
            XCTAssertFalse(ReminderNotificationScheduler.pendingAttentionOpen)
        }
    }
}

// MARK: - Subscription identity and delayed SDK responses

@MainActor
private final class DeferredSubscriptionClient: SubscriptionClient {
    var appUserID: String? = "$anonymous"
    var events: [String] = []
    var info: CustomerInfo!
    var loginAction: ((String) async throws -> Void)?
    var logoutAction: (() async throws -> Void)?
    var infoAction: (() async throws -> CustomerInfo)?
    var purchaseAction: (() async throws -> (CustomerInfo, Bool))?
    var restoreAction: (() async throws -> CustomerInfo)?
    var offeringsFail = false
    var offeredPackages: [Package] = []

    func logIn(_ userID: String) async throws {
        events.append("login:\(userID)")
        try await loginAction?(userID)
        appUserID = userID
    }
    func logOut() async throws {
        events.append("logout")
        try await logoutAction?()
        appUserID = "$anonymous"
    }
    func packages() async throws -> [Package] {
        if offeringsFail { throw URLError(.notConnectedToInternet) }
        return offeredPackages
    }
    func customerInfo() async throws -> CustomerInfo {
        events.append("info:\(appUserID ?? "nil")")
        if let infoAction { return try await infoAction() }
        return info
    }
    func purchase(_ package: Package) async throws -> (CustomerInfo, Bool) {
        events.append("purchase:\(appUserID ?? "nil")")
        if let purchaseAction { return try await purchaseAction() }
        return (info, false)
    }
    func restore() async throws -> CustomerInfo {
        if let restoreAction { return try await restoreAction() }
        return info
    }
    func introEligible(_ productID: String) async -> Bool { false }
}

extension SessionIsolationTests {
    private func subscriptionInfo(_ tier: String = "pro", renewing: Bool = true) throws -> CustomerInfo {
        let product = "halofi_\(tier)_monthly"
        let details: [String: Any] = [
            "purchase_date": "2026-09-01T00:00:00Z", "expires_date": "2099-10-01T00:00:00Z",
            "period_type": "normal", "is_sandbox": false, "store": "app_store",
            "unsubscribe_detected_at": renewing ? NSNull() : "2026-09-05T00:00:00Z"
        ]
        let payload: [String: Any] = [
            "request_date": "2026-09-07T00:00:00Z",
            "subscriber": [
                "first_seen": "2026-09-01T00:00:00Z", "original_app_user_id": "anonymous-original",
                "subscriptions": [product: details], "non_subscriptions": [:],
                "entitlements": [tier: ["product_identifier": product,
                    "purchase_date": "2026-09-01T00:00:00Z", "expires_date": "2099-10-01T00:00:00Z"]]
            ]
        ]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CustomerInfo.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    @MainActor
    func testSubscriptionLogoutCannotRunAfterNewAccountLogin() async throws {
        let client = DeferredSubscriptionClient(), lifetime = SessionLifetime()
        let session = SubscriptionSession(client: client, lifetime: lifetime)
        session.selectUser("A")
        try await session.prepare()
        let started = expectation(description: "Logout started")
        var resume: CheckedContinuation<Void, Never>?
        client.logoutAction = {
            await withCheckedContinuation { resume = $0; started.fulfill() }
        }
        lifetime.invalidate { }
        session.selectUser(nil)
        await fulfillment(of: [started], timeout: 2)
        lifetime.invalidate { }
        session.selectUser("B")
        let ready = Task { try await session.prepare() }
        XCTAssertFalse(session.isReady)
        resume?.resume()
        try await ready.value
        XCTAssertEqual(client.events, ["login:A", "logout", "login:B"])
        XCTAssertEqual(client.appUserID, "B")
        XCTAssertTrue(session.isReady)
    }

    @MainActor
    func testSlowOldSubscriptionLoginCannotBecomeCurrentIdentity() async throws {
        let client = DeferredSubscriptionClient(), lifetime = SessionLifetime()
        let session = SubscriptionSession(client: client, lifetime: lifetime)
        let started = expectation(description: "Old login started")
        var resume: CheckedContinuation<Void, Never>?
        client.loginAction = { id in
            if id == "A" { await withCheckedContinuation { resume = $0; started.fulfill() } }
        }
        session.selectUser("A")
        await fulfillment(of: [started], timeout: 2)
        lifetime.invalidate { }
        session.selectUser(nil)
        lifetime.invalidate { }
        session.selectUser("B")
        let ready = Task { try await session.prepare() }
        resume?.resume()
        try await ready.value
        XCTAssertEqual(client.events, ["login:A", "login:B"])
        XCTAssertEqual(client.appUserID, "B")
    }

    @MainActor
    func testSubscriptionStateHidesImmediatelyAndRejectsLateOldResponse() async throws {
        let client = DeferredSubscriptionClient(), lifetime = SessionLifetime()
        client.info = try subscriptionInfo("max")
        let session = SubscriptionSession(client: client, lifetime: lifetime)
        let service = SubscriptionService(session: session, pendingChange: { _ in nil })
        session.selectUser("A")
        await service.checkSubscriptionStatus()
        XCTAssertEqual(service.currentSubscription, .max)
        let started = expectation(description: "Old customer request started")
        var resume: CheckedContinuation<CustomerInfo, Never>?
        client.infoAction = { await withCheckedContinuation { resume = $0; started.fulfill() } }
        let old = Task { await service.checkSubscriptionStatus() }
        await fulfillment(of: [started], timeout: 2)
        lifetime.invalidate { }
        session.selectUser("B")
        XCTAssertEqual(service.currentSubscription, .none)
        XCTAssertTrue(service.activeEntitlements.isEmpty)
        XCTAssertNil(service.customerInfo)
        resume?.resume(returning: client.info)
        await old.value
        XCTAssertEqual(service.currentSubscription, .none)
        XCTAssertNil(service.statusError)
    }

    @MainActor
    func testClearingSubscriptionCacheInvalidatesInFlightResponse() async throws {
        let client = DeferredSubscriptionClient()
        // Use a dedicated session without touching the app singleton.
        let ownedSession = SubscriptionSession(client: client, lifetime: SessionLifetime())
        let service = SubscriptionService(session: ownedSession, pendingChange: { _ in nil })
        ownedSession.selectUser("A")
        let info = try subscriptionInfo()
        let started = expectation(description: "Fetch started")
        var resume: CheckedContinuation<CustomerInfo, Never>?
        client.infoAction = { await withCheckedContinuation { resume = $0; started.fulfill() } }
        let request = Task { await service.checkSubscriptionStatus() }
        await fulfillment(of: [started], timeout: 2)
        service.clearCachedState()
        resume?.resume(returning: info)
        await request.value
        XCTAssertNil(service.customerInfo)
        XCTAssertFalse(service.hasActiveSubscription)
    }

    @MainActor
    func testSubscriptionRefreshFailurePreservesPlanAndCancellationTerm() async throws {
        let client = DeferredSubscriptionClient()
        client.info = try subscriptionInfo("max", renewing: false)
        let session = SubscriptionSession(client: client, lifetime: SessionLifetime())
        let service = SubscriptionService(session: session, pendingChange: { _ in nil })
        session.selectUser("A")
        await service.checkSubscriptionStatus()
        XCTAssertEqual(service.currentSubscription, .max)
        XCTAssertFalse(service.willRenew)
        XCTAssertNotNil(service.renewalDate)
        client.infoAction = { throw URLError(.notConnectedToInternet) }
        await service.checkSubscriptionStatus()
        XCTAssertEqual(service.currentSubscription, .max)
        XCTAssertTrue(service.hasActiveSubscription)
        XCTAssertNotNil(service.statusError)
    }

    @MainActor
    func testOfferingsFailureStillRefreshesRestoredAccountSubscription() async throws {
        let client = DeferredSubscriptionClient()
        client.appUserID = "old-cached-account"
        client.info = try subscriptionInfo()
        client.offeringsFail = true
        let session = SubscriptionSession(client: client, lifetime: SessionLifetime())
        let service = SubscriptionService(session: session, pendingChange: { _ in nil })
        session.selectUser("restored-account")
        await service.initialize()
        XCTAssertEqual(client.events, ["login:restored-account", "info:restored-account"])
        XCTAssertEqual(service.currentSubscription, .pro)
        XCTAssertFalse(service.isLoading)
    }

    @MainActor
    func testFailedSubscriptionIdentityDoesNotReadPreviousCustomersInfo() async throws {
        let client = DeferredSubscriptionClient()
        client.appUserID = "A"
        client.loginAction = { _ in throw URLError(.notConnectedToInternet) }
        let session = SubscriptionSession(client: client, lifetime: SessionLifetime())
        let service = SubscriptionService(session: session, pendingChange: { _ in nil })
        session.selectUser("B")
        let ready = await service.prepareForPaywall()
        XCTAssertFalse(ready)
        await service.checkSubscriptionStatus()
        XCTAssertFalse(service.hasActiveSubscription)
        XCTAssertNotNil(service.statusError)
        XCTAssertFalse(client.events.contains(where: { $0.hasPrefix("info:") }))
    }

    @MainActor
    func testOldRestoreCannotClearNewRestoreLoadingOrApplyItsPlan() async throws {
        let client = DeferredSubscriptionClient(), lifetime = SessionLifetime()
        let session = SubscriptionSession(client: client, lifetime: lifetime)
        let service = SubscriptionService(session: session, pendingChange: { _ in nil })
        session.selectUser("A")
        let firstStarted = expectation(description: "A restore started")
        let secondStarted = expectation(description: "B restore started")
        var first: CheckedContinuation<CustomerInfo, Never>?
        var second: CheckedContinuation<CustomerInfo, Never>?
        client.restoreAction = {
            await withCheckedContinuation { continuation in
                if client.appUserID == "A" { first = continuation; firstStarted.fulfill() }
                else { second = continuation; secondStarted.fulfill() }
            }
        }
        let old = Task { try await service.restorePurchases() }
        await fulfillment(of: [firstStarted], timeout: 2)
        lifetime.invalidate { }
        session.selectUser("B")
        let new = Task { try await service.restorePurchases() }
        first?.resume(returning: try subscriptionInfo("max"))
        await fulfillment(of: [secondStarted], timeout: 2)
        do { try await old.value; XCTFail("Old restore must be discarded") }
        catch is CancellationError { }
        XCTAssertTrue(service.isLoading)
        XCTAssertEqual(service.currentSubscription, .none)
        second?.resume(returning: try subscriptionInfo("basic"))
        try await new.value
        XCTAssertFalse(service.isLoading)
        XCTAssertEqual(service.currentSubscription, .basic)
    }
}

extension SessionIsolationTests {
    @MainActor
    func testLatePendingPlanLookupCannotOverwriteNewCustomerInfo() async throws {
        let client = DeferredSubscriptionClient()
        client.info = try subscriptionInfo("max")
        let session = SubscriptionSession(client: client, lifetime: SessionLifetime())
        let started = expectation(description: "First StoreKit lookup started")
        var resume: CheckedContinuation<String?, Never>?
        let service = SubscriptionService(session: session, pendingChange: { productID in
            if productID.contains("max") {
                return await withCheckedContinuation { resume = $0; started.fulfill() }
            }
            return nil
        })
        session.selectUser("A")
        let first = Task { await service.checkSubscriptionStatus() }
        await fulfillment(of: [started], timeout: 2)
        client.info = try subscriptionInfo("basic")
        await service.checkSubscriptionStatus()
        resume?.resume(returning: "halofi_pro_yearly")
        await first.value
        XCTAssertEqual(service.currentSubscription, .basic)
        XCTAssertNil(service.pendingPlanChange)
    }
}


extension SessionIsolationTests {
    private func purchasePackage() -> Package {
        Package(identifier: "test", packageType: .monthly,
                storeProduct: StoreProduct(sk1Product: SKProduct()),
                presentedOfferingContext: .init(offeringIdentifier: "test"), webCheckoutUrl: nil)
    }

    @MainActor
    func testOldScreenCannotStartPurchaseOrRestoreForNewAccount() async throws {
        let client = DeferredSubscriptionClient()
        let session = SubscriptionSession(client: client, lifetime: SessionLifetime())
        let service = SubscriptionService(session: session, pendingChange: { _ in nil })
        session.selectUser("A")
        try await session.prepare()
        let oldOwner = session.revision
        session.selectUser("B")
        try await session.prepare()
        client.restoreAction = { XCTFail("Stale restore reached SDK"); throw CancellationError() }
        do {
            _ = try await service.purchase(package: purchasePackage(), expectedRevision: oldOwner)
            XCTFail("Stale purchase accepted")
        } catch is CancellationError { }
        do {
            try await service.restorePurchases(expectedRevision: oldOwner)
            XCTFail("Stale restore accepted")
        } catch is CancellationError { }
        XCTAssertEqual(client.events, ["login:A", "login:B"])
        XCTAssertFalse(service.isLoading)
        XCTAssertNil(service.customerInfo)
    }

    @MainActor
    func testPurchaseKeepsSDKIdentityUntilCompletionAfterAccountSwitch() async throws {
        let client = DeferredSubscriptionClient()
        client.info = try subscriptionInfo("max")
        let session = SubscriptionSession(client: client, lifetime: SessionLifetime())
        let service = SubscriptionService(session: session, pendingChange: { _ in nil })
        session.selectUser("A")
        let started = expectation(description: "Purchase began")
        var resume: CheckedContinuation<Void, Never>?
        client.purchaseAction = {
            await withCheckedContinuation { resume = $0; started.fulfill() }
            XCTAssertEqual(client.appUserID, "A", "Receipt must be processed with the original SDK account")
            return (client.info, false)
        }
        let purchase = Task { try await service.purchase(package: purchasePackage()) }
        await fulfillment(of: [started], timeout: 2)
        session.selectUser(nil)
        session.selectUser("B")
        let bind = Task { try await session.prepare() }
        XCTAssertEqual(client.appUserID, "A")
        XCTAssertFalse(session.isReady)
        resume?.resume()
        do { _ = try await purchase.value; XCTFail("Old purchase result applied") }
        catch is CancellationError { }
        try await bind.value
        XCTAssertEqual(client.events, ["login:A", "purchase:A", "login:B"])
        XCTAssertNil(service.customerInfo)
        XCTAssertEqual(client.appUserID, "B")
    }

    @MainActor
    func testFailedPurchaseReleasesIdentityQueue() async throws {
        let client = DeferredSubscriptionClient()
        let session = SubscriptionSession(client: client, lifetime: SessionLifetime())
        let service = SubscriptionService(session: session, pendingChange: { _ in nil })
        session.selectUser("A")
        let started = expectation(description: "Purchase began")
        var resume: CheckedContinuation<Void, Never>?
        client.purchaseAction = {
            await withCheckedContinuation { resume = $0; started.fulfill() }
            throw URLError(.notConnectedToInternet)
        }
        let purchase = Task { try await service.purchase(package: purchasePackage()) }
        await fulfillment(of: [started], timeout: 2)
        session.selectUser("B")
        resume?.resume()
        do { _ = try await purchase.value; XCTFail("Failed purchase accepted") }
        catch is CancellationError { }
        try await session.prepare()
        XCTAssertEqual(client.appUserID, "B")
        XCTAssertFalse(service.isLoading)
    }
}


extension SessionIsolationTests {
    @MainActor
    private func checkoutSetup() async throws -> (DeferredSubscriptionClient, SubscriptionSession, SubscriptionService, SubscriptionCheckout) {
        let client = DeferredSubscriptionClient()
        client.info = try subscriptionInfo()
        client.offeredPackages = try await CheckoutFixtureClient(mode: "normal").packages()
        let session = SubscriptionSession(client: client, lifetime: SessionLifetime())
        session.selectUser("A")
        let service = SubscriptionService(session: session, pendingChange: { _ in nil })
        let checkout = SubscriptionCheckout(service: service)
        await checkout.load()
        checkout.selectedID = checkout.plans.first?.id
        return (client, session, service, checkout)
    }

    @MainActor
    func testCheckoutPurchaseSucceedsWithoutSecondCustomerFetch() async throws {
        let (client, _, _, checkout) = try await checkoutSetup()
        client.infoAction = { XCTFail("Successful purchase should not require another network check"); throw URLError(.notConnectedToInternet) }
        await checkout.purchase()
        XCTAssertTrue(checkout.completed)
        XCTAssertFalse(checkout.isBusy)
        await checkout.purchase()
        XCTAssertEqual(client.events.filter { $0.hasPrefix("purchase:") }, ["purchase:A"])
    }

    @MainActor
    func testCheckoutCancellationAllowsRetryWithoutClaimingAccess() async throws {
        let (client, _, _, checkout) = try await checkoutSetup()
        client.purchaseAction = { (client.info, true) }
        await checkout.purchase()
        XCTAssertEqual(checkout.message, "Purchase cancelled.")
        XCTAssertFalse(checkout.completed)
        XCTAssertTrue(checkout.canPurchase)
        client.purchaseAction = { throw ErrorCode.purchaseCancelledError }
        await checkout.purchase()
        XCTAssertEqual(checkout.message, "Purchase cancelled.")
        XCTAssertTrue(checkout.canPurchase)
    }

    @MainActor
    func testCheckoutPendingPaymentCannotPromptDuplicatePurchase() async throws {
        let (client, _, _, checkout) = try await checkoutSetup()
        client.purchaseAction = { throw ErrorCode.paymentPendingError }
        client.info = try await CheckoutFixtureClient(mode: "pending").customerInfo()
        await checkout.purchase()
        XCTAssertTrue(checkout.awaitingConfirmation)
        XCTAssertFalse(checkout.canPurchase)
        XCTAssertTrue(checkout.message?.contains("awaiting Apple approval") == true)
        await checkout.checkStatus()
        XCTAssertFalse(checkout.completed)
        XCTAssertFalse(checkout.canPurchase)
        await checkout.purchase()
        XCTAssertEqual(client.events.filter { $0.hasPrefix("purchase:") }.count, 1)
    }

    @MainActor
    func testCheckoutEmptyCatalogStillAllowsRestoreAndReportsNoActiveAccess() async throws {
        let (client, _, _, checkout) = try await checkoutSetup()
        client.offeredPackages = []
        client.info = try await CheckoutFixtureClient(mode: "empty").customerInfo()
        await checkout.load()
        XCTAssertTrue(checkout.plans.isEmpty)
        XCTAssertNotNil(checkout.catalogError)
        XCTAssertFalse(checkout.canPurchase)
        await checkout.restore()
        XCTAssertFalse(checkout.completed)
        XCTAssertTrue(checkout.message?.contains("No active subscription") == true)
        client.info = try subscriptionInfo()
        await checkout.restore()
        XCTAssertTrue(checkout.completed)
    }

    @MainActor
    func testCheckoutFailedCatalogAndRestoreCanRecover() async throws {
        let (client, _, _, checkout) = try await checkoutSetup()
        client.offeringsFail = true
        await checkout.load()
        XCTAssertTrue(checkout.plans.isEmpty)
        XCTAssertNil(checkout.selectedID)
        XCTAssertNotNil(checkout.catalogError)
        client.restoreAction = { throw URLError(.notConnectedToInternet) }
        await checkout.restore()
        XCTAssertEqual(checkout.message, "Could not restore purchases. Please try again.")
        XCTAssertFalse(checkout.completed)
        client.offeringsFail = false
        await checkout.load()
        XCTAssertNil(checkout.catalogError)
        XCTAssertEqual(checkout.plans.count, 1)
    }

    @MainActor
    func testCheckoutClosingBeforeQueueAdmissionPreventsPurchase() async throws {
        let (client, _, service, checkout) = try await checkoutSetup()
        let started = expectation(description: "Status request holds queue")
        var resume: CheckedContinuation<CustomerInfo, Never>?
        client.infoAction = { await withCheckedContinuation { resume = $0; started.fulfill() } }
        let status = Task { await service.checkSubscriptionStatus() }
        await fulfillment(of: [started], timeout: 2)
        let purchase = Task { await checkout.purchase() }
        // Yield until the purchase is queued behind the deliberately paused fetch.
        while !checkout.isBusy { await Task.yield() }
        checkout.close()
        resume?.resume(returning: client.info)
        await status.value
        await purchase.value
        XCTAssertFalse(client.events.contains(where: { $0.hasPrefix("purchase:") }))
        XCTAssertFalse(checkout.completed)
    }

    @MainActor
    func testCheckoutAccountSwitchDuringPurchaseRejectsCompletionAndDuplicateTap() async throws {
        let (client, session, _, checkout) = try await checkoutSetup()
        let started = expectation(description: "Purchase started")
        var resume: CheckedContinuation<Void, Never>?
        client.purchaseAction = {
            await withCheckedContinuation { resume = $0; started.fulfill() }
            XCTAssertEqual(client.appUserID, "A")
            return (client.info, false)
        }
        let purchase = Task { await checkout.purchase() }
        await fulfillment(of: [started], timeout: 2)
        await checkout.purchase()
        session.selectUser("B")
        checkout.close()
        resume?.resume()
        await purchase.value
        try await session.prepare()
        XCTAssertFalse(checkout.completed)
        XCTAssertNil(checkout.message)
        XCTAssertEqual(client.events.filter { $0.hasPrefix("purchase:") }.count, 1)
        XCTAssertEqual(client.appUserID, "B")
    }

    func testCheckoutOfferTermsShowFullBillingPeriodAndAllOfferModes() {
        let month = RevenueCat.SubscriptionPeriod(value: 1, unit: .month)
        XCTAssertEqual(SubscriptionPlan.period(RevenueCat.SubscriptionPeriod(value: 3, unit: .month)), "3 months")
        XCTAssertEqual(SubscriptionPlan.offerTerms(price: "$0.00", mode: .freeTrial,
            period: RevenueCat.SubscriptionPeriod(value: 7, unit: .day), count: 1, recurring: "$9.99 every 1 month"),
            "Free for 7 days, then $9.99 every 1 month.")
        XCTAssertEqual(SubscriptionPlan.offerTerms(price: "$5.00", mode: .payUpFront,
            period: month, count: 3, recurring: "$9.99 every 1 month"),
            "$5.00 for the first 3 months, then $9.99 every 1 month.")
        XCTAssertEqual(SubscriptionPlan.offerTerms(price: "$1.00", mode: .payAsYouGo,
            period: month, count: 3, recurring: "$9.99 every 1 month"),
            "$1.00 every 1 month for 3 payments, then $9.99 every 1 month.")
    }
}


extension SessionIsolationTests {
    @MainActor
    func testBillingCycleShowsThreeTiersAndKeepsTheSelectedTier() async throws {
        let (client, _, _, checkout) = try await checkoutSetup()
        client.offeredPackages = try await CheckoutFixtureClient(mode: "catalog").packages()
        await checkout.load()
        XCTAssertEqual(checkout.visiblePlans.map(\.displayTitle), ["Basic", "Pro", "Max"])
        XCTAssertTrue(checkout.visiblePlans.allSatisfy { $0.billingCycle == .monthly })
        checkout.selectedID = "fixture-pro-monthly"
        checkout.selectCycle(.yearly)
        XCTAssertEqual(checkout.selectedID, "fixture-pro-yearly")
        XCTAssertEqual(checkout.selectedPlan?.package.storeProduct.productIdentifier, "com.halofi.pro.yearly")
        XCTAssertTrue(checkout.visiblePlans.allSatisfy { $0.terms.contains("99.99") && $0.terms.contains("1 year") })
        XCTAssertTrue(checkout.canPurchase)
        checkout.selectCycle(.monthly)
        XCTAssertEqual(checkout.selectedID, "fixture-pro-monthly")
    }

    @MainActor
    func testMissingYearlyProductCannotPurchaseHiddenMonthlySelection() async throws {
        let (_, _, _, checkout) = try await checkoutSetup()
        XCTAssertTrue(checkout.canPurchase)
        checkout.selectCycle(.yearly)
        XCTAssertNil(checkout.selectedPlan)
        XCTAssertFalse(checkout.canPurchase)
    }

    @MainActor
    func testVoiceSubscriptionOutageRequiresManualRetry() {
        XCTAssertTrue(AgentWebSocketManager.terminalErrorCodes.contains("SUBSCRIPTION_UNAVAILABLE"))
        XCTAssertTrue(AgentWebSocketManager.terminalErrorCodes.contains("MINUTE_LIMIT_REACHED"))
        XCTAssertFalse(AgentWebSocketManager.terminalErrorCodes.contains("PROCESSING_ERROR"))
    }
}

private struct NoDestinationBiometrics: BiometricCredentialStoreProtocol {
    var hasEnrolledCredentials: Bool { false }
    func save(_ credentials: BiometricCredentials) throws { }
    func read(reason: String) async throws -> BiometricCredentials { throw BiometricCredentialError.notFound }
    func clear() { }
}

@MainActor
final class DestinationRestorationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    override func setUp() {
        super.setUp()
        suiteName = "destination-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }
    private func manager() -> UserManager {
        UserManager(tokenStorage: MockTokenStorage(), authService: MockAuthService(),
                    biometricCredentialStore: NoDestinationBiometrics(), userDefaults: defaults)
    }
    private func user(_ id: String = "returning", completed: Bool = false) -> User {
        User(id: id, email: "test@example.invalid", firstName: "Test", isOnboarded: completed)
    }
    func testAllAuthenticationPathsRestoreSavedCompletionBeforeRouting() {
        defaults.set(true, forKey: "user_onboarding_completed_returning")
        let manager = manager()
        manager.restoreAuthenticatedUser(user())
        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertTrue(manager.isOnboarded)
        XCTAssertFalse(manager.isResolvingDestination)
        XCTAssertEqual(manager.currentUser?.isOnboarded, true)
        manager.resolveDestination(hasAccounts: false, confirmed: false, userId: "returning", generation: SessionLifetime.shared.current)
        XCTAssertTrue(manager.isOnboarded)
        XCTAssertNil(manager.destinationError)
    }
    func testStoredUserCompletionSurvivesMissingOrOlderFalseFlag() {
        defaults.set(false, forKey: "user_onboarding_completed_returning")
        let manager = manager()
        manager.restoreAuthenticatedUser(user(completed: true))
        XCTAssertTrue(manager.isOnboarded)
        XCTAssertFalse(manager.isResolvingDestination)
    }
    func testUnknownDestinationWaitsAndFailedReadDoesNotStartOnboarding() {
        let manager = manager()
        manager.restoreAuthenticatedUser(user("new"))
        XCTAssertTrue(manager.isResolvingDestination)
        manager.resolveDestination(hasAccounts: false, confirmed: false, userId: "new", generation: SessionLifetime.shared.current)
        XCTAssertTrue(manager.isResolvingDestination)
        XCTAssertNotNil(manager.destinationError)
        manager.resolveDestination(hasAccounts: false, confirmed: true, userId: "new", generation: SessionLifetime.shared.current)
        XCTAssertFalse(manager.isResolvingDestination)
        XCTAssertFalse(manager.isOnboarded)
        XCTAssertNil(manager.destinationError)
    }
    func testAccountSwitchAndExpiredGenerationCannotResolveNewSession() {
        let manager = manager()
        manager.restoreAuthenticatedUser(user("A", completed: true))
        manager.restoreAuthenticatedUser(user("B"))
        manager.resolveDestination(hasAccounts: true, confirmed: true, userId: "A", generation: SessionLifetime.shared.current)
        manager.resolveDestination(hasAccounts: true, confirmed: true, userId: "B", generation: UUID())
        XCTAssertFalse(manager.isOnboarded)
        XCTAssertTrue(manager.isResolvingDestination)
        manager.resolveDestination(hasAccounts: true, confirmed: true, userId: "B", generation: SessionLifetime.shared.current)
        XCTAssertTrue(manager.isOnboarded)
        XCTAssertFalse(manager.isResolvingDestination)
    }
}

private struct DestinationRefreshAuth: AuthServiceProtocol {
    func refreshToken(refreshToken: String) async throws -> RefreshTokenResponse {
        .init(success: true, accessToken: "test-access", refreshToken: "test-refresh", tokenType: "bearer", expiresIn: 3600)
    }
    func login(email: String, password: String) async throws -> LoginResponse { throw AuthError.notImplemented }
    func socialLogin(provider: String, idToken: String, nonce: String?, firstName: String?, lastName: String?) async throws -> LoginResponse { throw AuthError.notImplemented }
    func register(firstName: String, lastName: String, email: String, phone: String, password: String, dateOfBirth: Date?) async throws -> SignupResponse { throw AuthError.notImplemented }
    func getUserProfile() async throws -> UserProfileResponse { throw AuthError.notImplemented }
    func updateUserProfile(request: UpdateUserProfileRequest) async throws -> UserProfileResponse { throw AuthError.notImplemented }
    func logout(accessToken: String) async throws { }
    func deleteAccount(userId: String) async throws { }
}

extension DestinationRestorationTests {
    func testConsentRestorationSurvivesPreviousBankSessionBeingCleared() async throws {
        let manager = manager()
        manager.restoreAuthenticatedUser(user("B", completed: true))
        XCTAssertTrue(manager.isResolvingConsent)
        // configureForUser clears the previous bank session synchronously.
        SessionLifetime.shared.invalidate { }
        for _ in 0..<1000 {
            if !manager.isResolvingConsent { break }
            await Task.yield()
        }
        XCTAssertFalse(manager.isResolvingConsent)
        XCTAssertTrue(manager.isOnboarded)
    }

    func testExpiredTokenLaunchNeverPublishesReturningUserAsOnboarding() async throws {
        defaults.set(try JSONEncoder().encode(user(completed: true)), forKey: "currentUser")
        defaults.set(true, forKey: "user_onboarding_completed_returning")
        let storage = MockTokenStorage()
        storage.saveTokens(accessToken: "expired", refreshToken: "refresh", expiresIn: -10)
        let manager = UserManager(tokenStorage: storage, authService: DestinationRefreshAuth(),
                                  biometricCredentialStore: NoDestinationBiometrics(), userDefaults: defaults)
        XCTAssertTrue(manager.isResolvingDestination)
        for _ in 0..<1000 {
            if manager.isAuthenticated { break }
            await Task.yield()
        }
        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertTrue(manager.isOnboarded)
        XCTAssertFalse(manager.isResolvingDestination)
        XCTAssertTrue(storage.isTokenValid())
    }
}

final class VoiceReviewConfigurationTests: XCTestCase {
    func testSavedModeIsPreservedAndMissingModeMatchesServer() {
        XCTAssertEqual(ConversationMode.from(nil), .handsFree)
        XCTAssertEqual(ConversationMode.from("invalid"), .handsFree)
        XCTAssertEqual(ConversationMode.from("push_to_talk"), .pushToTalk)
        XCTAssertEqual(ConversationMode.from("hands_free"), .handsFree)
    }

    func testEffectiveSTTConfigurationAndLegacyResponseDecode() throws {
        let base = #"{"token":"fixture","model_id":"scribe_v2_realtime","websocket_url":"wss://example.invalid","config":{"audio_format":"pcm_16000","sample_rate":16000,"commit_strategy":"vad","language_code":"en","include_timestamps":false}}"#
        let legacy = try JSONDecoder().decode(STTTokenResponse.self, from: Data(base.utf8))
        XCTAssertNil(legacy.config.conversationMode)
        XCTAssertNil(legacy.config.minSpeechMs)
        let updated = base.replacingOccurrences(of: #""include_timestamps":false"#, with: #""include_timestamps":false,"conversation_mode":"hands_free","min_speech_ms":300"#)
        let effective = try JSONDecoder().decode(STTTokenResponse.self, from: Data(updated.utf8))
        XCTAssertEqual(effective.config.conversationMode, "hands_free")
        XCTAssertEqual(effective.config.minSpeechMs, 300)
    }

    @MainActor
    func testNavigationConsumesOneDestinationAndClearsOldBudgetRequest() {
        VoiceNavigation.pendingBudget = true
        VoiceNavigation.pendingDestination = .transactions
        XCTAssertEqual(VoiceNavigation.consumeDestination(), .transactions)
        XCTAssertNil(VoiceNavigation.consumeDestination())
        XCTAssertFalse(VoiceNavigation.pendingBudget)
    }

    func testNewNavigationDestinationDecodes() throws {
        let payload = #"{"kind":"navigate","action_id":"t","state":"proposed","target":"investments","receipt":"Open investments."}"#
        let action = try JSONDecoder().decode(VoiceAppAction.self, from: Data(payload.utf8))
        XCTAssertEqual(action.target, .investments)
    }
}

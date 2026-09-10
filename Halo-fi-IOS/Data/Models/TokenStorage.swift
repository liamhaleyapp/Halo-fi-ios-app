import Foundation
import Security

/// One atomic Keychain item holds the entire rotated credential pair.
/// Legacy entries remain readable until the first successful refresh/save.
struct TokenStorage: TokenStorageProtocol {
    private let service: String
    private static let lock = NSRecursiveLock()
    private let sessionKey = "session.v2"
    private struct Credentials: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int
    }
    struct StorageError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Your sign-in could not be saved securely. Please try again." }
    }

    init(service: String = AppEnvironment.isProdPlaid ? "com.halofi.ios.prod" : "com.halofi.ios.sandbox") {
        self.service = service
    }

    func persistTokens(accessToken: String, refreshToken: String, expiresAt: Int) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard !accessToken.isEmpty, !refreshToken.isEmpty else { throw AuthError.invalidResponse }
        let data = try JSONEncoder().encode(Credentials(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt))
        let query = query(sessionKey)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            AuthSessionDiagnostics.record(.storageWriteFailed)
            Logger.warning("auth_storage_save_failed status=\(status)")
            throw StorageError(status: status)
        }
        // Only remove the previous format after the complete pair is durable.
        for key in ["accessToken", "refreshToken", "tokenExpiry"] { SecItemDelete(self.query(key) as CFDictionary) }
    }

    func saveTokens(accessToken: String, refreshToken: String, expiresIn: Int) {
        saveTokensWithExpiration(accessToken: accessToken, refreshToken: refreshToken,
            expiresAt: Int(Date().timeIntervalSince1970) + expiresIn)
    }

    func saveTokensWithExpiration(accessToken: String, refreshToken: String, expiresAt: Int) {
        // Compatibility for preview/test callers. Production uses throwing persistence.
        do { try persistTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt) }
        catch { Logger.warning("auth_storage_save_failed") }
    }

    func getAccessToken() -> String? { try? credentials()?.accessToken }
    func getRefreshToken() -> String? { try? credentials()?.refreshToken }
    func isTokenValid() -> Bool {
        guard let expiry = try? credentials()?.expiresAt else { return false }
        return expiry > Int(Date().timeIntervalSince1970)
    }

    func clearTokens() {
        SessionLifetime.shared.invalidate {
            Self.lock.lock()
            defer { Self.lock.unlock() }
            for key in [sessionKey, "accessToken", "refreshToken", "tokenExpiry"] {
                let status = SecItemDelete(query(key) as CFDictionary)
                if status != errSecSuccess && status != errSecItemNotFound {
                    Logger.warning("auth_storage_delete_failed status=\(status)")
                }
            }
        }
    }

    private func credentials() throws -> Credentials? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if let data = try read(sessionKey) { return try JSONDecoder().decode(Credentials.self, from: data) }
        guard let access = try read("accessToken"), let refresh = try read("refreshToken"),
              let accessToken = String(data: access, encoding: .utf8),
              let refreshToken = String(data: refresh, encoding: .utf8) else { return nil }
        let expiry = try read("tokenExpiry").flatMap { try? JSONDecoder().decode(Date.self, from: $0) }
        return Credentials(accessToken: accessToken, refreshToken: refreshToken, expiresAt: Int(expiry?.timeIntervalSince1970 ?? 0))
    }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    private func read(_ key: String) throws -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            AuthSessionDiagnostics.record(.storageReadFailed)
            Logger.warning("auth_storage_read_failed status=\(status)")
            throw StorageError(status: status)
        }
        return result as? Data
    }
}

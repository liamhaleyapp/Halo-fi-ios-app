//
//  BiometricAppLock.swift
//  Halo-fi-IOS
//
//  Face ID / Touch ID as an app lock (2026-09-05). Accounts signed in with
//  Google or Apple have no HaloFi password to re-enter, so "Face ID" for
//  them means: when the app returns to the foreground, prove it is you
//  before balances show. Password accounts keep the credential-store
//  sign-in they already had.
//

import Foundation
import SwiftUI

enum BiometricAppLock {
    private static let key = "biometric_app_lock.v1"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Covers the app until biometrics succeed, whenever it returns to the
/// foreground with the lock on and someone signed in.
struct BiometricAppLockModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(DIContainer.self) private var container
    @Environment(UserManager.self) private var userManager
    @State private var locked = false
    @State private var checking = false
    @State private var unlockedUserId: String?
    @AccessibilityFocusState private var lockFocused: Bool

    private var needsLock: Bool {
        BiometricAppLock.isEnabled && userManager.isAuthenticated &&
            (locked || unlockedUserId != userManager.currentUser?.id)
    }

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(needsLock)
            .allowsHitTesting(!needsLock)
            .overlay {
                if needsLock {
                    ZStack {
                        Color(.systemBackground).ignoresSafeArea()
                        VStack(spacing: 16) {
                            Image(systemName: "faceid").font(.system(size: 44)).foregroundStyle(.secondary).accessibilityHidden(true)
                            Text("HaloFi is locked").font(.title3.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityFocused($lockFocused)
                            Button { Task { await unlock() } } label: {
                                Text("Unlock").font(.headline).frame(minWidth: 200, minHeight: 56)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityHint("Asks for Face ID or Touch ID.")
                        }
                    }
                    .accessibilityAddTraits(.isModal)
                    .onAppear { lockFocused = true }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard BiometricAppLock.isEnabled, userManager.isAuthenticated else { return }
                if phase == .background { locked = true; unlockedUserId = nil }
                if phase == .active && locked && !checking { Task { await unlock() } }
            }
            .task(id: userManager.currentUser?.id) {
                unlockedUserId = nil
                guard BiometricAppLock.isEnabled, userManager.isAuthenticated else { return }
                locked = true
                await unlock()
            }
    }

    private func unlock() async {
        guard !checking else { return }
        let generation = SessionLifetime.shared.current
        let userId = userManager.currentUser?.id
        checking = true
        defer { checking = false }
        do {
            try await container.biometricAuthService.authenticate(reason: "Unlock HaloFi")
            guard SessionLifetime.shared.isCurrent(generation), userManager.currentUser?.id == userId,
                  scenePhase != .background, !Task.isCancelled else { return }
            unlockedUserId = userId
            locked = false
            UIAccessibility.post(notification: .screenChanged, argument: "Unlocked.")
        } catch {
            locked = true
        }
    }
}

extension View {
    func biometricAppLock() -> some View { modifier(BiometricAppLockModifier()) }
}

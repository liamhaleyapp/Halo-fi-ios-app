//
//  InAppBrowser.swift
//  Halo-fi-IOS
//
//  Web links (the free benefits counselor finder, a receipt image) open
//  INSIDE the app in SFSafariViewController (Liam, 2026-09-05) instead of
//  bouncing the user out to Safari. Standard Close control top-left,
//  VoiceOver-ready, shares Safari's autofill and cookies, no permissions.
//  Non-web schemes (tel:, mailto:) still go to the system.
//

import SafariServices
import SwiftUI
import UIKit

enum InAppBrowser {
    @MainActor
    static func open(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let presenter = topViewController() else {
            UIApplication.shared.open(url)
            return
        }
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let safari = SFSafariViewController(url: url, configuration: config)
        safari.dismissButtonStyle = .close
        safari.preferredControlTintColor = .systemBlue
        safari.modalPresentationStyle = .pageSheet
        presenter.present(safari, animated: true)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.flatMap(\.windows).first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

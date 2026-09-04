//
//  SharedReceiptInbox.swift
//  Halo-fi-IOS
//
//  Handoff between the HaloFiShare extension and the app.
//
//  The extension cannot reach the app's keychain (no access group, tokens
//  are ThisDeviceOnly), so it never uploads. It copies the shared image or
//  PDF into the App Group container and opens `halofi://receipt?file=<name>`.
//  The app (which has the auth token) picks the file up from the inbox,
//  uploads it, and opens the log form with the receipt attached.
//
//  Both targets must carry the App Group entitlement `group.com.Halofiapp`.
//

import Foundation
import UIKit

extension Notification.Name {
    /// Posted by the app's URL handler when a receipt arrived from the share
    /// extension. userInfo["fileURL"] is the file in the inbox.
    static let receiptShared = Notification.Name("ReceiptShared")
}

enum SharedReceiptInbox {
    static let appGroupIdentifier = "group.com.Halofiapp"
    static let urlScheme = "halofi"
    static let urlHost = "receipt"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("ReceiptInbox", isDirectory: true)
    }

    /// True for `halofi://receipt?file=...`.
    static func isReceiptURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == urlScheme && url.host?.lowercased() == urlHost
    }

    /// Resolve the inbox file named in the URL; nil when missing.
    static func fileURL(from url: URL) -> URL? {
        guard isReceiptURL(url),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let name = items.first(where: { $0.name == "file" })?.value,
              !name.isEmpty,
              !name.contains("/"), !name.contains(".."),
              let dir = containerURL else { return nil }
        let file = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Load an inbox file as an uploadable receipt (JPEG or PDF), then
    /// delete it from the inbox.
    static func consume(_ fileURL: URL) -> CapturedReceipt? {
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        if fileURL.pathExtension.lowercased() == "pdf" {
            return .pdf(data)
        }
        guard let image = UIImage(data: data), let jpeg = image.receiptJPEGData() else { return nil }
        return .jpeg(jpeg)
    }

    /// Anything left behind (app was killed before consuming).
    static func pendingFiles() -> [URL] {
        guard let dir = containerURL,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { ["jpg", "jpeg", "png", "heic", "pdf"].contains($0.pathExtension.lowercased()) }
    }
}


/// The app-side hand-off buffer. The URL handler drops the receipt here and
/// switches to the Budget tab; BudgetView takes it when it appears (or
/// immediately, if it is already on screen). Survives the race between the
/// notification and the tab's first render.
@MainActor
@Observable
final class ReceiptHandoff {
    static let shared = ReceiptHandoff()
    private(set) var pending: CapturedReceipt?

    func offer(_ receipt: CapturedReceipt) {
        pending = receipt
        NotificationCenter.default.post(name: .receiptShared, object: nil)
    }

    func take() -> CapturedReceipt? {
        defer { pending = nil }
        return pending
    }
}

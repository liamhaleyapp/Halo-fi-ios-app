//
//  ShareViewController.swift
//  HaloFiShare
//
//  "Share to HaloFi" from the Uber/Lyft email, Photos, Files, Mail, etc.
//
//  The extension never talks to the backend (it has no auth token — the
//  app's keychain items are ThisDeviceOnly with no access group). It copies
//  the shared image or PDF into the App Group inbox and opens
//  `halofi://receipt?file=<name>`; the app uploads and opens the log form.
//
//  Keep this file free of app-target types: the extension target compiles
//  it alone. The inbox layout mirrors SharedReceiptInbox.swift in the app.
//

import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let appGroupIdentifier = "group.com.Halofiapp"
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.text = "Sending the receipt to HaloFi…"
        statusLabel.font = UIFont.preferredFont(forTextStyle: .title3)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])
        UIAccessibility.post(notification: .screenChanged, argument: statusLabel)
        handleShare()
    }

    private func handleShare() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments, !providers.isEmpty else {
            fail("Nothing to share.")
            return
        }
        let preferred: [UTType] = [.pdf, .jpeg, .png, .heic, .image, .fileURL, .url]
        for type in preferred {
            if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) }) {
                provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { [weak self] payload, error in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if let error {
                            self.fail("Couldn't read that. \(error.localizedDescription)")
                            return
                        }
                        self.persist(payload, declaredType: type)
                    }
                }
                return
            }
        }
        fail("HaloFi can accept a photo or a PDF of a receipt.")
    }

    private func persist(_ payload: NSSecureCoding?, declaredType: UTType) {
        var data: Data?
        var ext = "jpg"
        switch payload {
        case let url as URL:
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            data = try? Data(contentsOf: url)
            ext = url.pathExtension.lowercased()
        case let image as UIImage:
            data = image.jpegData(compressionQuality: 0.85)
            ext = "jpg"
        case let raw as Data:
            data = raw
            ext = declaredType == .pdf ? "pdf" : (declaredType == .png ? "png" : "jpg")
        default:
            break
        }
        guard let bytes = data, !bytes.isEmpty else {
            fail("Couldn't read that receipt.")
            return
        }
        guard ["jpg", "jpeg", "png", "heic", "pdf"].contains(ext) else {
            fail("HaloFi can accept a photo or a PDF of a receipt.")
            return
        }
        guard bytes.count <= 10 * 1024 * 1024 else {
            fail("Receipts must be 10 MB or smaller.")
            return
        }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            fail("HaloFi isn't set up to receive shares yet. Open the app and try again.")
            return
        }
        let inbox = container.appendingPathComponent("ReceiptInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).\(ext)"
        do {
            try bytes.write(to: inbox.appendingPathComponent(name), options: .atomic)
        } catch {
            fail("Couldn't save the receipt. \(error.localizedDescription)")
            return
        }
        openApp(fileName: name)
    }

    private func openApp(fileName: String) {
        guard let url = URL(string: "halofi://receipt?file=\(fileName)") else {
            fail("Couldn't open HaloFi.")
            return
        }
        statusLabel.text = "Opening HaloFi…"
        // Share extensions can't call UIApplication.open directly; walk the
        // responder chain to the host's UIApplication (the standard workaround).
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let r = responder {
            if r.responds(to: selector) {
                _ = r.perform(selector, with: url)
                break
            }
            responder = r.next
        }
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func fail(_ message: String) {
        statusLabel.text = message
        UIAccessibility.post(notification: .announcement, argument: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: "HaloFiShare", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }
}

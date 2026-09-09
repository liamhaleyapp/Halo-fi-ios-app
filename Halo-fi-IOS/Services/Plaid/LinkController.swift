import LinkKit
import SwiftUI

/// Bridge for the installed LinkKit 6 SDK. Open only after the host appears.
struct LinkController: UIViewControllerRepresentable {
    private let handler: Handler
    private let colorScheme: ColorScheme?

    init(handler: Handler, colorScheme: ColorScheme? = nil) {
        self.handler = handler
        self.colorScheme = colorScheme
    }

    func makeUIViewController(context: Context) -> LinkHostViewController {
        let host = LinkHostViewController { attach in
            handler.open(presentUsing: .custom(attach))
        }
        if let colorScheme { host.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light }
        return host
    }

    func updateUIViewController(_ host: LinkHostViewController, context: Context) {}

    static func dismantleUIViewController(_ host: LinkHostViewController, coordinator: ()) {
        host.invalidate()
    }
}

@MainActor
final class LinkHostViewController: UIViewController {
    private let openLink: (@escaping (UIViewController) -> Void) -> Void
    private var hasOpened = false
    private var isValid = true
    private var openingTimeout: Task<Void, Never>?
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    init(openLink: @escaping (@escaping (UIViewController) -> Void) -> Void) {
        self.openLink = openLink
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.text = "Opening secure bank sign-in…"
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        spinner.startAnimating()
        spinner.isAccessibilityElement = false
        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard isValid, !hasOpened else { return }
        hasOpened = true
        Diagnostics.send("plaid_link_host_open")
        openingTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, self.isValid, self.children.isEmpty else { return }
            let message = "Bank sign-in hasn't opened. Close this screen and try again."
            self.statusLabel.text = message
            self.spinner.stopAnimating()
            UIAccessibility.post(notification: .announcement, argument: message)
            Diagnostics.send("plaid_link_open_timeout")
        }
        openLink { [weak self] child in
            guard let self, self.isValid, self.children.isEmpty else { return }
            self.openingTimeout?.cancel()
            self.addChild(child)
            self.view.addSubview(child.view)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                child.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                child.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                child.view.topAnchor.constraint(equalTo: self.view.topAnchor),
                child.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
            ])
            child.didMove(toParent: self)
            self.statusLabel.isHidden = true
            self.spinner.stopAnimating()
            self.spinner.isHidden = true
            Diagnostics.send("plaid_link_attached")
        }
    }

    func invalidate() {
        isValid = false
        openingTimeout?.cancel()
        openingTimeout = nil
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
    }
}

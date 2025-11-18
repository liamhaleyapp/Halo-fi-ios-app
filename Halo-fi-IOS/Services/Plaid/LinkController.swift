//
//  LinkController.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/6/25.
//

import LinkKit
import SwiftUI

// Plaid currently doesn't fully support SwiftUI. Therefore, we need to create a bridge from SwiftUI to UIKit.
struct LinkController: UIViewControllerRepresentable {

    private let handler: Handler
    private let colorScheme: ColorScheme?

    init(handler: Handler, colorScheme: ColorScheme? = nil) {
        self.handler = handler
        self.colorScheme = colorScheme
    }

    // MARK: UIViewControllerRepresentable

    final class Coordinator: NSObject {
        private let parent: LinkController
        private let handler: Handler
        private let colorScheme: ColorScheme?

        fileprivate init(parent: LinkController, handler: Handler, colorScheme: ColorScheme?) {
            self.parent = parent
            self.handler = handler
            self.colorScheme = colorScheme
        }

        fileprivate func present(_ handler: Handler, in viewController: UIViewController) {
            handler.open(presentUsing: .custom({ linkViewController in
                // Always use dark mode for Plaid Link for better visual consistency
                linkViewController.overrideUserInterfaceStyle = .dark
                linkViewController.view.backgroundColor = .black
                
                viewController.addChild(linkViewController)
                viewController.view.addSubview(linkViewController.view)
                linkViewController.view.translatesAutoresizingMaskIntoConstraints = false
                linkViewController.view.frame = viewController.view.bounds
                NSLayoutConstraint.activate([
                    linkViewController.view.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
                    linkViewController.view.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor),
                    linkViewController.view.widthAnchor.constraint(equalTo: viewController.view.widthAnchor),
                    linkViewController.view.heightAnchor.constraint(equalTo: viewController.view.heightAnchor),
                ])
                linkViewController.didMove(toParent: viewController)
            }))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, handler: handler, colorScheme: colorScheme)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        
        // Always use dark mode for Plaid Link for better visual consistency
        viewController.overrideUserInterfaceStyle = .dark
        viewController.view.backgroundColor = .black
        
        // Configure status bar style
        viewController.setNeedsStatusBarAppearanceUpdate()
        
        context.coordinator.present(handler, in: viewController)
        return viewController
    }
    
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        // Clean up if needed
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Empty implementation
    }
}

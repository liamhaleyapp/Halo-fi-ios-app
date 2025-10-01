//
//  PlaidWebView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI
@preconcurrency import WebKit

struct PlaidWebView: UIViewRepresentable {
  let linkToken: String
  let onSuccess: (String) -> Void
  let onExit: (PlaidError?) -> Void
  
  func makeUIView(context: Context) -> WKWebView {
    let webView = WKWebView()
    webView.navigationDelegate = context.coordinator
    webView.allowsBackForwardNavigationGestures = false
    
    // Load Plaid Link
    if let url = URL(string: "https://cdn.plaid.com/link/v2/stable/link.html?isWebview=true&token=\(linkToken)") {
      let request = URLRequest(url: url)
      webView.load(request)
    }
    
    return webView
  }
  
  func updateUIView(_ uiView: WKWebView, context: Context) {
    // No updates needed
  }
  
  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }
  
  class Coordinator: NSObject, WKNavigationDelegate {
    let parent: PlaidWebView
    
    init(_ parent: PlaidWebView) {
      self.parent = parent
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
      // Handle Plaid callbacks
      if let url = navigationAction.request.url,
         url.scheme == "plaid" {
        
        if url.host == "oauth" {
          // OAuth callback - let Plaid handle it
          decisionHandler(.allow)
        } else if url.host == "event" {
          // Handle Plaid events
          handlePlaidEvent(url)
          decisionHandler(.cancel)
        } else {
          decisionHandler(.cancel)
        }
      } else {
        decisionHandler(.allow)
      }
    }
    
    private func handlePlaidEvent(_ url: URL) {
      // Parse Plaid event from URL
      // This would handle success, exit, and other events
      // For now, we'll use a simplified approach
    }
  }
}

// MARK: - Preview
#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    PlaidWebView(
      linkToken: "demo-token",
      onSuccess: { _ in },
      onExit: { _ in }
    )
  }
}

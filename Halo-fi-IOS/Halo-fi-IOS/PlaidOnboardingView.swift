import SwiftUI
import WebKit

struct PlaidOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var plaidManager = PlaidManager()
    @State private var isLoading = true
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Plaid WebView
                if isLoading {
                    loadingView
                } else {
                    PlaidWebView(
                        linkToken: plaidManager.linkToken,
                        onSuccess: { publicToken in
                            handlePlaidSuccess(publicToken)
                        },
                        onExit: { error in
                            handlePlaidExit(error)
                        }
                    )
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            startPlaidFlow()
        }
        .alert("Connection Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.white)
                
                Spacer()
                
                Text("Connect Your Bank")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Invisible button for balance
                Button("") { }
                    .opacity(0)
            }
            .padding(.horizontal)
            
            Text("Securely connect your accounts to get personalized financial insights")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top)
        .background(
            LinearGradient(
                colors: [Color.indigo, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            
            Text("Setting up secure connection...")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("This may take a few moments")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.indigo, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    // MARK: - Plaid Flow Methods
    private func startPlaidFlow() {
        Task {
            do {
                try await plaidManager.createLinkToken()
                await MainActor.run {
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to start bank connection: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
    
    private func handlePlaidSuccess(_ publicToken: String) {
        Task {
            do {
                try await plaidManager.exchangePublicToken(publicToken)
                await MainActor.run {
                    // Success - dismiss and return to main app
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to complete connection: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
    
    private func handlePlaidExit(_ error: PlaidError?) {
        if let error = error {
            errorMessage = "Connection failed: \(error.localizedDescription)"
            showingError = true
        } else {
            // User cancelled - just dismiss
            dismiss()
        }
    }
}

// MARK: - Plaid WebView
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

// MARK: - Plaid Manager
class PlaidManager: ObservableObject {
    @Published var linkToken: String = ""
    
    func createLinkToken() async throws {
        // In a real app, this would call your backend
        // For now, we'll simulate it
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Simulate getting a link token from your backend
        linkToken = "link-sandbox-\(UUID().uuidString)"
    }
    
    func exchangePublicToken(_ publicToken: String) async throws {
        // In a real app, this would call your backend to exchange the public token
        // for an access token and fetch initial account data
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Simulate successful exchange
        print("Successfully exchanged public token: \(publicToken)")
    }
}

// MARK: - Plaid Error
enum PlaidError: Error, LocalizedError {
    case linkTokenCreationFailed
    case publicTokenExchangeFailed
    case userCancelled
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .linkTokenCreationFailed:
            return "Failed to create secure connection"
        case .publicTokenExchangeFailed:
            return "Failed to complete bank connection"
        case .userCancelled:
            return "Bank connection was cancelled"
        case .networkError:
            return "Network error. Please try again"
        }
    }
}

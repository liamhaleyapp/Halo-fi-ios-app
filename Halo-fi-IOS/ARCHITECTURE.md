# Halo-Fi iOS Architecture

## Overview

Halo-Fi iOS follows the **MVVM (Model-View-ViewModel)** architecture pattern with SwiftUI and Swift's modern `@Observable` macro for state management.

## Project Structure

```
Halo-fi-IOS/
├── App/                     # App entry point and root views
│   ├── Halo_fi_IOSApp.swift # Main app, dependency injection setup
│   └── ContentView.swift    # Root view controller
│
├── Features/                # Feature modules (organized by domain)
│   ├── Auth/               # Authentication (SignIn, SignUp)
│   ├── Accounts/           # Bank accounts management
│   ├── Home/               # Main dashboard
│   ├── Profile/            # User profile and settings
│   ├── Subscription/       # Subscription management
│   ├── Onboarding/         # User onboarding flow
│   └── Voice/              # AI voice assistant
│
├── Services/               # Business logic and API communication
│   ├── UserManager.swift   # User state and authentication
│   ├── AuthService.swift   # Auth API calls (singleton)
│   ├── NetworkService.swift # HTTP client (singleton)
│   ├── Banking/            # Bank-related services
│   └── Plaid/              # Plaid integration
│
├── Data/                   # Data layer
│   ├── Models/             # Domain models (Codable structs)
│   └── Mock/               # Mock data for previews
│
├── Shared/                 # Cross-cutting utilities
│   ├── Helpers/            # Utility classes (CurrencyFormatter, Logger, etc.)
│   ├── Constants/          # API endpoints, strings
│   └── Networking/         # Request/Response DTOs
│
└── UI/                     # Global UI components
    └── Components/         # Reusable UI primitives
```

## Key Services

| Service | Type | Purpose |
|---------|------|---------|
| `UserManager` | @Observable | User authentication state, profile |
| `BankDataManager` | @Observable | Bank accounts and transactions |
| `SubscriptionService` | @Observable | RevenueCat subscription state |
| `AuthService` | Singleton | Authentication API calls |
| `BankService` | Singleton | Banking API calls |
| `NetworkService` | Singleton | HTTP client wrapper |
| `PlaidManager` | ObservableObject | Plaid Link orchestration |

## Dependency Injection

Dependencies are injected via SwiftUI's environment:

```swift
// App setup (Halo_fi_IOSApp.swift)
ContentView()
    .environment(userManager)       // @Observable
    .environment(bankDataManager)   // @Observable
    .environmentObject(plaidManager) // ObservableObject

// Usage in views
@Environment(UserManager.self) private var userManager
```

## State Management

The app uses Swift's `@Observable` macro (iOS 17+):

```swift
@MainActor
@Observable
class UserManager {
    var currentUser: User?
    var isAuthenticated = false
    // Properties are automatically observed
}
```

## Networking

All API calls go through `NetworkService`, which handles:
- Authentication header injection
- Token management
- Error parsing and conversion

API endpoints are centralized in `APIEndpoints.swift`.

## Error Handling

- `AuthError` - Authentication failures
- `BankError` - Banking operation failures
- Services convert errors to domain-specific types

## Shared Utilities

| Utility | Location | Purpose |
|---------|----------|---------|
| `CurrencyFormatter` | Shared/Helpers | Currency formatting |
| `DateFormatting` | Shared/Helpers | Date parsing/formatting |
| `Logger` | Shared/Helpers | Consistent logging |
| `APIEndpoints` | Shared/Constants | Centralized endpoints |

## Future Improvements

1. **DI Standardization**: Migrate `PlaidManager` from `ObservableObject` to `@Observable`
2. **Testing**: Add unit tests for services
3. **Error Recovery**: Implement token refresh flow

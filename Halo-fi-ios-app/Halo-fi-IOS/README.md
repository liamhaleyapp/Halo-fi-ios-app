# Halo Fi iOS App

A voice-first financial coaching app built with SwiftUI for iOS.

## Overview

Halo Fi is designed to provide users with personalized financial coaching through voice interactions and comprehensive account management. The app features a modern, dark-themed interface with vibrant gradients and intuitive navigation.

## Features

### 🏠 Home View
- Personalized greeting with user's name
- Central glowing microphone button for voice conversations
- Four action buttons with vibrant gradient colors:
  - **Daily Snapshot** - Quick financial overview
  - **Weekly Summary** - Weekly financial insights
  - **Spending Check** - Monitor spending patterns
  - **Financial Coaching** - Access to financial advice

### 💳 Accounts Overview
- Comprehensive view of all financial accounts
- Account categories:
  - Checking Accounts
  - Savings Accounts
  - Credit Cards
  - Investments
  - Loans
- Real-time balance display with trend indicators (up/down arrows)
- Color-coded category buttons for easy identification
- Navigation with back button and volume toggle

### ⚙️ Settings
- Clean, flat design with subtle icons
- Settings options:
  - Profile management
  - Preferences customization
  - Subscription details
  - Invite friends functionality
  - About information
  - Logout functionality
  - Account settings

## Technical Details

### Architecture
- **SwiftUI** - Modern declarative UI framework
- **MVVM Pattern** - Clean separation of concerns
- **Tab-based Navigation** - Intuitive user experience

### Design System
- **Dark Mode Default** - High contrast, modern aesthetic
- **System Fonts** - Consistent with iOS design guidelines
- **Vibrant Gradients** - Rich, engaging visual elements
- **High Contrast** - Accessible design for all users

### File Structure
```
Halo-fi-IOS/
├── Halo-fi-IOS/
│   ├── Halo_fi_IOSApp.swift      # Main app entry point
│   ├── ContentView.swift          # Root view container
│   ├── MainTabView.swift          # Tab navigation coordinator
│   ├── HomeView.swift             # Home screen implementation
│   ├── AccountsOverviewView.swift # Accounts management view
│   ├── SettingsView.swift         # Settings and preferences
│   └── Assets.xcassets/          # App icons and assets
├── Halo-fi-IOS.xcodeproj/        # Xcode project file
└── README.md                      # This documentation
```

## Getting Started

### Prerequisites
- Xcode 15.0 or later
- iOS 18.2+ deployment target
- macOS 14.0 or later (for development)

### Installation
1. Clone the repository
2. Open `Halo-fi-IOS.xcodeproj` in Xcode
3. Select your target device or simulator
4. Build and run the project (⌘+R)

### Building
```bash
cd Halo-fi-IOS
xcodebuild -project Halo-fi-IOS.xcodeproj -scheme Halo-fi-IOS -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Development Status

### ✅ Completed
- Core app structure and navigation
- Three main views (Home, Accounts, Settings)
- Dark theme with vibrant gradients
- Tab-based navigation system
- Responsive UI components

### 🚧 In Progress
- Voice conversation functionality
- Data persistence and management
- User authentication system

### 📋 Planned Features
- Real-time account synchronization
- Voice recognition and processing
- Financial insights and analytics
- Push notifications
- Social features (invite friends)

## Contributing

This is the first version (MVP) of Halo Fi. Future iterations will include:
- Enhanced voice capabilities
- Advanced financial analytics
- Integration with financial institutions
- Personalized coaching algorithms

## License

This project is proprietary software. All rights reserved.

---

**Built with ❤️ using SwiftUI for iOS** 
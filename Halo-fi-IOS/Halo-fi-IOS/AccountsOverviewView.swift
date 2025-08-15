import SwiftUI

struct AccountsOverviewView: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Navigation bar
                    HStack {
                        Spacer()
                        
                        Text("Accounts Overview")
                            .font(.largeTitle)
                            .fontWeight(.heavy)
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                    
                    // Content
                    VStack(spacing: 12) {
                        // Checking Accounts
                        AccountCategorySection(
                            title: "Checking Accounts",
                            icon: "house.fill",
                            color: Color.gray.opacity(0.7),
                            accounts: [
                                Account(name: "Bank of America Checking", balance: "$4,502.32", trend: .up),
                                Account(name: "Chime Checking", balance: "$1,120.00", trend: .down)
                            ]
                        )
                        
                        // Savings Accounts
                        AccountCategorySection(
                            title: "Savings Accounts",
                            icon: "creditcard.fill",
                            color: Color.purple.opacity(0.7),
                            accounts: [
                                Account(name: "Ally Savings", balance: "$9,230.50", trend: .up)
                            ],
                            isHighlighted: true
                        )
                        
                        // Credit Cards
                        AccountCategorySection(
                            title: "Credit Cards",
                            icon: "creditcard.fill",
                            color: Color.blue.opacity(0.7),
                            accounts: [
                                Account(name: "Amex Platinum", balance: "$1,245.12", trend: .up),
                                Account(name: "Chase Sapphire", balance: "$3,010.00", trend: .down)
                            ]
                        )
                        
                        // Investments
                        AccountCategorySection(
                            title: "Investments",
                            icon: "chart.line.uptrend.xyaxis",
                            color: Color.blue.opacity(0.9),
                            accounts: [
                                Account(name: "Vanguard IRA", balance: "$21,304.23", trend: .up),
                                Account(name: "Robinhood", balance: "$1,190.44", trend: .down)
                            ]
                        )
                        
                        // Loans
                        AccountCategorySection(
                            title: "My Loans",
                            icon: "house.fill",
                            color: Color.teal.opacity(0.7),
                            accounts: [
                                Account(name: "Car Loan", balance: "-$9,200.00", trend: .down),
                                Account(name: "Student Loan", balance: "-$15,500.00", trend: .down)
                            ]
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

struct AccountCategorySection: View {
    let title: String
    let icon: String
    let color: Color
    let accounts: [Account]
    var isHighlighted: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Category button
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(.white)
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 80, height: 80)
                .background(color)
                .cornerRadius(12)
                
                // Account list
                VStack(spacing: 8) {
                    ForEach(accounts) { account in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                Text(account.balance)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            Image(systemName: account.trend == .up ? "arrow.up" : "arrow.down")
                                .font(.caption)
                                .foregroundColor(account.trend == .up ? .green : .red)
                                .frame(width: 24, height: 24)
                                .background(
                                    Circle()
                                        .fill(account.trend == .up ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                )
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHighlighted ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

struct Account: Identifiable {
    let id = UUID()
    let name: String
    let balance: String
    let trend: Trend
    
    enum Trend {
        case up, down
    }
}

#Preview {
    AccountsOverviewView()
} 
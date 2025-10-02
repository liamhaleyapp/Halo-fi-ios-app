import SwiftUI

struct AccountsOverviewView: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Navigation bar
                        HStack {
                            Spacer()
                            
                            Text("Accounts")
                                .font(.largeTitle)
                                .fontWeight(.heavy)
                                .foregroundColor(.white)
                                .padding(.vertical, 8)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 10)
                        
                        // Responsive grid layout for iPad
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                NavigationLink(destination: CheckingAccountsView()) {
                                    LargeNavButton(title: "Checking Accounts", icon: "house.fill", tileColor: Color.gray.opacity(0.7))
                                }
                                
                                NavigationLink(destination: SavingsAccountsView()) {
                                    LargeNavButton(title: "Savings Accounts", icon: "creditcard.fill", tileColor: Color.purple.opacity(0.8))
                                }
                                
                                NavigationLink(destination: CreditCardsView()) {
                                    LargeNavButton(title: "Credit Cards", icon: "creditcard.fill", tileColor: Color.blue)
                                }
                                
                                NavigationLink(destination: InvestmentsView()) {
                                    LargeNavButton(title: "Investments", icon: "chart.line.uptrend.xyaxis", tileColor: Color.blue.opacity(0.9))
                                }
                                
                                NavigationLink(destination: LoansView()) {
                                    LargeNavButton(title: "My Loans", icon: "house.fill", tileColor: Color.teal)
                                }
                            }
                            .padding(.horizontal, max(20, geometry.size.width * 0.1))
                        } else {
                            // iPhone single column layout
                            VStack(spacing: 12) {
                                NavigationLink(destination: CheckingAccountsView()) {
                                    LargeNavButton(title: "Checking Accounts", icon: "house.fill", tileColor: Color.gray.opacity(0.7))
                                }
                                NavigationLink(destination: SavingsAccountsView()) {
                                    LargeNavButton(title: "Savings Accounts", icon: "creditcard.fill", tileColor: Color.purple.opacity(0.8))
                                }
                                NavigationLink(destination: CreditCardsView()) {
                                    LargeNavButton(title: "Credit Cards", icon: "creditcard.fill", tileColor: Color.blue)
                                }
                                NavigationLink(destination: InvestmentsView()) {
                                    LargeNavButton(title: "Investments", icon: "chart.line.uptrend.xyaxis", tileColor: Color.blue.opacity(0.9))
                                }
                                NavigationLink(destination: LoansView()) {
                                    LargeNavButton(title: "My Loans", icon: "house.fill", tileColor: Color.teal)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// Old section components removed in favor of dedicated views

#Preview {
    AccountsOverviewView()
} 
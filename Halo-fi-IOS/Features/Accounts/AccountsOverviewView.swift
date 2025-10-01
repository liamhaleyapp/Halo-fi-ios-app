import SwiftUI

struct AccountsOverviewView: View {
  @Environment(\.presentationMode) var presentationMode
  
  var body: some View {
    NavigationView {
      ZStack {
        Color.black.ignoresSafeArea()
        
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
          
          // Large horizontal navigation buttons
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
          .padding(.bottom, 20)
        }
      }
    }
    .navigationBarHidden(true)
  }
}

#Preview {
  AccountsOverviewView()
}

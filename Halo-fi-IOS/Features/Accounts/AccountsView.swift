import SwiftUI

struct AccountsView: View {
  @Environment(\.dismiss) private var dismiss
  
  // MARK: - State Variables
  @State private var showingLinkNewAccount = false
  @State private var showingInstitutionDetails = false
  @State private var selectedInstitution: FinancialInstitution?
  
  // MARK: - Sample Data
  @State private var institutions: [FinancialInstitution] = MockInstitutions.institutions
  
  var body: some View {
    NavigationView {
      ZStack {
        // Background
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 16) {
          headerView
          
          linkNewAccountSection
          
          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
      }
    }
    .navigationBarHidden(true)
    .sheet(isPresented: $showingLinkNewAccount) {
      LinkNewAccountView()
    }
    .sheet(isPresented: $showingInstitutionDetails) {
      if let institution = selectedInstitution {
        InstitutionDetailsView(institution: institution)
      }
    }
  }
  
  // MARK: - Header View
  private var headerView: some View {
    HStack {
      Button(action: {
        dismiss()
      }) {
        Image(systemName: "chevron.left")
          .font(.title2)
          .foregroundColor(.white)
          .frame(width: 40, height: 40)
          .background(Color.gray.opacity(0.2))
          .clipShape(Circle())
      }
      
      Spacer()
      
      Text("Accounts")
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundColor(.white)
      
      Spacer()
      
      // Invisible spacer to center the title
      Color.clear
        .frame(width: 40, height: 40)
    }
    .padding(.horizontal, 20)
    .padding(.top, 15)
    .padding(.bottom, 20)
  }
  
  // MARK: - Link New Account Section
  private var linkNewAccountSection: some View {
    Button(action: {
      // TODO: Implement account linking logic
    }) {
      HStack {
        Image(systemName: "plus.circle.fill")
          .font(.title2)
          .foregroundColor(.white)
        
        Text("Link New Account")
          .font(.body)
          .foregroundColor(.white)
        
        Spacer()
        
        Image(systemName: "chevron.right")
          .foregroundColor(.gray)
          .font(.caption)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .background(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing))
      .cornerRadius(16)
    }
  }
  
  // MARK: - Connected Institutions Section
  private var connectedInstitutionsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Connected Institutions")
        .font(.headline)
        .foregroundColor(.gray)
        .padding(.horizontal, 20)
      
      ForEach(institutions) { institution in
        institutionCard(institution)
      }
    }
  }
  
  // MARK: - Institution Card
  private func institutionCard(_ institution: FinancialInstitution) -> some View {
    VStack(spacing: 0) {
      // Institution Header
      Button(action: {
        selectedInstitution = institution
        showingInstitutionDetails = true
      }) {
        HStack(spacing: 16) {
          Image(systemName: institution.logo)
            .font(.title2)
            .foregroundColor(.teal)
            .frame(width: 32, height: 32)
          
          VStack(alignment: .leading, spacing: 4) {
            Text(institution.name)
              .font(.body)
              .fontWeight(.medium)
              .foregroundColor(.white)
            
            HStack(spacing: 8) {
              Circle()
                .fill(institution.status.color)
                .frame(width: 8, height: 8)
              
              Text(institution.status.displayText)
                .font(.caption)
                .foregroundColor(.gray)
            }
          }
          
          Spacer()
          
          Image(systemName: "chevron.right")
            .foregroundColor(.gray)
            .font(.caption)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
      }
      
      // Accounts Preview
      VStack(spacing: 6) {
        ForEach(institution.accounts.prefix(2)) { account in
          accountRow(account)
        }
        
        if institution.accounts.count > 2 {
          HStack {
            Text("+\(institution.accounts.count - 2) more accounts")
              .font(.caption)
              .foregroundColor(.gray)
            Spacer()
          }
          .padding(.horizontal, 30)
          .padding(.vertical, 6)
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 12)
    }
  }
  
  // MARK: - Account Row
  private func accountRow(_ account: FinancialAccount) -> some View {
    HStack(spacing: 16) {
      Image(systemName: account.type.icon)
        .font(.caption)
        .foregroundColor(.teal)
        .frame(width: 20, height: 20)
      
      VStack(alignment: .leading, spacing: 2) {
        Text(account.nickname)
          .font(.caption)
          .foregroundColor(.white)
        
        Text(account.type.displayName)
          .font(.caption2)
          .foregroundColor(.gray)
      }
      
      Spacer()
      
      if account.isSynced {
        Text(account.balance.formatted(.currency(code: "USD")))
          .font(.caption)
          .foregroundColor(account.balance >= 0 ? .green : .red)
      } else {
        Text("Not synced")
          .font(.caption)
          .foregroundColor(.gray)
      }
    }
    .padding(.horizontal, 30)
    .padding(.vertical, 12)
    .background(Color.gray.opacity(0.05))
    .cornerRadius(12)
  }
}


// MARK: - Link New Account View (Modal)
struct LinkNewAccountView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var searchText = ""
  @State private var selectedBank: String?
  
  let popularBanks = ["Chase", "Bank of America", "Wells Fargo", "Citibank", "Capital One", "American Express"]
  
  var body: some View {
    NavigationView {
      ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 20) {
          Text("Link New Account")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.top, 20)
          
          VStack(alignment: .leading, spacing: 12) {
            Text("Search for your bank")
              .font(.body)
              .foregroundColor(.white)
            
            TextField("Enter bank name...", text: $searchText)
              .textFieldStyle(.roundedBorder)
          }
          .padding(.horizontal, 20)
          
          VStack(alignment: .leading, spacing: 12) {
            Text("Popular Banks")
              .font(.headline)
              .foregroundColor(.gray)
              .padding(.horizontal, 20)
            
            ForEach(popularBanks, id: \.self) { bank in
              Button(action: {
                selectedBank = bank
              }) {
                HStack {
                  Text(bank)
                    .font(.body)
                    .foregroundColor(.white)
                  Spacer()
                  if selectedBank == bank {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundColor(.teal)
                  }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
                .background(selectedBank == bank ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                .cornerRadius(12)
              }
            }
          }
          
          Spacer()
        }
      }
      .navigationBarHidden(true)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .foregroundColor(.white)
        }
      }
    }
  }
}

// MARK: - Institution Details View (Modal)
struct InstitutionDetailsView: View {
  @Environment(\.dismiss) private var dismiss
  let institution: FinancialInstitution
  
  var body: some View {
    NavigationView {
      ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 20) {
          Text(institution.name)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.top, 20)
          
          VStack(alignment: .leading, spacing: 16) {
            HStack {
              Image(systemName: institution.logo)
                .font(.title)
                .foregroundColor(.teal)
              
              VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                  .font(.caption)
                  .foregroundColor(.gray)
                
                HStack(spacing: 8) {
                  Circle()
                    .fill(institution.status.color)
                    .frame(width: 8, height: 8)
                  
                  Text(institution.status.displayText)
                    .font(.body)
                    .foregroundColor(.white)
                }
              }
              
              Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
            
            Text("Accounts")
              .font(.headline)
              .foregroundColor(.gray)
              .padding(.horizontal, 20)
            
            ForEach(institution.accounts) { account in
              accountDetailRow(account)
            }
          }
          
          Spacer()
        }
      }
      .navigationBarHidden(true)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .foregroundColor(.white)
        }
      }
    }
  }
  
  private func accountDetailRow(_ account: FinancialAccount) -> some View {
    HStack(spacing: 16) {
      Image(systemName: account.type.icon)
        .font(.title3)
        .foregroundColor(.teal)
        .frame(width: 24, height: 24)
      
      VStack(alignment: .leading, spacing: 4) {
        Text(account.nickname)
          .font(.body)
          .fontWeight(.medium)
          .foregroundColor(.white)
        
        Text(account.name)
          .font(.caption)
          .foregroundColor(.gray)
      }
      
      Spacer()
      
      VStack(alignment: .trailing, spacing: 4) {
        if account.isSynced {
          Text(account.balance.formatted(.currency(code: "USD")))
            .font(.body)
            .foregroundColor(account.balance >= 0 ? .green : .red)
        } else {
          Text("Not synced")
            .font(.caption)
            .foregroundColor(.gray)
        }
        
        Text(account.type.displayName)
          .font(.caption2)
          .foregroundColor(.gray)
      }
    }
    .padding(.horizontal, 30)
    .padding(.vertical, 20)
    .background(Color.gray.opacity(0.1))
    .cornerRadius(16)
  }
}

#Preview {
  AccountsView()
}

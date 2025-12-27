//
//  AccountsOverviewView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

enum AccountViewMode {
  case institutions
  case accountTypes
}

struct AccountsOverviewView: View {
  @Environment(BankDataManager.self) private var bankDataManager
  @State private var showingPlaidOnboarding = false
  @State private var viewMode: AccountViewMode = .institutions
  @State private var isLoadingLinkedItems = false
  @State private var isLoadingAccounts = false
  @State private var selectedItemId: String?
  @State private var hasAppeared = false
  @State private var navigationPath = NavigationPath()
  
  var body: some View {
    NavigationStack(path: $navigationPath) {
      ZStack {
        Color.black.ignoresSafeArea()
        
        ScrollView {
          VStack(spacing: 20) {

            // Summary Section
            if hasData {
              summarySection
            }
            
            // Filter Toggle
            if hasData {
              filterToggleSection
            }
            
            // Content based on view mode
            if isLoadingLinkedItems && !hasAppeared {
              loadingView
            } else if hasData {
              contentView
            } else {
              emptyStateView
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 20)
          .padding(.bottom, 100)
        }
      }
      .navigationTitle("Accounts")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            showingPlaidOnboarding = true
          } label: {
            Image(systemName: "plus.app")
          }
          .accessibilityLabel("Add bank account")
          .accessibilityHint("Connect a new bank account")
        }
      }
      .onAppear {
        if !hasAppeared {
          hasAppeared = true
          Task {
            // Trigger auto-refresh of accounts if stale (uses persisted linkedItems)
            await bankDataManager.refreshIfStale()
            await loadInitialData()
          }
        }
      }
      .sheet(isPresented: $showingPlaidOnboarding) {
        PlaidOnboardingView()
      }
      .navigationDestination(for: ConnectedItem.self) { item in
        InstitutionAccountsView(item: item)
      }
    }
  }
  
  // MARK: - Summary Section
  
  private var summarySection: some View {
    let totalBalance = bankDataManager.totalBalance()
    let accountCount = bankDataManager.totalAccountCount()
    let currency = bankDataManager.accountsByItemId.values.flatMap { $0 }.first?.currency ?? "USD"
    
    return VStack(spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Total Balance")
            .font(.subheadline)
            .foregroundColor(.gray)
            .accessibilityAddTraits(.isHeader)
          
          Text(CurrencyFormatter.format(totalBalance, currency: currency))
            .font(.title)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .accessibilityLabel("Total balance, \(CurrencyFormatter.format(totalBalance, currency: currency))")
        }
        
        Spacer()
        
        VStack(alignment: .trailing, spacing: 4) {
          Text("Accounts")
            .font(.subheadline)
            .foregroundColor(.gray)
            .accessibilityAddTraits(.isHeader)
          
          Text("\(accountCount)")
            .font(.title)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .accessibilityLabel("\(accountCount) account\(accountCount == 1 ? "" : "s")")
        }
      }
      .padding(20)
      .background(Color.gray.opacity(0.1))
      .cornerRadius(16)
    }
  }
  
  // MARK: - Filter Toggle Section
  
  private var filterToggleSection: some View {
    Picker("View Mode", selection: $viewMode) {
      Text("By Institution").tag(AccountViewMode.institutions)
        .accessibilityLabel("View accounts by institution")
      Text("Accounts").tag(AccountViewMode.accountTypes)
        .accessibilityLabel("View all accounts by type")
    }
    .pickerStyle(.segmented)
    .accessibilityLabel("Account view mode")
    .accessibilityHint("Switch between viewing by institution or all accounts grouped by type")
  }
  
  // MARK: - Content View
  
  @ViewBuilder
  private var contentView: some View {
    switch viewMode {
    case .institutions:
      institutionsView
    case .accountTypes:
      accountTypesView
    }
  }
  
  // MARK: - Institutions View
  
  private var institutionsView: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let linkedItems = bankDataManager.linkedItems, !linkedItems.isEmpty {
        Text("Linked Institutions")
          .font(.headline)
          .foregroundColor(.gray)
          .accessibilityAddTraits(.isHeader)
          .padding(.top, 8)
        
        ForEach(linkedItems, id: \.itemId) { item in
          NavigationLink(value: item) {
            AccessibleInstitutionCard(
              item: item,
              accounts: bankDataManager.accountsByItemId[item.plaidItemId],
              isLoading: isLoadingAccounts && selectedItemId == item.plaidItemId
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
  
  // MARK: - Account Types View
  
  private var accountTypesView: some View {
    AccountTypeFilterView(
      accountsByType: bankDataManager.accountsGroupedByType()
    )
  }
  
  // MARK: - Loading View
  
  private var loadingView: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.2)
        .accessibilityLabel("Loading accounts")
      
      Text("Loading accounts...")
        .font(.body)
        .foregroundColor(.gray)
        .accessibilityLabel("Loading accounts, please wait")
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }
  
  // MARK: - Empty State View
  
  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Image(systemName: "building.2")
        .font(.system(size: 48))
        .foregroundColor(.gray.opacity(0.5))
        .accessibilityHidden(true)
      
      Text("No Accounts Linked")
        .font(.headline)
        .foregroundColor(.white)
        .accessibilityAddTraits(.isHeader)
      
      Text("Connect your bank accounts to get started")
        .font(.subheadline)
        .foregroundColor(.gray)
        .multilineTextAlignment(.center)
        .accessibilityLabel("No accounts linked. Connect your bank accounts to get started.")
      
      Button {
        showingPlaidOnboarding = true
      } label: {
        HStack {
          Image(systemName: "plus.circle.fill")
            .accessibilityHidden(true)
          Text("Link New Account")
        }
        .font(.body)
        .fontWeight(.semibold)
        .foregroundColor(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing))
        .cornerRadius(12)
      }
      .accessibilityLabel("Link new account")
      .accessibilityHint("Double tap to connect a new bank account")
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }
  
  // MARK: - Computed Properties
  
  private var hasData: Bool {
    guard let linkedItems = bankDataManager.linkedItems, !linkedItems.isEmpty else {
      return false
    }
    return true
  }
  
  // MARK: - Data Loading
  
  private func loadInitialData() async {
    isLoadingLinkedItems = true

    // Fetch linked items if we don't have them
    if bankDataManager.linkedItems == nil {
      // Try to fetch accounts which may trigger linked items fetch
      // For now, we'll rely on the linkedItems being set during onboarding
      // If they're not set, we'll show empty state
      print("🔵 AccountsOverviewView: Checking for linked items")
    }

    // If we have linked items but no accounts loaded, fetch accounts for the first item
    if let linkedItems = bankDataManager.linkedItems,
       !linkedItems.isEmpty,
       bankDataManager.accountsByItemId.isEmpty {
      // Load accounts for the first institution to show summary
      let firstItem = linkedItems[0]
      if bankDataManager.accountsByItemId[firstItem.plaidItemId] == nil {
        await fetchAccountsForItem(firstItem)
      }
    }

    isLoadingLinkedItems = false
  }
  
  private func fetchAccountsForItem(_ item: ConnectedItem) async {
    guard !isLoadingAccounts else { return }
    
    if bankDataManager.accountsByItemId[item.plaidItemId] != nil {
      print("🔵 AccountsOverviewView: Accounts already fetched for item \(item.plaidItemId)")
      return
    }
    
    selectedItemId = item.plaidItemId
    isLoadingAccounts = true
    
    do {
      print("🔵 AccountsOverviewView: Fetching accounts for item \(item.plaidItemId) (\(item.institutionName))")
      let response = try await bankDataManager.fetchAccountsForItem(itemId: item.plaidItemId)
      
      await MainActor.run {
        bankDataManager.accountsByItemId[item.plaidItemId] = response.accounts
        isLoadingAccounts = false
        selectedItemId = nil
        print("✅ AccountsOverviewView: Fetched \(response.accounts.count) accounts for \(item.institutionName)")
      }
    } catch {
      await MainActor.run {
        isLoadingAccounts = false
        selectedItemId = nil
        print("❌ AccountsOverviewView: Error fetching accounts: \(error)")
        // Errors are now handled in InstitutionAccountsView, not here
      }
    }
  }
}

#Preview {
  AccountsOverviewView()
    .environment(BankDataManager())
}

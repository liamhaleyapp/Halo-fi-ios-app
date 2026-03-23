//
//  AccountsOverviewView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct AccountsOverviewView: View {
  @Environment(BankDataManager.self) private var bankDataManager
  @State private var showingPlaidOnboarding = false
  @State private var isLoadingLinkedItems = false
  @State private var hasAppeared = false
  @State private var navigationPath = NavigationPath()
  @State private var searchText = ""
  @State private var isRefreshing = false

  var body: some View {
    NavigationStack(path: $navigationPath) {
      ZStack {
        Color.black.ignoresSafeArea()

        if isLoadingLinkedItems && !hasAppeared {
          loadingView
        } else if hasData {
          institutionsList
        } else {
          emptyStateView
        }
      }
      .navigationTitle("Accounts")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
          Button {
            Task {
              isRefreshing = true
              await bankDataManager.refreshLinkedItems()
              isRefreshing = false
            }
          } label: {
            if isRefreshing {
              ProgressView()
            } else {
              Image(systemName: "arrow.clockwise")
            }
          }
          .disabled(isRefreshing)
          .accessibilityLabel("Refresh accounts")

          Button {
            showingPlaidOnboarding = true
          } label: {
            Image(systemName: "plus.app")
          }
          .accessibilityLabel("Add account")
          .accessibilityHint("Opens secure bank linking flow")
        }
      }
      .onAppear {
        if !hasAppeared {
          hasAppeared = true
          Task {
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

  // MARK: - Institutions List

  private var institutionsList: some View {
    ScrollView {
      LazyVStack(spacing: 12) {
        // Search field
        searchField
          .padding(.bottom, 8)

        // Connected institutions section
        if !connectedInstitutions.isEmpty {
          Section {
            ForEach(connectedInstitutions, id: \.itemId) { item in
              institutionRow(item)
            }
          } header: {
            sectionHeader("Connected", count: connectedInstitutions.count)
          }
        }

        // Needs attention section
        if !needsAttentionInstitutions.isEmpty {
          Section {
            ForEach(needsAttentionInstitutions, id: \.itemId) { item in
              institutionRow(item)
            }
          } header: {
            sectionHeader("Needs Attention", count: needsAttentionInstitutions.count)
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 20)
      .padding(.bottom, 100)
    }
  }

  // MARK: - Search Field

  private var searchField: some View {
    HStack(spacing: 12) {
      Image(systemName: "magnifyingglass")
        .foregroundColor(.gray)
        .accessibilityHidden(true)

      TextField("Search institutions", text: $searchText)
        .foregroundColor(.white)
        .autocorrectionDisabled()
        .accessibilityLabel("Search institutions")
        .accessibilityHint("Type to filter your linked banks")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color.gray.opacity(0.15))
    .cornerRadius(12)
  }

  // MARK: - Section Header

  private func sectionHeader(_ title: String, count: Int) -> some View {
    HStack {
      Text(title)
        .font(.headline)
        .foregroundColor(.gray)

      Spacer()

      Text("\(count)")
        .font(.subheadline)
        .foregroundColor(.gray.opacity(0.7))
    }
    .padding(.top, 16)
    .padding(.bottom, 8)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
    .accessibilityLabel("\(title), \(count) institution\(count == 1 ? "" : "s")")
  }

  // MARK: - Institution Row

  private func institutionRow(_ item: ConnectedItem) -> some View {
    NavigationLink(value: item) {
      AccessibleInstitutionCard(
        item: item,
        accounts: bankDataManager.accountsByItemId[item.itemId],
        isLoading: false
      )
    }
    .buttonStyle(HapticPlainButtonStyle())
  }

  // MARK: - Filtered Institutions

  private var filteredInstitutions: [ConnectedItem] {
    guard let linkedItems = bankDataManager.linkedItems else { return [] }

    if searchText.isEmpty {
      return linkedItems
    }

    return linkedItems.filter { item in
      item.institutionName.localizedCaseInsensitiveContains(searchText)
    }
  }

  private var connectedInstitutions: [ConnectedItem] {
    filteredInstitutions.filter { $0.isActive }
  }

  private var needsAttentionInstitutions: [ConnectedItem] {
    filteredInstitutions.filter { !$0.isActive }
  }

  // MARK: - Loading View

  private var loadingView: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.2)
        .tint(.white)

      Text("Loading institutions...")
        .font(.body)
        .foregroundColor(.gray)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Loading institutions, please wait")
  }

  // MARK: - Empty State View

  private var emptyStateView: some View {
    VStack(spacing: 20) {
      Image(systemName: "building.2")
        .font(.system(size: 56))
        .foregroundColor(.gray.opacity(0.5))
        .accessibilityHidden(true)

      VStack(spacing: 8) {
        Text("No Linked Institutions")
          .font(.title3)
          .fontWeight(.semibold)
          .foregroundColor(.white)

        Text("Connect your bank to view accounts and transactions")
          .font(.body)
          .foregroundColor(.gray)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 40)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("No linked institutions. Connect your bank to view accounts and transactions.")

      Button {
        showingPlaidOnboarding = true
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "plus.circle.fill")
            .accessibilityHidden(true)
          Text("Link Your First Account")
        }
        .font(.body)
        .fontWeight(.semibold)
        .foregroundColor(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing))
        .cornerRadius(14)
      }
      .accessibilityLabel("Link your first account")
      .accessibilityHint("Opens secure bank linking flow")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.bottom, 100)
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

    if bankDataManager.linkedItems == nil {
      Logger.info("AccountsOverviewView: Checking for linked items")
    }

    isLoadingLinkedItems = false
  }
}

#Preview {
  AccountsOverviewView()
    .environment(BankDataManager())
}

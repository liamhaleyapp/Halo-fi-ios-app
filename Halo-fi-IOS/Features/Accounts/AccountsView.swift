import SwiftUI

struct AccountsView: View {
  @Environment(\.dismiss) private var dismiss
  
  // MARK: - State Variables
  @State private var showingLinkNewAccount = false
  
  var body: some View {
    NavigationView {
      ZStack {
        // Background
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 16) {
          headerView
          
          LinkNewAccountSection {
            showingLinkNewAccount = true
          }
          
          // TODO: Add institutions list here when ready
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
  
}


#Preview {
  AccountsView()
}

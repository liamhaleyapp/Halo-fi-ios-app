import SwiftUI

struct LoansView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("My Loans")
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                
                List {
                    Section(header: Text("Connected").foregroundColor(.gray)) {
                        AccountRowSimple(name: "Car Loan", balance: -9200.00)
                        AccountRowSimple(name: "Student Loan", balance: -15500.00)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView { LoansView() }
}



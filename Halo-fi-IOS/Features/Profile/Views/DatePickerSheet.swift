//
//  DatePickerSheet.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Date Picker Sheet
struct DatePickerSheet: View {
  @Binding var selectedDate: Date
  @Environment(\.presentationMode) var presentationMode
  
  var body: some View {
    NavigationView {
      ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 24) {
          Text("Select Date of Birth")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.top, 20)
          
          DatePicker(
            "Date of Birth",
            selection: $selectedDate,
            displayedComponents: .date
          )
          .datePickerStyle(WheelDatePickerStyle())
          .accentColor(.blue)
          .colorScheme(.dark)
          
          ActionButton(
            title: "Done",
            gradient: LinearGradient(
              colors: [Color.blue, Color.purple],
              startPoint: .leading,
              endPoint: .trailing
            )
          ) {
            presentationMode.wrappedValue.dismiss()
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 20)
        }
      }
    }
    .navigationBarHidden(true)
  }
}

// MARK: - Preview
#Preview {
  DatePickerSheet(selectedDate: .constant(Date()))
}

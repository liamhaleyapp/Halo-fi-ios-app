//
//  DateOfBirthField.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct DateOfBirthField: View {
  let selectedDate: Date
  let onTap: () -> Void
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "calendar")
          .font(.title3)
          .foregroundColor(.blue)
          .frame(width: 20, height: 20)
        
        Text("Date of Birth")
          .font(.headline)
          .foregroundColor(.white)
        
        Spacer()
      }
      
      Button(action: onTap) {
        HStack {
          Text(selectedDate, style: .date)
            .foregroundColor(.white)
            .padding(.leading, 16)
          
          Spacer()
          
          Image(systemName: "chevron.right")
            .foregroundColor(.gray)
            .padding(.trailing, 16)
        }
        .frame(height: 50)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
      }
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    DateOfBirthField(selectedDate: Date()) {}
      .padding()
  }
}

//
//  PlanOptionCard.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/18/25.
//
import SwiftUI

struct PlanOptionCard: View {
  let plan: SubscriptionPlan
  let isSelected: Bool
  let billingCycle: BillingCycle
  let onSelect: () -> Void
  
  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 16) {
        // Plan Icon
        Image(systemName: plan.iconName)
          .font(.title2)
          .foregroundColor(isSelected ? .white : .purple)
          .frame(width: 40, height: 40)
          .background(
            isSelected ?
            AnyShapeStyle(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)) :
              AnyShapeStyle(Color.purple.opacity(0.1))
          )
          .clipShape(Circle())
        
        // Plan Details
        VStack(alignment: .leading, spacing: 4) {
          Text(plan.displayName)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
          
          Text(plan.description)
            .font(.caption)
            .foregroundColor(.gray)
            .lineLimit(2)
          
          Text(billingCycle == .monthly ? plan.monthlyPrice : plan.yearlyPrice)
            .font(.title3)
            .fontWeight(.bold)
            .foregroundColor(.purple)
        }
        
        Spacer()
        
        // Selection Indicator
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .font(.title2)
            .foregroundColor(.purple)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(isSelected ? Color.purple.opacity(0.1) : Color.gray.opacity(0.08))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
      )
    }
    .buttonStyle(HapticPlainButtonStyle())
  }
}

//
//  Date+RelativeDescription.swift
//  Halo-fi-IOS
//
//  Extension for human-readable relative date descriptions.
//

import Foundation

extension Date {
    /// Returns a human-readable relative description like "Updated 2m ago" or "Just now"
    var relativeDescription: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "Updated \(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "Updated \(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            if days == 1 {
                return "Updated yesterday"
            } else {
                return "Updated \(days)d ago"
            }
        }
    }
}

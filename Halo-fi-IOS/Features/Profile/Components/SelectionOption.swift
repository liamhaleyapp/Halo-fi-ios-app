//
//  SelectionOption.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

struct SelectionOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let disabledReason: String?

    init(id: String, title: String, subtitle: String? = nil, disabledReason: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.disabledReason = disabledReason
    }
}

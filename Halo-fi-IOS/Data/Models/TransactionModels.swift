//
//  TransactionModels.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Transaction Location
struct TransactionLocation: Codable {
    // Dynamic properties that can vary
    let additionalProperties: [String: AnyCodable]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var properties: [String: AnyCodable] = [:]
        
        for key in container.allKeys {
            if let value = try? container.decode(AnyCodable.self, forKey: key) {
                properties[key.stringValue] = value
            }
        }
        
        self.additionalProperties = properties.isEmpty ? nil : properties
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)
        if let properties = additionalProperties {
            for (key, value) in properties {
                if let codingKey = DynamicCodingKeys(stringValue: key) {
                    try container.encode(value, forKey: codingKey)
                }
            }
        }
    }
    
    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?
        
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        
        init?(intValue: Int) {
            return nil
        }
    }
}

// MARK: - Personal Finance Category
struct PersonalFinanceCategory: Codable {
    // Dynamic properties that can vary
    let additionalProperties: [String: AnyCodable]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var properties: [String: AnyCodable] = [:]
        
        for key in container.allKeys {
            if let value = try? container.decode(AnyCodable.self, forKey: key) {
                properties[key.stringValue] = value
            }
        }
        
        self.additionalProperties = properties.isEmpty ? nil : properties
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)
        if let properties = additionalProperties {
            for (key, value) in properties {
                if let codingKey = DynamicCodingKeys(stringValue: key) {
                    try container.encode(value, forKey: codingKey)
                }
            }
        }
    }
    
    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?
        
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        
        init?(intValue: Int) {
            return nil
        }
    }
}

// MARK: - Transaction Counterparty
struct TransactionCounterparty: Codable {
    // Dynamic properties that can vary
    let additionalProperties: [String: AnyCodable]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var properties: [String: AnyCodable] = [:]
        
        for key in container.allKeys {
            if let value = try? container.decode(AnyCodable.self, forKey: key) {
                properties[key.stringValue] = value
            }
        }
        
        self.additionalProperties = properties.isEmpty ? nil : properties
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)
        if let properties = additionalProperties {
            for (key, value) in properties {
                if let codingKey = DynamicCodingKeys(stringValue: key) {
                    try container.encode(value, forKey: codingKey)
                }
            }
        }
    }
    
    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?
        
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        
        init?(intValue: Int) {
            return nil
        }
    }
}

// MARK: - Transaction
struct Transaction: Codable, Identifiable {
    let amount: Double
    let currency: String
    let transactionDate: String
    let name: String
    let merchantName: String?
    let category: [String]?
    let pending: Bool
    let location: TransactionLocation?
    let paymentChannel: String?
    let transactionType: String?
    let transactionDatetime: String?
    let authorizedDate: String?
    let authorizedDatetime: String?
    let personalFinanceCategory: PersonalFinanceCategory?
    let personalFinanceCategoryIconUrl: String?
    let merchantEntityId: String?
    let logoUrl: String?
    let website: String?
    let counterparties: [TransactionCounterparty]?
    let pendingTransactionId: String?
    let checkNumber: String?
    let transactionCode: String?
    let idTransaction: String
    let accountId: String
    let plaidTransactionId: String?
    let isActive: Bool
    let lastSync: String?
    let createdAt: String
    let updatedAt: String
    
    var id: String {
        return idTransaction
    }
    
    enum CodingKeys: String, CodingKey {
        case amount
        case currency
        case transactionDate = "transaction_date"
        case name
        case merchantName = "merchant_name"
        case category
        case pending
        case location
        case paymentChannel = "payment_channel"
        case transactionType = "transaction_type"
        case transactionDatetime = "transaction_datetime"
        case authorizedDate = "authorized_date"
        case authorizedDatetime = "authorized_datetime"
        case personalFinanceCategory = "personal_finance_category"
        case personalFinanceCategoryIconUrl = "personal_finance_category_icon_url"
        case merchantEntityId = "merchant_entity_id"
        case logoUrl = "logo_url"
        case website
        case counterparties
        case pendingTransactionId = "pending_transaction_id"
        case checkNumber = "check_number"
        case transactionCode = "transaction_code"
        case idTransaction = "id_transaction"
        case accountId = "account_id"
        case plaidTransactionId = "plaid_transaction_id"
        case isActive = "is_active"
        case lastSync = "last_sync"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

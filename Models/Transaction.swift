//
//  Transaction.swift
//  MLBCallups
//
//  Created by Nicolas Richards on 2/20/26.
//

import Foundation

struct TransactionsResponse: Codable, Sendable {
    let transactions: [Transaction]
}

struct Transaction: Codable, Sendable {
    let person: TransactionPerson?
    let toTeam: TransactionTeam?
    let fromTeam: TransactionTeam?
    let typeCode: String?
    let description: String?
}

struct TransactionPerson: Codable, Sendable {
    let id: Int
    let fullName: String?
}

struct TransactionTeam: Codable, Sendable {
    let id: Int
    let name: String?
}

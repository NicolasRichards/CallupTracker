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

extension Transaction {
    /// True if this transaction looks like a genuine minors-to-MLB call-up.
    ///
    /// The rule itself lives in CallupRules so the app, the background refresh,
    /// and the widget all apply exactly the same test.
    var isLikelyCallup: Bool {
        CallupRules.isLikelyCallup(typeCode: typeCode,
                                   toTeamID: toTeam?.id,
                                   fromTeamID: fromTeam?.id,
                                   description: description)
    }
}

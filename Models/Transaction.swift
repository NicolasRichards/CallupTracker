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
    /// True if this transaction looks like a genuine minors→MLB callup.
    ///
    /// CU = recalled to the active 26-man roster (player already on 40-man).
    /// SE = selected from minors — can be a true active callup OR a 40-man-only
    ///      addition; callers that need certainty must additionally verify SE
    ///      transactions against the live active roster.
    ///
    /// Shared by TrackerViewModel and NotificationManager so the app and its
    /// notifications always agree on what counts as a callup.
    var isLikelyCallup: Bool {
        guard let code = typeCode, code == "CU" || code == "SE" else { return false }
        guard let toID = toTeam?.id, MLBAPIClient.mlbTeamIDs.contains(toID) else { return false }

        if let fromID = fromTeam?.id {
            // fromTeam is provided — it must be a minor-league team (not an MLB club).
            // If it's an MLB team, this is a trade/DFA claim, not a callup.
            return !MLBAPIClient.mlbTeamIDs.contains(fromID)
        }

        // No fromTeam in API data — fall back to description heuristic.
        // Accept only if the description mentions " from " but does NOT name
        // an MLB club (e.g. "recalled from Iowa Cubs" passes, but
        // "traded from Los Angeles Dodgers" does not).
        guard let desc = description else { return false }
        let lower = desc.lowercased()
        guard lower.contains(" from ") else { return false }
        let mentionsMLBTeam = MLBAPIClient.allTeams.contains { lower.contains($0.name.lowercased()) }
        return !mentionsMLBTeam
    }
}

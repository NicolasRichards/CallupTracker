//
//  MLBAPIClient.swift
//  MLBCallups
//
//  Created by Nicolas Richards on 2/20/26.
//

import Foundation

struct MLBTeam: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let abbreviation: String
}

struct MLBAPIClient: Sendable {

    static let shared = MLBAPIClient()

    private let baseURL = "https://statsapi.mlb.com/api/v1"

    /// Both derive from CallupRules, which the widget extension also compiles,
    /// so the app and the widget can never drift apart on club membership.
    static let mlbTeamIDs: Set<Int> = CallupRules.mlbTeamIDs

    static let allTeams: [MLBTeam] = CallupRules.clubs.map {
        MLBTeam(id: $0.id, name: $0.name, abbreviation: $0.abbreviation)
    }

    // MARK: - Transactions

    func fetchTransactions(for dateString: String) async throws -> [Transaction] {
        let urlString = "\(baseURL)/transactions?startDate=\(dateString)&endDate=\(dateString)"
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        return try JSONDecoder().decode(TransactionsResponse.self, from: data).transactions
    }

    // MARK: - Player Info

    func fetchPlayerInfo(playerID: Int) async throws -> PlayerInfo? {
        let urlString = "\(baseURL)/people/\(playerID)?hydrate=currentTeam,transactions"
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        return try JSONDecoder().decode(PeopleResponse.self, from: data).people.first
    }

    // MARK: - Career Stats

    func fetchCareerHitting(playerID: Int) async throws -> StatLine? {
        try await fetchCareerStats(playerID: playerID, group: "hitting")
    }

    func fetchCareerPitching(playerID: Int) async throws -> StatLine? {
        try await fetchCareerStats(playerID: playerID, group: "pitching")
    }

    private func fetchCareerStats(playerID: Int, group: String) async throws -> StatLine? {
        let urlString = "\(baseURL)/people/\(playerID)/stats?stats=career&group=\(group)&sportId=1"
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let groups = try JSONDecoder().decode(StatsResponse.self, from: data).stats
        guard let firstGroup = groups.first else { return nil }
        // Prefer MLB regular season split
        if let mlbRegular = firstGroup.splits.first(where: { $0.sport?.id == 1 && $0.gameType == "R" }) {
            return mlbRegular.stat
        }
        return firstGroup.splits.first?.stat
    }

    // MARK: - Active Roster

    /// Returns the set of player IDs currently on the active 26-man roster for a team.
    func fetchActiveRosterIDs(teamID: Int) async throws -> Set<Int> {
        let urlString = "\(baseURL)/teams/\(teamID)/roster?rosterType=active"
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let roster = try JSONDecoder().decode(RosterResponse.self, from: data)
        return Set(roster.roster.map { $0.person.id })
    }

    // MARK: - Headshot URL

    static func headshotURL(for playerID: Int) -> URL? {
        URL(string: "https://img.mlbstatic.com/mlb-photos/image/upload/d_people:generic:headshot:67:current.png/w_213,q_auto:best/v1/people/\(playerID)/headshot/67/current")
    }

    // MARK: - Helpers

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw APIError.httpError(http.statusCode) }
    }
}

// MARK: - Roster Response

private struct RosterResponse: Decodable {
    let roster: [RosterEntry]
}

private struct RosterEntry: Decodable {
    let person: RosterPerson
}

private struct RosterPerson: Decodable {
    let id: Int
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code): return "Server returned HTTP \(code)"
        }
    }
}


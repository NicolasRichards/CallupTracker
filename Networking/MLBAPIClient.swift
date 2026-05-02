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

    static let mlbTeamIDs: Set<Int> = [
        108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121,
        133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146,
        147, 158
    ]

    static let allTeams: [MLBTeam] = [
        .init(id: 109, name: "Arizona Diamondbacks",   abbreviation: "ARI"),
        .init(id: 144, name: "Atlanta Braves",          abbreviation: "ATL"),
        .init(id: 110, name: "Baltimore Orioles",       abbreviation: "BAL"),
        .init(id: 111, name: "Boston Red Sox",          abbreviation: "BOS"),
        .init(id: 112, name: "Chicago Cubs",            abbreviation: "CHC"),
        .init(id: 145, name: "Chicago White Sox",       abbreviation: "CWS"),
        .init(id: 113, name: "Cincinnati Reds",         abbreviation: "CIN"),
        .init(id: 114, name: "Cleveland Guardians",     abbreviation: "CLE"),
        .init(id: 115, name: "Colorado Rockies",        abbreviation: "COL"),
        .init(id: 116, name: "Detroit Tigers",          abbreviation: "DET"),
        .init(id: 117, name: "Houston Astros",          abbreviation: "HOU"),
        .init(id: 118, name: "Kansas City Royals",      abbreviation: "KC"),
        .init(id: 108, name: "Los Angeles Angels",      abbreviation: "LAA"),
        .init(id: 119, name: "Los Angeles Dodgers",     abbreviation: "LAD"),
        .init(id: 146, name: "Miami Marlins",           abbreviation: "MIA"),
        .init(id: 158, name: "Milwaukee Brewers",       abbreviation: "MIL"),
        .init(id: 142, name: "Minnesota Twins",         abbreviation: "MIN"),
        .init(id: 121, name: "New York Mets",           abbreviation: "NYM"),
        .init(id: 147, name: "New York Yankees",        abbreviation: "NYY"),
        .init(id: 133, name: "Oakland Athletics",       abbreviation: "OAK"),
        .init(id: 143, name: "Philadelphia Phillies",   abbreviation: "PHI"),
        .init(id: 134, name: "Pittsburgh Pirates",      abbreviation: "PIT"),
        .init(id: 135, name: "San Diego Padres",        abbreviation: "SD"),
        .init(id: 137, name: "San Francisco Giants",    abbreviation: "SF"),
        .init(id: 136, name: "Seattle Mariners",        abbreviation: "SEA"),
        .init(id: 138, name: "St. Louis Cardinals",     abbreviation: "STL"),
        .init(id: 139, name: "Tampa Bay Rays",          abbreviation: "TB"),
        .init(id: 140, name: "Texas Rangers",           abbreviation: "TEX"),
        .init(id: 141, name: "Toronto Blue Jays",       abbreviation: "TOR"),
        .init(id: 120, name: "Washington Nationals",    abbreviation: "WSH"),
    ]

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

// MARK: - Innings Parsing

func parseInnings(_ ipString: String?) -> Double {
    guard let ip = ipString, !ip.isEmpty else { return 0.0 }
    let parts = ip.split(separator: ".")
    guard let full = Double(parts[0]) else { return 0.0 }
    let thirds = parts.count > 1 ? (Double(parts[1]) ?? 0.0) : 0.0
    return full + (thirds / 3.0)
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


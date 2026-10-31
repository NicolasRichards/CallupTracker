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
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

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
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        return try JSONDecoder().decode(TransactionsResponse.self, from: data).transactions
    }

    // MARK: - Player Info

    func fetchPlayerInfo(playerID: Int) async throws -> PlayerInfo? {
        let urlString = "\(baseURL)/people/\(playerID)?hydrate=currentTeam,transactions"
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        return try JSONDecoder().decode(PeopleResponse.self, from: data).people.first
    }

    // MARK: - Career Stats

    /// Career MLB stats. With `through`, only games up to and including that
    /// "yyyy-MM-dd" date count, so a past date's card isn't shaped by games played since.
    func fetchCareerHitting(playerID: Int, through: String? = nil) async throws -> StatLine? {
        try await fetchStats(playerID: playerID, group: "hitting", from: through == nil ? nil : "1900-01-01", through: through)
    }

    func fetchCareerPitching(playerID: Int, through: String? = nil) async throws -> StatLine? {
        try await fetchStats(playerID: playerID, group: "pitching", from: through == nil ? nil : "1900-01-01", through: through)
    }

    // MARK: - Current-Year Stats

    /// Returns the season StatLine for a player (MLB regular season only), optionally
    /// limited to games through `through`. Games played > 0 means the player has
    /// appeared in an MLB game that year, a reliable signal of active-roster time.
    func fetchCurrentYearStats(playerID: Int, group: String, year: Int, through: String? = nil) async throws -> StatLine? {
        guard let through else {
            return try await fetchStats(playerID: playerID, group: group, season: year)
        }
        let start = "\(year)-01-01"
        guard through >= start else { return nil }
        return try await fetchStats(playerID: playerID, group: group, from: start, through: through)
    }

    private func fetchStats(playerID: Int, group: String, season: Int? = nil,
                            from: String? = nil, through: String? = nil) async throws -> StatLine? {
        var urlString = "\(baseURL)/people/\(playerID)/stats?group=\(group)&sportId=1"
        if let through, let from {
            urlString += "&stats=byDateRange&startDate=\(from)&endDate=\(through)"
        } else if let season {
            urlString += "&stats=season&season=\(season)"
        } else {
            urlString += "&stats=career"
        }
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        let groups = try JSONDecoder().decode(StatsResponse.self, from: data).stats
        guard let firstGroup = groups.first else { return nil }
        // Prefer MLB regular season split
        if let mlbRegular = firstGroup.splits.first(where: { $0.sport?.id == 1 && $0.gameType == "R" }) {
            return mlbRegular.stat
        }
        // byDateRange returns one split per team plus an all-teams total (sport id 0).
        if let total = firstGroup.splits.first(where: { $0.sport?.id == 0 }) {
            return total.stat
        }
        return firstGroup.splits.first?.stat
    }

    // MARK: - Active Roster

    /// Returns the set of player IDs on the active 26-man roster for a team,
    /// as of `date` ("yyyy-MM-dd") when given, otherwise now.
    func fetchActiveRosterIDs(teamID: Int, date: String? = nil) async throws -> Set<Int> {
        var urlString = "\(baseURL)/teams/\(teamID)/roster?rosterType=active"
        if let date { urlString += "&date=\(date)" }
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        let roster = try JSONDecoder().decode(RosterResponse.self, from: data)
        return Set(roster.roster.map { $0.person.id })
    }

    // MARK: - Season Dates

    /// The first regular-season day through the last postseason day of `year`,
    /// as "yyyy-MM-dd" strings.
    func fetchSeasonDates(year: Int) async throws -> ClosedRange<String> {
        let urlString = "\(baseURL)/seasons/\(year)?sportId=1"
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        guard let season = try JSONDecoder().decode(SeasonsResponse.self, from: data).seasons.first,
              let start = season.regularSeasonStartDate,
              let end = season.postSeasonEndDate ?? season.regularSeasonEndDate,
              start <= end else { throw APIError.invalidResponse }
        return start...end
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

// MARK: - Seasons Response

private struct SeasonsResponse: Decodable {
    let seasons: [Season]
}

private struct Season: Decodable {
    let regularSeasonStartDate: String?
    let regularSeasonEndDate: String?
    let postSeasonEndDate: String?
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


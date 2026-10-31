//
//  CallupFeed.swift
//  CallupTracker
//
//  The call-up pipeline steps shared by the app, its notifications, and the widget.
//

import Foundation

/// Turns a day's transactions into confirmed call-ups, the same way in the app,
/// background refresh, and the widget. A member of both the CallupTracker and
/// CallupWidgetExtension targets.
///
/// Failure policy, the same everywhere: fail closed and say so. A team or
/// player whose lookup fails is left out and the result is marked incomplete;
/// only a failed transactions request throws.
nonisolated enum CallupFeed {

    /// Active rosters run 26 players, 28 in September and 29 for international
    /// series. A bigger dated "active" roster is really the 40-man (offseason,
    /// spring before cuts, eliminated clubs in October), so an SE there is only
    /// a 40-man addition.
    static let maxActiveRosterSize = 29

    struct Day: Sendable {
        /// Confirmed call-ups, one per player, in feed order.
        let callups: [Transaction]
        /// A lookup failed, so some call-ups may be missing.
        let isIncomplete: Bool
    }

    struct RookieCheck: Sendable {
        /// The call-ups that pass the rookie-limit heuristic.
        let callups: [Transaction]
        /// Players whose stats couldn't be loaded, so they couldn't be judged.
        let failedIDs: Set<Int>
    }

    /// The day's likely call-ups, deduplicated by player, with SE selections
    /// confirmed against the active roster as of `date`.
    static func confirmedCallups(on date: String, api: MLBAPIClient) async throws -> Day {
        let transactions = try await api.fetchTransactions(for: date)

        var seen = Set<Int>()
        let unique = transactions.filter { txn in
            guard txn.isLikelyCallup, let id = txn.person?.id else { return false }
            return seen.insert(id).inserted
        }

        // SE can mean a true active-roster call-up OR only a 40-man addition.
        // Batch by team, typically 0–2 teams per day.
        let seTeamIDs = Set(unique.compactMap { $0.typeCode == "SE" ? $0.toTeam?.id : nil })
        var activeRosters: [Int: Set<Int>] = [:]
        var isIncomplete = false
        if !seTeamIDs.isEmpty {
            switch await SeasonCalendar.shared.isInSeason(date, api: api) {
            case true?:
                for teamID in seTeamIDs {
                    do {
                        let roster = try await api.fetchActiveRosterIDs(teamID: teamID, date: date)
                        if roster.count <= maxActiveRosterSize { activeRosters[teamID] = roster }
                    } catch {
                        isIncomplete = true
                    }
                }
            case false?:
                // Far from the season there's no active roster, only the 40-man.
                break
            case nil:
                isIncomplete = true
            }
        }

        let confirmed = unique.filter { txn in
            guard txn.typeCode == "SE" else { return true }  // CU is always an active-roster call-up
            guard let teamID = txn.toTeam?.id, let playerID = txn.person?.id else { return false }
            return activeRosters[teamID]?.contains(playerID) == true
        }
        return Day(callups: confirmed, isIncomplete: isIncomplete)
    }

    /// The call-ups that pass the MLB rookie-limit heuristic on career
    /// major-league stats before `date`. Background refresh and the widget use
    /// this because they can't reach Baseball Reference in their time budget.
    static func rookieEligible(_ callups: [Transaction], on date: String,
                               api: MLBAPIClient) async -> RookieCheck {
        let through = CallupDates.dayBefore(date)
        return await withTaskGroup(of: (Transaction, Bool?).self) { group in
            for txn in callups {
                group.addTask {
                    guard let playerID = txn.person?.id else { return (txn, false) }
                    let eligible = try? await passesRookieLimits(playerID: playerID, through: through, api: api)
                    return (txn, eligible)
                }
            }
            var eligible: [Transaction] = []
            var failedIDs = Set<Int>()
            for await (txn, passes) in group {
                switch passes {
                case true?: eligible.append(txn)
                case false?: break
                case nil: if let id = txn.person?.id { failedIDs.insert(id) }
                }
            }
            return RookieCheck(callups: eligible, failedIDs: failedIDs)
        }
    }

    private static func passesRookieLimits(playerID: Int, through: String?, api: MLBAPIClient) async throws -> Bool {
        guard let info = try await api.fetchPlayerInfo(playerID: playerID) else { throw APIError.invalidResponse }
        let isPitcher = CallupRules.pitcherPositions.contains(info.primaryPosition?.abbreviation ?? "")
        if isPitcher {
            let raw = try await api.fetchCareerPitching(playerID: playerID, through: through)
            return CallupRules.passesRookieLimits(isPitcher: true,
                                                  careerInningsPitched: raw?.inningsPitched,
                                                  careerAtBats: nil)
        } else {
            let raw = try await api.fetchCareerHitting(playerID: playerID, through: through)
            return CallupRules.passesRookieLimits(isPitcher: false,
                                                  careerInningsPitched: nil,
                                                  careerAtBats: raw?.atBats)
        }
    }
}

/// Each year's season window, fetched once per process.
actor SeasonCalendar {
    static let shared = SeasonCalendar()

    /// Opening Day roster selections land up to a week before the first game.
    private static let leadInDays = 10

    private var seasons: [Int: ClosedRange<String>] = [:]

    /// Whether `date` ("yyyy-MM-dd") falls from `leadInDays` before the regular
    /// season through the end of the postseason; nil when the dates couldn't be loaded.
    func isInSeason(_ date: String, api: MLBAPIClient) async -> Bool? {
        guard let year = Int(date.prefix(4)) else { return nil }
        if let season = seasons[year] { return season.contains(date) }
        guard let official = try? await api.fetchSeasonDates(year: year),
              let start = CallupDates.day(official.lowerBound, offsetBy: -Self.leadInDays) else { return nil }
        let season = start...official.upperBound
        seasons[year] = season
        return season.contains(date)
    }
}

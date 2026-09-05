//
//  CallupRules.swift
//  CallupTracker
//
//  Facts and rules shared by the app, its notifications, and the widget.
//

import Foundation

/// The single source of truth for "which clubs are MLB" and "what counts as a
/// call-up".
///
/// This file is a member of **both** the CallupTracker and CallupWidgetExtension
/// targets. The widget used to carry its own copy of the team-ID list and a
/// stricter transaction filter, so the app and the widget could disagree about
/// who was called up on the same day. Anything both targets rely on belongs here.
enum CallupRules {

    // MARK: - Clubs

    struct Club: Sendable, Hashable {
        let id: Int
        let name: String
        let abbreviation: String
    }

    /// The 30 MLB clubs, in the alphabetical order the team filter menu shows.
    static let clubs: [Club] = [
        .init(id: 109, name: "Arizona Diamondbacks",   abbreviation: "ARI"),
        .init(id: 144, name: "Atlanta Braves",         abbreviation: "ATL"),
        .init(id: 110, name: "Baltimore Orioles",      abbreviation: "BAL"),
        .init(id: 111, name: "Boston Red Sox",         abbreviation: "BOS"),
        .init(id: 112, name: "Chicago Cubs",           abbreviation: "CHC"),
        .init(id: 145, name: "Chicago White Sox",      abbreviation: "CWS"),
        .init(id: 113, name: "Cincinnati Reds",        abbreviation: "CIN"),
        .init(id: 114, name: "Cleveland Guardians",    abbreviation: "CLE"),
        .init(id: 115, name: "Colorado Rockies",       abbreviation: "COL"),
        .init(id: 116, name: "Detroit Tigers",         abbreviation: "DET"),
        .init(id: 117, name: "Houston Astros",         abbreviation: "HOU"),
        .init(id: 118, name: "Kansas City Royals",     abbreviation: "KC"),
        .init(id: 108, name: "Los Angeles Angels",     abbreviation: "LAA"),
        .init(id: 119, name: "Los Angeles Dodgers",    abbreviation: "LAD"),
        .init(id: 146, name: "Miami Marlins",          abbreviation: "MIA"),
        .init(id: 158, name: "Milwaukee Brewers",      abbreviation: "MIL"),
        .init(id: 142, name: "Minnesota Twins",        abbreviation: "MIN"),
        .init(id: 121, name: "New York Mets",          abbreviation: "NYM"),
        .init(id: 147, name: "New York Yankees",       abbreviation: "NYY"),
        .init(id: 133, name: "Oakland Athletics",      abbreviation: "OAK"),
        .init(id: 143, name: "Philadelphia Phillies",  abbreviation: "PHI"),
        .init(id: 134, name: "Pittsburgh Pirates",     abbreviation: "PIT"),
        .init(id: 135, name: "San Diego Padres",       abbreviation: "SD"),
        .init(id: 137, name: "San Francisco Giants",   abbreviation: "SF"),
        .init(id: 136, name: "Seattle Mariners",       abbreviation: "SEA"),
        .init(id: 138, name: "St. Louis Cardinals",    abbreviation: "STL"),
        .init(id: 139, name: "Tampa Bay Rays",         abbreviation: "TB"),
        .init(id: 140, name: "Texas Rangers",          abbreviation: "TEX"),
        .init(id: 141, name: "Toronto Blue Jays",      abbreviation: "TOR"),
        .init(id: 120, name: "Washington Nationals",   abbreviation: "WSH"),
    ]

    static let mlbTeamIDs: Set<Int> = Set(clubs.map(\.id))

    private static let clubNamesLowercased: [String] = clubs.map { $0.name.lowercased() }

    // MARK: - Call-up detection

    /// True when a transaction looks like a genuine minors-to-MLB call-up.
    ///
    /// CU = recalled to the active 26-man roster, the player is already on the 40-man.
    /// SE = selected from the minors, which can be a true active call-up OR only a
    ///      40-man addition. Callers that need certainty verify SE transactions
    ///      against the live active roster.
    ///
    /// The description fallback matters: the API often omits `fromTeam`, and the
    /// widget's old filter rejected those outright while the app accepted them.
    static func isLikelyCallup(typeCode: String?,
                               toTeamID: Int?,
                               fromTeamID: Int?,
                               description: String?) -> Bool {
        guard let code = typeCode, code == "CU" || code == "SE" else { return false }
        guard let toID = toTeamID, mlbTeamIDs.contains(toID) else { return false }

        if let fromID = fromTeamID {
            // fromTeam is present, so it must be a minor-league club. An MLB
            // fromTeam means a trade or a waiver claim, not a call-up.
            return !mlbTeamIDs.contains(fromID)
        }

        // No fromTeam in the API data. Accept only when the description mentions
        // " from " and does not name an MLB club, so "recalled from Iowa Cubs"
        // passes but "traded from Los Angeles Dodgers" does not.
        guard let description else { return false }
        let lower = description.lowercased()
        guard lower.contains(" from ") else { return false }
        return !clubNamesLowercased.contains { lower.contains($0) }
    }

    // MARK: - Rookie eligibility

    /// Position abbreviations the API uses for pitchers, including two-way players.
    static let pitcherPositions: Set<String> = ["P", "SP", "RP", "TWP"]

    static let rookieInningsPitchedLimit = 50.0
    static let rookieAtBatLimit = 130

    /// Parses the API's innings string, where the fraction is thirds of an inning.
    /// "131.1" is 131 and one third, not 131.1.
    static func inningsPitched(from raw: String?) -> Double {
        let parts = (raw ?? "0").split(separator: ".")
        let whole = Double(parts.first ?? "0") ?? 0
        let thirds = Double(parts.dropFirst().first ?? "0") ?? 0
        return whole + thirds / 3.0
    }

    /// The MLB rookie-limit heuristic: under 50 career innings for a pitcher,
    /// under 130 career at-bats for a hitter.
    ///
    /// The app itself does not use this. It defers to Baseball Reference, which
    /// also accounts for active-roster service time and is the arbiter shown in
    /// the UI. Background refresh and the widget cannot reach Baseball Reference
    /// within their time budget, so they share this approximation instead. It is
    /// the one place the three code paths can still legitimately differ.
    static func passesRookieLimits(isPitcher: Bool,
                                   careerInningsPitched: String?,
                                   careerAtBats: Int?) -> Bool {
        isPitcher
            ? inningsPitched(from: careerInningsPitched) < rookieInningsPitchedLimit
            : (careerAtBats ?? 0) < rookieAtBatLimit
    }
}

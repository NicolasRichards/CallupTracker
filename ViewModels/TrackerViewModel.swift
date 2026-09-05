import SwiftUI
import Combine

@MainActor
class TrackerViewModel: ObservableObject {

    @Published var selectedDate: Date = Date()
    @Published var cards: [PlayerCard] = []
    @Published var loadingState: LoadingState = .idle
    @Published var selectedTeamID: Int? = nil
    @Published var brefRateLimitUntil: Date? = nil

    enum LoadingState {
        case idle, loading, loaded, empty
        case error(String)
    }

    private let api = MLBAPIClient.shared
    private var loadingTask: Task<Void, Never>?

    var isAtToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        // POSIX locale: this feeds API URLs, so it must not depend on the
        // device's calendar setting (Buddhist/Japanese calendars shift the year).
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: selectedDate)
    }

    var displayDate: String {
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: selectedDate)
    }

    var selectedTeam: MLBTeam? {
        guard let id = selectedTeamID else { return nil }
        return MLBAPIClient.allTeams.first { $0.id == id }
    }

    var filteredCards: [PlayerCard] {
        guard let teamID = selectedTeamID else { return cards }
        return cards.filter { $0.teamID == teamID }
    }

    // MARK: - Navigation

    func goToPreviousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        loadCards()
    }

    func goToNextDay() {
        guard !isAtToday else { return }
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        loadCards()
    }

    // MARK: - Loading

    func loadCards() {
        loadingTask?.cancel()
        cards = []
        loadingState = .loading
        let dateStr = formattedDate
        let loadingToday = isAtToday

        loadingTask = Task {
            do {
                let result = try await fetchCallups(for: dateStr, isToday: loadingToday)
                guard !Task.isCancelled else { return }
                self.cards = result
                self.loadingState = result.isEmpty ? .empty : .loaded
                // Share eligible players with the widget
                if Calendar.current.isDateInToday(self.selectedDate) {
                    // Widget only shows rookie-eligible players
                    SharedCallupData.save(result.filter { $0.isRookieEligible }, for: dateStr)
                }
            } catch is CancellationError {
                // User navigated away — ignore
            } catch {
                guard !Task.isCancelled else { return }
                self.loadingState = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Pipeline

    private func fetchCallups(for dateStr: String, isToday: Bool = true) async throws -> [PlayerCard] {
        let transactions = try await api.fetchTransactions(for: dateStr)

        let callups = transactions.filter { $0.isLikelyCallup }

        var seen = Set<Int>()
        let unique = callups.filter { txn in
            guard let id = txn.person?.id, !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }

        // SE transactions can mean a true active-roster callup OR just a 40-man addition.
        // Verify by fetching the live active roster for each team that has SE transactions.
        // Batch by team — typically 0–2 teams per day — so at most a couple of extra calls.
        let seTeamIDs = Set(unique.compactMap { $0.typeCode == "SE" ? $0.toTeam?.id : nil })
        var activeRosters: [Int: Set<Int>] = [:]
        for teamID in seTeamIDs {
            activeRosters[teamID] = (try? await api.fetchActiveRosterIDs(teamID: teamID)) ?? []
        }

        let confirmed = unique.filter { txn in
            guard txn.typeCode == "SE",
                  let teamID = txn.toTeam?.id,
                  let playerID = txn.person?.id else {
                return true  // CU — always an active roster callup, no verification needed
            }
            return activeRosters[teamID]?.contains(playerID) == true
        }

        return try await withThrowingTaskGroup(of: PlayerCard?.self) { group in
            for (index, txn) in confirmed.enumerated() {
                let brefDelay = isToday ? 0 : index
                group.addTask { try await self.buildCard(from: txn, dateStr: dateStr, brefDelayIndex: brefDelay) }
            }
            var result: [PlayerCard] = []
            for try await card in group {
                if let card { result.append(card) }
            }
            return result.sorted {
                if $0.callupBucket.rawValue != $1.callupBucket.rawValue {
                    return $0.callupBucket.rawValue < $1.callupBucket.rawValue
                }
                return $0.name < $1.name
            }
        }
    }

    private func buildCard(from txn: Transaction, dateStr: String, brefDelayIndex: Int = 0) async throws -> PlayerCard? {
        guard let person = txn.person else { return nil }
        let playerID = person.id

        guard let info = try await api.fetchPlayerInfo(playerID: playerID) else { return nil }
        let posAbbr = info.primaryPosition?.abbreviation ?? ""
        let posName = info.primaryPosition?.name ?? posAbbr
        let isPitcher = CallupRules.pitcherPositions.contains(posAbbr)

        var displayHitting: DisplayHittingStats? = nil
        var displayPitching: DisplayPitchingStats? = nil

        if isPitcher {
            let raw = try await api.fetchCareerPitching(playerID: playerID)
            if let raw {
                displayPitching = DisplayPitchingStats(
                    games: raw.gamesPlayed ?? 0,
                    wins: raw.wins ?? 0,
                    losses: raw.losses ?? 0,
                    era: raw.era ?? "—",
                    inningsPitched: raw.inningsPitched ?? "0",
                    strikeouts: raw.strikeOuts ?? 0,
                    whip: raw.whip ?? "—"
                )
            }
        } else {
            let raw = try await api.fetchCareerHitting(playerID: playerID)
            if let raw {
                displayHitting = DisplayHittingStats(
                    games: raw.gamesPlayed ?? 0,
                    atBats: raw.atBats ?? 0,
                    avg: raw.avg ?? "—",
                    homeRuns: raw.homeRuns ?? 0,
                    rbi: raw.rbi ?? 0,
                    ops: raw.ops ?? "—"
                )
            }
        }

        let callupHistory = extractCallupHistory(from: info, beforeDate: dateStr)
        // Use CU+SE to determine whether the player has been on the active roster
        // this year — SE is unreliable for showing specific dates but good enough
        // for a yes/no year check. CU-only history is used for display.
        let isFirstCallupThisSeason = !hasAnyCallupInCurrentYear(from: info, beforeDate: dateStr)

        // For historical dates, stagger uncached BBRef requests (300ms per player)
        // to avoid triggering rate limiting. Skip the delay for today and for cache hits.
        if brefDelayIndex > 0, !BaseballReferenceClient.shared.hasCachedStatus(forMLBID: playerID) {
            try await Task.sleep(nanoseconds: UInt64(brefDelayIndex) * 300_000_000)
        }

        // Use Baseball Reference as the arbiter of rookie eligibility
        let brefLookup = await BaseballReferenceClient.shared.fetchRookieStatus(forMLBID: playerID)
        if let retryAfterSeconds = brefLookup.retryAfterSeconds {
            self.brefRateLimitUntil = Date().addingTimeInterval(TimeInterval(retryAfterSeconds))
        }

        return PlayerCard(
            id: playerID,
            teamID: txn.toTeam?.id ?? 0,
            name: person.fullName ?? "Unknown",
            team: txn.toTeam?.name ?? "Unknown Team",
            positionName: posName,
            positionAbbr: posAbbr,
            description: txn.description ?? "",
            headshotURL: MLBAPIClient.headshotURL(for: playerID),
            isPitcher: isPitcher,
            hittingStats: displayHitting,
            pitchingStats: displayPitching,
            callupHistory: callupHistory,
            isFirstCallupThisSeason: isFirstCallupThisSeason,
            brefRookieStatus: brefLookup.status
        )
    }

    // MARK: - Callup History

    private func extractCallupHistory(from info: PlayerInfo, beforeDate: String) -> [String] {
        guard let txns = info.transactions else { return [] }
        return txns
            .filter { txn in
                // CU only — "recalled" is specifically for active-roster callups.
                // SE (selected) fires for 40-man additions too, and we can't verify
                // active-roster status for historical dates the way we do for today.
                guard let code = txn.typeCode, code == "CU" else { return false }
                guard let toID = txn.toTeam?.id, MLBAPIClient.mlbTeamIDs.contains(toID) else { return false }
                guard let fromID = txn.fromTeam?.id,
                      !MLBAPIClient.mlbTeamIDs.contains(fromID) else { return false }
                guard let date = txn.date else { return false }
                guard isRegularSeason(date) else { return false }
                return date < beforeDate
            }
            .compactMap { $0.date.map { formatCallupDate($0) } }
            .reversed()
            .prefix(3)
            .map { $0 }
    }

    // Checks whether the player had a CU (active-roster recall) in the current
    // calendar year before today. CU-only matches extractCallupHistory so that
    // the bucket classification is always consistent with what the history displays.
    // SE is excluded — we can't verify historical active-roster status for SE
    // transactions, and including them causes bucket/history disagreements.
    private func hasAnyCallupInCurrentYear(from info: PlayerInfo, beforeDate: String) -> Bool {
        guard let txns = info.transactions else { return false }
        let currentYear = String(Calendar.current.component(.year, from: Date()))
        return txns.contains { txn in
            guard let code = txn.typeCode, code == "CU" else { return false }
            guard let toID = txn.toTeam?.id, MLBAPIClient.mlbTeamIDs.contains(toID) else { return false }
            // PlayerTransaction has no description field, so skip transactions
            // where fromTeam is nil — we can't tell if it's a trade or a callup.
            guard let fromID = txn.fromTeam?.id,
                  !MLBAPIClient.mlbTeamIDs.contains(fromID) else { return false }
            guard let date = txn.date, date.hasPrefix(currentYear) else { return false }
            guard isRegularSeason(date) else { return false }
            return date < beforeDate
        }
    }

    // Regular season: last week of March through first week of October
    private func isRegularSeason(_ dateStr: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: dateStr) else { return false }
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        if month >= 4 && month <= 9 { return true }
        if month == 3 && day >= 25 { return true }
        return false
    }

    private func formatCallupDate(_ dateStr: String) -> String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        input.locale = Locale(identifier: "en_US_POSIX")
        let output = DateFormatter()
        output.dateFormat = "MMM d, yyyy"
        if let d = input.date(from: dateStr) {
            return output.string(from: d)
        }
        return dateStr
    }
}

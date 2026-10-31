import SwiftUI
import Combine

@MainActor
class TrackerViewModel: ObservableObject {

    @Published var selectedDate: Date = CallupDates.localDate(of: CallupDates.today()) ?? Date()
    @Published var cards: [PlayerCard] = []
    @Published var loadingState: LoadingState = .idle
    /// Some players or teams couldn't be loaded, so the list may be missing call-ups.
    @Published var isIncomplete = false
    @Published var selectedTeamID: Int? = nil
    @Published var brefRateLimitUntil: Date? = nil

    enum LoadingState {
        case idle, loading, loaded, empty
        case error(String)
    }

    private let api = MLBAPIClient.shared
    private var loadingTask: Task<Void, Never>?
    private var wasAtTodayWhenLeftActive = true
    private var lastCompleteLoad: (date: String, at: Date)?

    /// The feed's today (US Eastern) as a date-picker date, the latest selectable day.
    var latestDate: Date {
        CallupDates.localDate(of: CallupDates.today()) ?? Date()
    }

    var isAtToday: Bool {
        formattedDate >= CallupDates.today()
    }

    /// The API date for the day the picker shows.
    var formattedDate: String {
        CallupDates.localDay(of: selectedDate)
    }

    var displayDate: String {
        selectedDate.formatted(date: .complete, time: .omitted)
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
        // loadCards() is triggered by ContentView's onChange(of: selectedDate)
    }

    func goToNextDay() {
        guard !isAtToday else { return }
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        // loadCards() is triggered by ContentView's onChange(of: selectedDate)
    }

    // MARK: - Scene Phase

    func sceneLeftActive() {
        wasAtTodayWhenLeftActive = isAtToday
    }

    /// Follows the date forward if the user was on today when the app went to
    /// the background, and skips a refetch of a day that loaded moments ago.
    func sceneBecameActive() {
        if wasAtTodayWhenLeftActive && !isAtToday {
            selectedDate = latestDate   // loadCards() runs from ContentView's onChange
            return
        }
        if let last = lastCompleteLoad, last.date == formattedDate,
           Date().timeIntervalSince(last.at) < 5 * 60 {
            return
        }
        loadCards()
    }

    // MARK: - Loading

    func loadCards() {
        loadingTask?.cancel()
        cards = []
        loadingState = .loading
        isIncomplete = false
        lastCompleteLoad = nil
        brefRateLimitUntil = nil   // cleared each load; re-set below if a 429 is encountered
        let dateStr = formattedDate
        let loadingToday = isAtToday

        loadingTask = Task {
            do {
                let result = try await fetchCallups(for: dateStr, isToday: loadingToday)
                guard !Task.isCancelled else { return }
                self.cards = result.cards
                self.isIncomplete = result.isIncomplete
                if result.cards.isEmpty && result.isIncomplete {
                    self.loadingState = .error("Couldn't load call-ups. Check your connection and try again.")
                } else {
                    self.loadingState = result.cards.isEmpty ? .empty : .loaded
                }
                // A rate-limited player is unjudged, so that list isn't complete either.
                let complete = !result.isIncomplete && !result.cards.contains { $0.isBRefRateLimited }
                if complete { self.lastCompleteLoad = (dateStr, Date()) }
                if dateStr == CallupDates.today() {
                    // Widget only shows rookie-eligible players
                    let players = result.cards.filter { $0.isRookieEligible }
                        .map { SharedPlayer(id: $0.id, name: $0.name, team: $0.team) }
                    let notEligibleIDs = result.cards
                        .filter { $0.brefRookieStatus == .exceededRookieLimits }.map(\.id).sorted()
                    SharedCallupData.save(players, notEligibleIDs: notEligibleIDs,
                                          isComplete: complete, for: dateStr)
                }
            } catch is CancellationError {
                // User navigated away — ignore
            } catch {
                guard !Task.isCancelled else { return }
                let message: String
                if error is DecodingError {
                    message = "Couldn't read the MLB data. Try again in a moment."
                } else {
                    message = "Couldn't load call-ups. Check your connection and try again."
                }
                self.loadingState = .error(message)
            }
        }
    }

    // MARK: - Pipeline

    /// Only a failed transactions request throws; a player whose details fail
    /// to load is left out and the result is marked incomplete.
    private func fetchCallups(for dateStr: String, isToday: Bool = true) async throws -> (cards: [PlayerCard], isIncomplete: Bool) {
        let day = try await CallupFeed.confirmedCallups(on: dateStr, api: api)

        return await withTaskGroup(of: (card: PlayerCard?, failed: Bool).self) { group in
            for (index, txn) in day.callups.enumerated() {
                let brefDelay = isToday ? 0 : index
                group.addTask {
                    do {
                        return (try await self.buildCard(from: txn, dateStr: dateStr, brefDelayIndex: brefDelay), false)
                    } catch {
                        return (nil, true)
                    }
                }
            }
            var result: [PlayerCard] = []
            var isIncomplete = day.isIncomplete
            for await outcome in group {
                if let card = outcome.card { result.append(card) }
                if outcome.failed { isIncomplete = true }
            }
            let sorted = result.sorted {
                if $0.callupBucket.rawValue != $1.callupBucket.rawValue {
                    return $0.callupBucket.rawValue < $1.callupBucket.rawValue
                }
                return $0.name < $1.name
            }
            return (sorted, isIncomplete)
        }
    }

    private func buildCard(from txn: Transaction, dateStr: String, brefDelayIndex: Int = 0) async throws -> PlayerCard? {
        guard let person = txn.person else { return nil }
        let playerID = person.id

        guard let info = try await api.fetchPlayerInfo(playerID: playerID) else { return nil }
        let posAbbr = info.primaryPosition?.abbreviation ?? ""
        let posName = info.primaryPosition?.name ?? posAbbr
        let isPitcher = CallupRules.pitcherPositions.contains(posAbbr)

        // Stats count only games before the viewed date, so a debut on a past date
        // (or today, once the game ends) isn't bucketed by games played since.
        let statsThrough = CallupDates.dayBefore(dateStr)

        var displayHitting: DisplayHittingStats? = nil
        var displayPitching: DisplayPitchingStats? = nil

        if isPitcher {
            let raw = try await api.fetchCareerPitching(playerID: playerID, through: statsThrough)
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
            let raw = try await api.fetchCareerHitting(playerID: playerID, through: statsThrough)
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
        // Primary check: season stats for the viewed year — games played > 0 means
        // the player has appeared in a game that year, regardless of transaction code.
        // Use the year from dateStr (not Date()) so historical browsing works correctly.
        // Fallback: CU transaction check for players called up today but not yet in a game.
        let viewedYear = Int(dateStr.prefix(4)) ?? Calendar.current.component(.year, from: Date())
        let currentYearStats = try? await api.fetchCurrentYearStats(playerID: playerID, group: isPitcher ? "pitching" : "hitting", year: viewedYear, through: statsThrough)
        let hasCurrentYearGames = (currentYearStats?.gamesPlayed ?? 0) > 0
        let isFirstCallupThisSeason = !hasCurrentYearGames && !hasAnyCallupInCurrentYear(from: info, beforeDate: dateStr)

        // For historical dates, stagger uncached BBRef requests (300ms per player)
        // to avoid triggering rate limiting. Skip the delay for today and for cache hits.
        if brefDelayIndex > 0 {
            let isCached = await BaseballReferenceClient.shared.hasCachedStatus(forMLBID: playerID)
            if !isCached {
                try await Task.sleep(nanoseconds: UInt64(brefDelayIndex) * 300_000_000)
            }
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
            .sorted { ($0.date ?? "") < ($1.date ?? "") }
            .compactMap { $0.date.map { CallupDates.displayString(for: $0) } }
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
        let viewedYear = String(beforeDate.prefix(4))
        return txns.contains { txn in
            guard let code = txn.typeCode, code == "CU" else { return false }
            guard let toID = txn.toTeam?.id, MLBAPIClient.mlbTeamIDs.contains(toID) else { return false }
            // PlayerTransaction has no description field, so skip transactions
            // where fromTeam is nil — we can't tell if it's a trade or a callup.
            guard let fromID = txn.fromTeam?.id,
                  !MLBAPIClient.mlbTeamIDs.contains(fromID) else { return false }
            guard let date = txn.date, date.hasPrefix(viewedYear) else { return false }
            guard isRegularSeason(date) else { return false }
            return date < beforeDate
        }
    }

    // Regular season: last week of March through first week of October.
    // Parse date string directly to avoid DateFormatter allocation on every call.
    private func isRegularSeason(_ dateStr: String) -> Bool {
        // Expected format: "yyyy-MM-dd" — parse month and day from fixed positions.
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day   = Int(parts[2]) else { return false }
        if month >= 4 && month <= 9 { return true }
        if month == 3 && day >= 25  { return true }
        if month == 10 && day <= 7  { return true }
        return false
    }
}

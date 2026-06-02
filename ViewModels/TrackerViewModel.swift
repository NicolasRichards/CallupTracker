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

        loadingTask = Task {
            do {
                let result = try await fetchCallups(for: dateStr)
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

    private func fetchCallups(for dateStr: String) async throws -> [PlayerCard] {
        let transactions = try await api.fetchTransactions(for: dateStr)

        let callups = transactions.filter { isCallup($0) }

        var seen = Set<Int>()
        let unique = callups.filter { txn in
            guard let id = txn.person?.id, !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }

        return try await withThrowingTaskGroup(of: PlayerCard?.self) { group in
            for txn in unique {
                group.addTask { try await self.buildCard(from: txn, dateStr: dateStr) }
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

    private func isCallup(_ txn: Transaction) -> Bool {
        guard let code = txn.typeCode, (code == "CU" || code == "SE") else { return false }
        guard let toID = txn.toTeam?.id, MLBAPIClient.mlbTeamIDs.contains(toID) else { return false }
        // Accept if API provides fromTeam, or if description says "from [minor league team]"
        return txn.fromTeam != nil || txn.description?.lowercased().contains(" from ") == true
    }

    private func buildCard(from txn: Transaction, dateStr: String) async throws -> PlayerCard? {
        guard let person = txn.person else { return nil }
        let playerID = person.id

        guard let info = try await api.fetchPlayerInfo(playerID: playerID) else { return nil }
        let posAbbr = info.primaryPosition?.abbreviation ?? ""
        let posName = info.primaryPosition?.name ?? posAbbr
        let isPitcher = ["P", "SP", "RP", "TWP"].contains(posAbbr)

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
        let currentYear = String(Calendar.current.component(.year, from: Date()))
        let isFirstCallupThisSeason = !callupHistory.contains { $0.contains(currentYear) }

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
                // CU or SE, but must have a fromTeam — excludes 40-man additions (no fromTeam)
                guard let code = txn.typeCode, (code == "CU" || code == "SE") else { return false }
                guard let toID = txn.toTeam?.id, MLBAPIClient.mlbTeamIDs.contains(toID) else { return false }
                guard txn.fromTeam != nil else { return false }
                guard let date = txn.date else { return false }
                guard isRegularSeason(date) else { return false }
                return date < beforeDate
            }
            .compactMap { $0.date.map { formatCallupDate($0) } }
            .reversed()
            .prefix(3)
            .map { $0 }
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
        if month == 3 && day >= 20 { return true }
        if month == 10 && day <= 10 { return true }
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

import SwiftUI
import Combine

@MainActor
class TrackerViewModel: ObservableObject {

    @Published var selectedDate: Date = Date()
    @Published var cards: [PlayerCard] = []
    @Published var loadingState: LoadingState = .idle
    @Published var selectedTeamID: Int? = nil

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
                    SharedCallupData.save(result, for: dateStr)
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
                if $0.isFirstCallupThisSeason != $1.isFirstCallupThisSeason {
                    return $0.isFirstCallupThisSeason
                }
                return $0.name < $1.name
            }
        }
    }

    private func isCallup(_ txn: Transaction) -> Bool {
        guard let code = txn.typeCode, (code == "CU" || code == "SE") else { return false }
        guard let toID = txn.toTeam?.id, MLBAPIClient.mlbTeamIDs.contains(toID) else { return false }
        return txn.fromTeam != nil
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
                if parseInnings(raw.inningsPitched) >= 50 { return nil }
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
                if (raw.atBats ?? 0) >= 130 { return nil }
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
            isFirstCallupThisSeason: isFirstCallupThisSeason
        )
    }

    // MARK: - Callup History

    private func extractCallupHistory(from info: PlayerInfo, beforeDate: String) -> [String] {
        guard let txns = info.transactions else { return [] }
        return txns
            .filter { txn in
                // Only "CU" (Called Up) counts — excludes "SE" (40-man roster additions)
                guard let code = txn.typeCode, code == "CU" else { return false }
                // Must be to an MLB team
                guard let toID = txn.toTeam?.id, MLBAPIClient.mlbTeamIDs.contains(toID) else { return false }
                guard let date = txn.date else { return false }
                return date < beforeDate
            }
            .compactMap { $0.date.map { formatCallupDate($0) } }
            .reversed()
            .prefix(3)
            .map { $0 }
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

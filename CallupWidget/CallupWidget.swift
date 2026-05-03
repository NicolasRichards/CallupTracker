//
//  CallupWidget.swift
//  CallupWidget
//
//  Created by Nicolas Richards on 5/1/26.
//

import WidgetKit
import SwiftUI

// MARK: - Model

struct CallupEntry: TimelineEntry {
    let date: Date
    let callups: [CallupItem]
    let fetchFailed: Bool
}

struct CallupItem: Identifiable {
    let id: Int
    let name: String
    let team: String
}

// MARK: - Provider

struct Provider: TimelineProvider {

    func placeholder(in context: Context) -> CallupEntry {
        CallupEntry(date: .now, callups: [
            CallupItem(id: 1, name: "Spencer Jones", team: "New York Yankees"),
            CallupItem(id: 2, name: "Jackson Chourio", team: "Milwaukee Brewers"),
        ], fetchFailed: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (CallupEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task {
            let entry = await fetchTodayEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CallupEntry>) -> Void) {
        Task {
            let entry = await fetchTodayEntry()

            let nextUpdate: Date
            if entry.fetchFailed || entry.callups.isEmpty {
                // Retry in 30 minutes if we got nothing
                nextUpdate = Date(timeIntervalSinceNow: 30 * 60)
            } else {
                // Refresh at 6 AM tomorrow once we have data
                var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
                components.day! += 1
                components.hour = 6
                components.minute = 0
                nextUpdate = Calendar.current.date(from: components) ?? Date(timeIntervalSinceNow: 8 * 3600)
            }

            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func fetchTodayEntry() async -> CallupEntry {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let todayStr = f.string(from: .now)

        // Prefer the pre-filtered list saved by the main app (exact eligibility match)
        if let shared = loadShared(for: todayStr) {
            let items = shared.players.map { CallupItem(id: $0.id, name: $0.name, team: $0.team) }
            return CallupEntry(date: .now, callups: items, fetchFailed: false)
        }

        // Fall back to raw API fetch if app hasn't run today yet
        do {
            let items = try await fetchCallups(for: todayStr)
            return CallupEntry(date: .now, callups: items, fetchFailed: false)
        } catch {
            return CallupEntry(date: .now, callups: [], fetchFailed: true)
        }
    }

    private func loadShared(for dateStr: String) -> SharedWidgetData? {
        guard let defaults = UserDefaults(suiteName: "group.NickRichards.MLBCallups"),
              let data = defaults.data(forKey: "todayCallups"),
              let shared = try? JSONDecoder().decode(SharedWidgetData.self, from: data),
              shared.date == dateStr
        else { return nil }
        return shared
    }

    private func fetchCallups(for dateStr: String) async throws -> [CallupItem] {
        let mlbTeamIDs: Set<Int> = [
            108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121,
            133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146,
            147, 158
        ]

        let urlStr = "https://statsapi.mlb.com/api/v1/transactions?startDate=\(dateStr)&endDate=\(dateStr)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(WidgetTransactionsResponse.self, from: data)

        var seen = Set<Int>()
        return decoded.transactions
            .filter { txn in
                guard let code = txn.typeCode, (code == "CU" || code == "SE") else { return false }
                guard let toID = txn.toTeam?.id, mlbTeamIDs.contains(toID) else { return false }
                guard txn.fromTeam != nil, let id = txn.person?.id, !seen.contains(id) else { return false }
                seen.insert(id)
                return true
            }
            .compactMap { txn -> CallupItem? in
                guard let id = txn.person?.id, let name = txn.person?.fullName else { return nil }
                return CallupItem(id: id, name: name, team: txn.toTeam?.name ?? "")
            }
            .sorted { $0.name < $1.name }
    }
}

// Shared container types (must match SharedCallupData.swift in the main app)
private struct SharedWidgetData: Decodable {
    let date: String
    let players: [SharedWidgetPlayer]
}
private struct SharedWidgetPlayer: Decodable {
    let id: Int
    let name: String
    let team: String
}

// Minimal decodable types (widget has no access to the main app module)
private struct WidgetTransactionsResponse: Decodable {
    let transactions: [WidgetTransaction]
}
private struct WidgetTransaction: Decodable {
    let typeCode: String?
    let person: WidgetPerson?
    let toTeam: WidgetTeam?
    let fromTeam: WidgetTeam?
}
private struct WidgetPerson: Decodable {
    let id: Int
    let fullName: String?
}
private struct WidgetTeam: Decodable {
    let id: Int
    let name: String?
}

// MARK: - Views

struct CallupWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:  smallView
        default:            mediumView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Callups", systemImage: "figure.baseball")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Spacer()
            if entry.callups.isEmpty {
                Text(entry.fetchFailed ? "Tap to refresh" : "None today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.callups.prefix(3)) { player in
                    Text(player.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                if entry.callups.count > 3 {
                    Text("+ more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Today's Callups", systemImage: "figure.baseball")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            if entry.callups.isEmpty {
                Spacer()
                Text(entry.fetchFailed ? "Could not load — tap to retry" : "No rookie callups today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.callups.prefix(4)) { player in
                    HStack {
                        Text(player.name)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Spacer()
                        Text(player.team)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if entry.callups.count > 4 {
                    Text("+ more • tap to see all")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }
}

// MARK: - Widget Declaration

struct CallupWidget: Widget {
    let kind: String = "CallupWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                CallupWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                CallupWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Rookie Callups")
        .description("See today's rookie-eligible callups at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    CallupWidget()
} timeline: {
    CallupEntry(date: .now, callups: [
        CallupItem(id: 1, name: "Spencer Jones", team: "New York Yankees"),
        CallupItem(id: 2, name: "Jackson Chourio", team: "Milwaukee Brewers"),
        CallupItem(id: 3, name: "Kyle Manzardo", team: "Cleveland Guardians"),
    ], fetchFailed: false)
    CallupEntry(date: .now, callups: [], fetchFailed: false)
}

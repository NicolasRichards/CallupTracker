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
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (CallupEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CallupEntry>) -> Void) {
        Task {
            let entry = await fetchTodayEntry()
            var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
            components.day! += 1
            components.hour = 6
            let nextUpdate = Calendar.current.date(from: components) ?? Date(timeIntervalSinceNow: 24 * 3600)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func fetchTodayEntry() async -> CallupEntry {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let todayStr = f.string(from: .now)
        do {
            let items = try await fetchCallups(for: todayStr)
            return CallupEntry(date: .now, callups: items)
        } catch {
            return CallupEntry(date: .now, callups: [])
        }
    }

    private func fetchCallups(for dateStr: String) async throws -> [CallupItem] {
        let mlbTeamIDs: Set<Int> = [
            108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121,
            133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146,
            147, 158
        ]
        let url = URL(string: "https://statsapi.mlb.com/api/v1/transactions?startDate=\(dateStr)&endDate=\(dateStr)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(WidgetTransactionsResponse.self, from: data)
        var seen = Set<Int>()
        return response.transactions
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
                Text("None today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(entry.callups.count)")
                    .font(.system(size: 40, weight: .bold))
                Text("rookie\(entry.callups.count == 1 ? "" : "s") called up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                Text("No rookie callups today")
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
                    Text("+\(entry.callups.count - 4) more")
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
        .description("See today's rookie-eligible MLB callups at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    CallupWidget()
} timeline: {
    CallupEntry(date: .now, callups: [
        CallupItem(id: 1, name: "Spencer Jones", team: "NYY"),
        CallupItem(id: 2, name: "Jackson Chourio", team: "MIL"),
    ])
}

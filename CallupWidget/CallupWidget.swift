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
    /// Some call-ups couldn't be checked, so the list may be missing players.
    var isIncomplete = false
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

    func getSnapshot(in context: Context, completion: @escaping @Sendable (CallupEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task {
            let entry = await fetchTodayEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<CallupEntry>) -> Void) {
        Task {
            let entry = await fetchTodayEntry()
            let minutes = await refreshMinutes(after: entry)
            completion(Timeline(entries: [entry], policy: .after(Date(timeIntervalSinceNow: minutes * 60))))
        }
    }

    private static let api: MLBAPIClient = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return MLBAPIClient(session: URLSession(configuration: config))
    }()

    private static let retryCountKey = "widgetRetryCount"

    /// Hourly in season so later call-ups appear (about 24 reloads a day, inside
    /// WidgetKit's budget); after a failure, 30 minutes doubling up to 4 hours;
    /// every 6 hours out of season.
    private func refreshMinutes(after entry: CallupEntry) async -> Double {
        let defaults = UserDefaults.standard
        let retries = entry.fetchFailed || entry.isIncomplete
            ? defaults.integer(forKey: Self.retryCountKey) + 1 : 0
        defaults.set(retries, forKey: Self.retryCountKey)

        if await SeasonCalendar.shared.isInSeason(CallupDates.today(), api: Self.api) == false {
            return 6 * 60
        }
        guard retries > 0 else { return 60 }
        return Double(30 << (min(retries, 4) - 1))
    }

    private func fetchTodayEntry() async -> CallupEntry {
        let todayStr = CallupDates.today()

        // Prefer the list the main app saved (Baseball Reference eligibility)
        // while it's recent and complete.
        let shared = SharedCallupData.load(for: todayStr)
        if let shared, shared.isFresh {
            return CallupEntry(date: .now, callups: items(from: shared), fetchFailed: false)
        }

        do {
            return try await fetchEntry(for: todayStr, judgedBy: shared)
        } catch {
            // The app's older list beats nothing.
            if let shared {
                return CallupEntry(date: .now, callups: items(from: shared), fetchFailed: false, isIncomplete: true)
            }
            return CallupEntry(date: .now, callups: [], fetchFailed: true)
        }
    }

    private func items(from shared: SharedCallupData) -> [CallupItem] {
        shared.players.map { CallupItem(id: $0.id, name: $0.name, team: $0.team) }
    }

    /// The same pipeline background refresh uses: confirmed call-ups, then the
    /// MLB rookie-limit heuristic, since a widget can't reach Baseball Reference
    /// inside its time budget. Players the app already judged keep its verdict;
    /// the heuristic only judges call-ups new since the app's last save.
    private func fetchEntry(for dateStr: String, judgedBy shared: SharedCallupData?) async throws -> CallupEntry {
        let day = try await CallupFeed.confirmedCallups(on: dateStr, api: Self.api)

        let appEligible = shared.map(items(from:)) ?? []
        let judgedIDs = Set(appEligible.map(\.id)).union(shared?.notEligibleIDs ?? [])
        let unjudged = day.callups.filter { txn in
            guard let id = txn.person?.id else { return false }
            return !judgedIDs.contains(id)
        }
        let rookies = await CallupFeed.rookieEligible(unjudged, on: dateStr, api: Self.api)
        let newItems = rookies.callups.compactMap { txn -> CallupItem? in
            guard let id = txn.person?.id, let name = txn.person?.fullName else { return nil }
            return CallupItem(id: id, name: name, team: txn.toTeam?.name ?? "")
        }
        return CallupEntry(date: .now,
                           callups: (appEligible + newItems).sorted { $0.name < $1.name },
                           fetchFailed: false,
                           isIncomplete: day.isIncomplete || !rookies.failedIDs.isEmpty)
    }
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
            header("Callups")
            Spacer()
            if entry.callups.isEmpty {
                Text(entry.fetchFailed || entry.isIncomplete ? "Tap to refresh" : "None today")
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

    /// The title, with a warning mark when the list may be missing players.
    private func header(_ title: String) -> some View {
        HStack(spacing: 4) {
            Label(title, systemImage: "figure.baseball")
            if entry.isIncomplete && !entry.callups.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityLabel("May be incomplete")
            }
        }
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 5) {
            header("Today's Callups")
            if entry.callups.isEmpty {
                Spacer()
                Text(entry.fetchFailed || entry.isIncomplete ? "Could not load — tap to retry" : "No rookie callups today")
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
    let kind: String = SharedCallupData.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CallupWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
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

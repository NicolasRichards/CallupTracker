//
//  SharedCallupData.swift
//  MLBCallups
//
//  Shared data container written by the main app, read by the widget.
//  Both targets must belong to the App Group: group.NickRichards.MLBCallups
//

import Foundation
import WidgetKit

struct SharedCallupData: Codable {
    let date: String          // yyyy-MM-dd of the callup day
    let players: [SharedPlayer]
}

struct SharedPlayer: Codable {
    let id: Int
    let name: String
    let team: String
}

extension SharedCallupData {
    static let appGroupID  = "group.NickRichards.MLBCallups"
    static let defaultsKey = "todayCallups"

    /// Called by the main app after filtering for rookie eligibility.
    static func save(_ cards: [PlayerCard], for dateStr: String) {
        let payload = SharedCallupData(
            date: dateStr,
            players: cards.map { SharedPlayer(id: $0.id, name: $0.name, team: $0.team) }
        )
        guard let encoded = try? JSONEncoder().encode(payload),
              let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(encoded, forKey: defaultsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Called by the widget to read today's pre-filtered list.
    static func load(for dateStr: String) -> SharedCallupData? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: defaultsKey),
              let shared = try? JSONDecoder().decode(SharedCallupData.self, from: data),
              shared.date == dateStr
        else { return nil }
        return shared
    }
}

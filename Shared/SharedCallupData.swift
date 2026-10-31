//
//  SharedCallupData.swift
//  MLBCallups
//
//  Shared data container written by the main app, read by the widget.
//  Both targets must belong to the App Group: group.NickRichards.MLBCallups
//  A member of both the CallupTracker and CallupWidgetExtension targets.
//

import Foundation
import WidgetKit

struct SharedCallupData: Codable {
    let date: String          // yyyy-MM-dd of the callup day
    /// The rookie-eligible players, by Baseball Reference.
    let players: [SharedPlayer]
    /// Players Baseball Reference judged not rookie-eligible. With `players`,
    /// every verdict the app reached, so the widget never overrides one.
    /// Optional, like the fields below, so payloads from older builds decode.
    let notEligibleIDs: [Int]?
    /// False when some players couldn't be loaded or judged.
    let isComplete: Bool?
    let savedAt: Date?
}

struct SharedPlayer: Codable, Equatable {
    let id: Int
    let name: String
    let team: String
}

extension SharedCallupData {
    static let appGroupID  = "group.NickRichards.MLBCallups"
    static let defaultsKey = "todayCallups"
    static let widgetKind  = "CallupWidget"

    /// How long the widget trusts the app's list before checking the API itself,
    /// so call-ups posted after the app was last opened still show up.
    static let freshInterval: TimeInterval = 60 * 60

    /// A complete list saved within `freshInterval`.
    var isFresh: Bool {
        guard isComplete == true, let savedAt else { return false }
        return Date().timeIntervalSince(savedAt) < Self.freshInterval
    }

    /// Called by the main app with the day's Baseball Reference verdicts.
    static func save(_ players: [SharedPlayer], notEligibleIDs: [Int], isComplete: Bool, for dateStr: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let previous = load(for: dateStr)
        let payload = SharedCallupData(date: dateStr, players: players, notEligibleIDs: notEligibleIDs,
                                       isComplete: isComplete, savedAt: .now)
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        defaults.set(encoded, forKey: defaultsKey)
        // A stale previous payload means the widget may be showing its own API result.
        if let previous, previous.isFresh, previous.players == players,
           previous.notEligibleIDs == notEligibleIDs, previous.isComplete == isComplete {
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Called by the widget to read the list the app saved for `dateStr`.
    static func load(for dateStr: String) -> SharedCallupData? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: defaultsKey),
              let shared = try? JSONDecoder().decode(SharedCallupData.self, from: data),
              shared.date == dateStr
        else { return nil }
        return shared
    }
}

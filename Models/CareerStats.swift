//
//  CareerStats.swift
//  MLBCallups
//
//  Created by Nicolas Richards on 2/20/26.
//

import Foundation

struct StatsResponse: Codable, Sendable {
    let stats: [StatGroup]
}

struct StatGroup: Codable, Sendable {
    let splits: [StatSplit]
}

struct StatSplit: Codable, Sendable {
    let sport: SportRef?
    let gameType: String?
    let stat: StatLine?
}

struct SportRef: Codable, Sendable {
    let id: Int?
}

struct StatLine: Codable, Sendable {
    // Hitting
    let gamesPlayed: Int?
    let atBats: Int?
    let homeRuns: Int?
    let rbi: Int?
    let avg: String?
    let ops: String?
    // Pitching
    let wins: Int?
    let losses: Int?
    let era: String?
    let inningsPitched: String?
    let whip: String?
    // Shared
    let strikeOuts: Int?
}


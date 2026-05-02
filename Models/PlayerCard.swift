//
//  PlayerCard.swift
//  MLBCallups
//
//  Created by Nicolas Richards on 2/20/26.
//

import Foundation

struct PlayerCard: Identifiable {
    let id: Int
    let teamID: Int
    let name: String
    let team: String
    let positionName: String
    let positionAbbr: String
    let description: String
    let headshotURL: URL?
    let isPitcher: Bool
    let hittingStats: DisplayHittingStats?
    let pitchingStats: DisplayPitchingStats?
    let callupHistory: [String]  // Formatted prior callup date strings, newest first
}

struct DisplayHittingStats {
    let games: Int
    let atBats: Int
    let avg: String
    let homeRuns: Int
    let rbi: Int
    let ops: String
}

struct DisplayPitchingStats {
    let games: Int
    let wins: Int
    let losses: Int
    let era: String
    let inningsPitched: String
    let strikeouts: Int
    let whip: String
}


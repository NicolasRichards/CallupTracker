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
    let isFirstCallupThisSeason: Bool
    let brefRookieStatus: BaseballReferenceClient.RookieStatus

    var isRookieEligible: Bool { brefRookieStatus == .rookieEligible }
    var isBRefRateLimited: Bool { brefRookieStatus == .rateLimited }

    // MARK: - Buckets

    enum CallupBucket: Int {
        case mlbDebut           = 0
        case firstCallupThisYear = 1
        case alreadyCalledUpThisYear = 2
        case notEligible        = 3
        case brefRateLimited    = 4
    }

    var callupBucket: CallupBucket {
        if isBRefRateLimited        { return .brefRateLimited }
        if !isRookieEligible        { return .notEligible }
        if callupHistory.isEmpty    { return .mlbDebut }
        if isFirstCallupThisSeason  { return .firstCallupThisYear }
        return .alreadyCalledUpThisYear
    }

    var bucketTitle: String {
        switch callupBucket {
        case .mlbDebut:               return "MLB Debut"
        case .firstCallupThisYear:    return "1st \(Calendar.current.component(.year, from: Date())) Call-Up"
        case .alreadyCalledUpThisYear: return "Called Up Before This Year"
        case .notEligible:            return "Not Eligible"
        case .brefRateLimited:        return "B-Ref Rate Limited"
        }
    }
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


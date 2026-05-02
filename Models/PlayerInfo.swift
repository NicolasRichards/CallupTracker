//
//  PlayerInfo.swift
//  MLBCallups
//
//  Created by Nicolas Richards on 2/20/26.
//

import Foundation

struct PeopleResponse: Codable, Sendable {
    let people: [PlayerInfo]
}

struct PlayerInfo: Codable, Sendable {
    let id: Int
    let fullName: String?
    let primaryPosition: Position?
    let currentTeam: TeamRef?
    let transactions: [PlayerTransaction]?
}

struct PlayerTransaction: Codable, Sendable {
    let typeCode: String?
    let date: String?
    let toTeam: TeamRef?
}

struct Position: Codable, Sendable {
    let name: String?
    let abbreviation: String?
}

struct TeamRef: Codable, Sendable {
    let id: Int?
    let name: String?
}

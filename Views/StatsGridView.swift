//
//  StatsGridView.swift
//  MLBCallups
//
//  Created by Nicolas Richards on 2/20/26.
//
// Which stats to show on the player cards

import SwiftUI

struct StatsGridView: View {
    let card: PlayerCard

    var body: some View {
        if card.isPitcher {
            if let stats = card.pitchingStats {
                statsGrid([
                    ("G",    "\(stats.games)"),
                    ("W-L",  "\(stats.wins)-\(stats.losses)"),
                    ("ERA",  stats.era),
                    ("IP",   stats.inningsPitched),
                    ("SO",   "\(stats.strikeouts)"),
                    ("WHIP", stats.whip),
                ])
            } else {
                noStatsLabel
            }
        } else {
            if let stats = card.hittingStats {
                statsGrid([
                    ("G",   "\(stats.games)"),
                    ("AB",  "\(stats.atBats)"),
                    ("AVG", stats.avg),
                    ("HR",  "\(stats.homeRuns)"),
                    ("RBI", "\(stats.rbi)"),
                    ("OPS", stats.ops),
                ])
            } else {
                noStatsLabel
            }
        }
    }

    private func statsGrid(_ items: [(String, String)]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
            spacing: 6
        ) {
            ForEach(items, id: \.0) { label, value in
                StatCellView(label: label, value: value)
            }
        }
    }

    private var noStatsLabel: some View {
        Text("No MLB career stats")
            .font(.caption)
            .foregroundStyle(.secondary)
            .italic()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

struct StatCellView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}


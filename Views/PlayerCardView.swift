//
//  PlayerCardView.swift
//  MLBCallups
//
//  Created by Nicolas Richards on 2/20/26.
//
// Build the card for each player called up. Name, team, position, news about the player, and MLB career stats (if any)

import SwiftUI

struct PlayerCardView: View {
    let card: PlayerCard
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: headshot + name + team
            HStack(alignment: .center, spacing: 12) {
                AsyncImage(url: card.headshotURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.blue)
                        .onTapGesture {
                            if let url = URL(string: "https://www.baseball-reference.com/redirect.fcgi?player=1&mlb_ID=\(card.id)") {
                                openURL(url)
                            }
                        }
                    Text(card.team)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding([.top, .horizontal], 12)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 8) {
                // Position badge + bucket badge
                HStack(spacing: 6) {
                    Text(card.positionName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(positionColor(for: card.positionAbbr).opacity(0.18))
                        .foregroundStyle(positionColor(for: card.positionAbbr))
                        .clipShape(Capsule())
                    Text(card.bucketTitle)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(bucketColor.opacity(0.18))
                        .foregroundStyle(bucketColor)
                        .clipShape(Capsule())
                }

                // Transaction description
                Text(card.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Stats
                StatsGridView(card: card)

                // Callup history
                if !card.callupHistory.isEmpty {
                    Divider().padding(.top, 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Previously called up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        ForEach(card.callupHistory, id: \.self) { date in
                            Text(date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding([.horizontal, .bottom], 12)
        }
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(bucketColor.opacity(0.5), lineWidth: 1.5)
        )
    }

    private var bucketColor: Color {
        switch card.callupBucket {
        case .mlbDebut:               return .green
        case .firstCallupThisYear:    return .blue
        case .alreadyCalledUpThisYear: return .orange
        case .notEligible:            return .red
        case .brefRateLimited:        return .yellow
        }
    }

    private func positionColor(for abbr: String) -> Color {
        switch abbr {
        case "P", "SP", "RP", "TWP": return .orange
        case "C": return .purple
        case "1B", "2B", "3B", "SS": return .red
        default: return .blue
        }
    }
}


//
//  ContentView.swift
//  MLBCallups
//
//  Created by Nicolas Richards on 2/20/26.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var viewModel = TrackerViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var now: Date = Date()

    private var gridColumns: [GridItem] {
        #if os(macOS)
        return [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 12, alignment: .top)]
        #else
        if horizontalSizeClass == .compact {
            return [GridItem(.flexible())]
        } else {
            return [GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 12, alignment: .top)]
        }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            dateNavBar
            rateLimitBanner
            Divider()
            contentArea
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
        .onAppear { viewModel.loadCards() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { viewModel.loadCards() }
        }
    }

    // MARK: - Rate Limit Banner

    @ViewBuilder
    private var rateLimitBanner: some View {
        if let until = viewModel.brefRateLimitUntil, until > now {
            // TimelineView drives the countdown — no Timer publisher gets
            // re-created on every body evaluation.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let secondsRemaining = max(0, Int(until.timeIntervalSince(context.date)))
                let minutes = secondsRemaining / 60
                let seconds = secondsRemaining % 60

                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Baseball Reference is rate limiting this app. Rookie eligibility may be incomplete. Try again in \(minutes)m \(String(format: "%02d", seconds))s.")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.18))
                .onChange(of: secondsRemaining) { remaining in
                    // Keep `now` fresh so the banner's visibility condition
                    // re-evaluates and it disappears when the window expires.
                    if remaining <= 0 { now = Date() }
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        let displayed = viewModel.filteredCards
        switch viewModel.loadingState {
        case .loading:
            ProgressView("Loading call-ups…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            ScrollView {
                EmptyStateView(
                    icon: "figure.baseball",
                    title: "No call-ups",
                    message: "No players were called up on \(viewModel.displayDate). Try another date or check back during the MLB season (April–October)."
                )
            }

        case .error(let message):
            ScrollView {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Could not load data",
                    message: message
                )
            }

        case .loaded:
            if displayed.isEmpty {
                ScrollView {
                    EmptyStateView(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "No call-ups for \(viewModel.selectedTeam?.abbreviation ?? "this team")",
                        message: "No players from \(viewModel.selectedTeam?.name ?? "this team") were called up on \(viewModel.displayDate)."
                    )
                }
            } else {
                tieredCallupList(displayed)
            }

        case .idle:
            Spacer()
        }
    }

    // MARK: - Tiered Layout

    @ViewBuilder
    private func tieredCallupList(_ cards: [PlayerCard]) -> some View {
        let debut          = cards.filter { $0.callupBucket == .mlbDebut }.sorted { $0.name < $1.name }
        let firstThisYear  = cards.filter { $0.callupBucket == .firstCallupThisYear }.sorted { $0.name < $1.name }
        let alreadyThisYear = cards.filter { $0.callupBucket == .alreadyCalledUpThisYear }.sorted { $0.name < $1.name }
        let notEligible    = cards.filter { $0.callupBucket == .notEligible }.sorted { $0.name < $1.name }
        let rateLimited    = cards.filter { $0.callupBucket == .brefRateLimited }.sorted { $0.name < $1.name }

        #if os(iOS)
        if horizontalSizeClass == .compact {
            List {
                callupListSection(title: "MLB Debut", cards: debut)
                callupListSection(title: "Eligible — First Call-Up This Year", cards: firstThisYear)
                callupListSection(title: "Eligible — Called Up Already This Year", cards: alreadyThisYear)
                callupListSection(title: "Not Eligible", cards: notEligible)
                callupListSection(title: "B-Ref Rate Limited", cards: rateLimited)
            }
            .listStyle(.plain)
        } else {
            tieredGrid(debut: debut, firstThisYear: firstThisYear,
                       alreadyThisYear: alreadyThisYear, notEligible: notEligible, rateLimited: rateLimited)
        }
        #else
        tieredGrid(debut: debut, firstThisYear: firstThisYear,
                   alreadyThisYear: alreadyThisYear, notEligible: notEligible, rateLimited: rateLimited)
        #endif
    }

    @ViewBuilder
    private func tieredGrid(debut: [PlayerCard], firstThisYear: [PlayerCard],
                            alreadyThisYear: [PlayerCard], notEligible: [PlayerCard],
                            rateLimited: [PlayerCard]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                callupGridSection(title: "MLB Debut", cards: debut)
                callupGridSection(title: "Eligible — First Call-Up This Year", cards: firstThisYear)
                callupGridSection(title: "Eligible — Called Up Already This Year", cards: alreadyThisYear)
                callupGridSection(title: "Not Eligible", cards: notEligible)
                callupGridSection(title: "B-Ref Rate Limited", cards: rateLimited)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func callupGridSection(title: String, cards: [PlayerCard]) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.title2.bold())
                    Text("\(cards.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(cards) { card in
                        PlayerCardView(card: card)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func callupListSection(title: String, cards: [PlayerCard]) -> some View {
        if !cards.isEmpty {
            Section(title) {
                ForEach(cards) { card in
                    PlayerCardView(card: card)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
    }

    // MARK: - Nav Bar

    private var dateNavBar: some View {
        HStack(spacing: 10) {
            Button(action: viewModel.goToPreviousDay) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)

            DatePicker(
                "",
                selection: $viewModel.selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .onChange(of: viewModel.selectedDate) { _ in
                viewModel.loadCards()
            }

            Button(action: viewModel.goToNextDay) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isAtToday)

            Spacer()

            // Team filter
            Menu {
                Button {
                    viewModel.selectedTeamID = nil
                } label: {
                    if viewModel.selectedTeamID == nil {
                        Label("All Teams", systemImage: "checkmark")
                    } else {
                        Text("All Teams")
                    }
                }
                Divider()
                ForEach(MLBAPIClient.allTeams) { team in
                    Button {
                        viewModel.selectedTeamID = team.id
                    } label: {
                        if viewModel.selectedTeamID == team.id {
                            Label(team.name, systemImage: "checkmark")
                        } else {
                            Text(team.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle\(viewModel.selectedTeamID != nil ? ".fill" : "")")
                    if let team = viewModel.selectedTeam {
                        Text(team.abbreviation)
                            .font(.caption.bold())
                    }
                }
                .foregroundStyle(viewModel.selectedTeamID != nil ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.bordered)

            if case .loaded = viewModel.loadingState {
                let count = viewModel.filteredCards.count
                Text("\(count) call-up\(count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

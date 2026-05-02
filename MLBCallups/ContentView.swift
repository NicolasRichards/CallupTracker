//
//  ContentView.swift
//  MLBCallups
//
//  Created by Nicolas Richards on 2/20/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TrackerViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    private var gridColumns: [GridItem] {
        #if os(macOS)
        return [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 12)]
        #else
        if horizontalSizeClass == .compact {
            return [GridItem(.flexible())]
        } else {
            return [GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 12)]
        }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            dateNavBar
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
                    title: "No rookie call-ups",
                    message: "No rookie-eligible players were called up on \(viewModel.displayDate). Try another date or check back during the MLB season (April–October)."
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
                        message: "No rookie-eligible players from \(viewModel.selectedTeam?.name ?? "this team") were called up on \(viewModel.displayDate)."
                    )
                }
            } else {
                #if os(iOS)
                if horizontalSizeClass == .compact {
                    List(displayed) { card in
                        PlayerCardView(card: card)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(displayed) { card in
                                PlayerCardView(card: card)
                            }
                        }
                        .padding(16)
                    }
                }
                #else
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(displayed) { card in
                            PlayerCardView(card: card)
                        }
                    }
                    .padding(16)
                }
                #endif
            }

        case .idle:
            Spacer()
        }
    }

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

            Text(viewModel.displayDate)
                .font(.headline)
                .foregroundStyle(.secondary)

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

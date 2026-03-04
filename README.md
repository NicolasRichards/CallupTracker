# MLB Callups

A native iOS/macOS app (Swift + SwiftUI) that tracks MLB rookie call-ups by date. Browse any day during the season to see which rookie-eligible players were called up, along with their stats and career info.

## Requirements

- **Xcode 15+** (Swift 5.9+)
- **iOS 16.0+ / macOS 13.0+** deployment target
- iPhone, iPad, or Mac

## Build & Run

1. Open `MLBCallups.xcodeproj` in Xcode.
2. Select your target device or simulator from the scheme picker.
3. Press **⌘R** (or Product → Run).

> If running on a physical device, set your Development Team in *Signing & Capabilities* (Target → MLBCallups → Signing & Capabilities → Team).

## Usage

- **Date navigation** — Use the left/right arrows or the date picker to browse by day.
- **Player cards** — Each card shows the called-up player's info, position, and career stats.
- **Season range** — Data is available during the MLB regular season (April–October).

## Features

- Day-by-day navigation of rookie call-ups
- Player cards with career stats
- Adaptive layout: single-column list on iPhone, grid on iPad and Mac
- Supports iOS and macOS from a single codebase

## Project Structure

```
MLBCallups/
├── MLBCallups.xcodeproj/
├── MLBCallups/
│   ├── MLBCallupsApp.swift       — @main entry point
│   └── ContentView.swift         — Main view with date nav and player grid/list
├── Models/
│   ├── PlayerCard.swift          — Primary display model
│   ├── PlayerInfo.swift          — Player biographical data
│   ├── CareerStats.swift         — Career statistics model
│   └── Transaction.swift         — Call-up transaction model
├── ViewModels/
│   └── TrackerViewModel.swift    — Date navigation + data loading
├── Views/
│   ├── PlayerCardView.swift      — Individual player card
│   ├── StatsGridView.swift       — Career stats grid layout
│   └── EmptyStateView.swift      — Empty/error state view
└── Networking/
    └── MLBAPIClient.swift        — MLB data API client
```

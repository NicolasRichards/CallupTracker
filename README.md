# CallupTracker

A native iOS, iPadOS and macOS app (Swift + SwiftUI) that tracks rookie call-ups to the majors by date. Browse any day of the season to see which players were called up, whether they're still rookie-eligible, and their stats and career info. Formerly named MLBCallups.

## Requirements

- **Xcode 26 or later** (Swift 6)
- **iOS 17.0+ / macOS 14.0+** deployment target
- iPhone, iPad or Mac

## Build & Run

1. Open `CallupTracker.xcodeproj` in Xcode.
2. Select your target device or simulator from the scheme picker.
3. Press **⌘R** (or Product → Run).

> If running on a physical device, set your Development Team in *Signing & Capabilities* (Target → CallupTracker → Signing & Capabilities → Team).

## Usage

- **Date navigation:** use the left/right arrows or the date picker to browse by day.
- **Team filter:** the filter button in the navigation bar narrows the list to one club.
- **Player cards:** each card shows the player's info, position, career stats and any earlier call-up dates.
- **Season range:** data is available during the regular season (April to October).

## Features

- Day-by-day call-ups, grouped into MLB Debut, Eligible (first call-up this year), Eligible (already called up this year) and Not Eligible
- Rookie eligibility checked against Baseball-Reference; players it couldn't check because of rate limiting are listed separately
- Team filter covering all 30 clubs
- Local notifications for new call-ups, using background refresh (iPhone and iPad)
- Home Screen widget in small and medium sizes
- Optional tip jar (consumable in-app purchases)
- Adaptive layout: single-column list on iPhone, grid on iPad and Mac

## Project Structure

```
CallupTracker/
├── CallupTracker.xcodeproj/
├── CallupTracker/
│   ├── CallupTrackerApp.swift      — @main entry point
│   ├── ContentView.swift           — Date navigation, team filter, grouped list/grid
│   ├── NotificationManager.swift   — Background refresh + local notifications (iOS)
│   ├── SharedCallupData.swift      — Data shared with the widget via the App Group
│   ├── AboutView.swift             — About screen with the tip jar
│   ├── TipJar.swift                — StoreKit 2 tips
│   └── CallupTracker.storekit      — Local StoreKit test configuration
├── CallupWidget/
│   ├── CallupWidget.swift          — WidgetKit widget (small + medium)
│   └── CallupWidgetBundle.swift
├── Shared/
│   └── CallupRules.swift           — Call-up rules shared by the app, notifications and widget
├── Models/
│   ├── PlayerCard.swift            — Primary display model and call-up grouping
│   ├── PlayerInfo.swift            — Player biographical data
│   ├── CareerStats.swift           — Career statistics model
│   └── Transaction.swift           — Call-up transaction model
├── ViewModels/
│   └── TrackerViewModel.swift      — Date navigation, data loading, team filter, call-up history
├── Views/
│   ├── PlayerCardView.swift        — Individual player card
│   ├── StatsGridView.swift         — Career stats grid layout
│   └── EmptyStateView.swift        — Empty/error state view
└── Networking/
    ├── MLBAPIClient.swift          — MLB Stats API client and team list
    └── BaseballReferenceClient.swift — Rookie-eligibility lookups
```

The internal identifiers still use the old name: bundle ID `NickRichards.MLBCallups`, App Group `group.NickRichards.MLBCallups` and background task `NickRichards.MLBCallups.refresh`. Changing them would break the widget and background refresh.

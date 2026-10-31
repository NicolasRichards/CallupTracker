# CallupTracker

iOS, iPadOS and macOS app (SwiftUI, Swift 6, iOS 17.0+ / macOS 14.0+) that lists the rookie-eligible players called up to MLB on any date, with stats, career info and earlier call-up dates. Live on the App Store. Formerly named MLBCallups; renamed in May 2026. Data comes from the MLB Stats API.

## Workflow

The owner runs Claude Code locally on a Mac, in this folder, and opens the project in Xcode to find the latest changes. The owner does not use Terminal, so do not ask them to run git or shell commands; do the git work yourself. This folder is the only source; `~/Documents/Claude App Notes/CallupTracker/` holds the owner's notes and assets and is read-only reference, never code.

- Build from the command line with `xcodebuild -project CallupTracker.xcodeproj -scheme CallupTracker -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` (verified on the owner's Mac, 2026-10-27). Do not report a build as passing unless one actually ran. There is no test target.
- Cloud sessions work on a fresh clone with no Xcode: say plainly that a change is unbuilt, push a `claude/...` branch, and merge it into `main` rather than copying its commits onto `main`.
- `CallupTracker/` and `CallupWidget/` are synchronized folder groups, so new files there are picked up without editing `project.pbxproj`. `Shared/`, `Models/`, `Networking/`, `ViewModels/` and `Views/` are classic groups: a new file there needs its own file reference and build-file entries for each target. Avoid hand-editing the project otherwise, and say so when you do.
- Before committing, review your own diff for regressions. Commit and push to `main` when the work is done.

## Layout

- `CallupTracker/`: app entry, `ContentView` (date picker, team filter), `NotificationManager` (BGAppRefreshTask + local notifications, iOS only), `AboutView`, `TipJar`, `CallupTracker.storekit`
- `CallupWidget/`: WidgetKit extension (small and medium)
- `Shared/`: compiled into both the app and the widget so all three paths agree. `CallupRules` (filter rules), `CallupFeed` (SE confirmation: an SE counts only from 10 days before the regular season through the postseason, and only if the player is on a dated active roster of 29 or fewer, since bigger "active" rosters are really the 40-man; plus the rookie heuristic; fails closed and marks results incomplete), `CallupDates` ("yyyy-MM-dd" days; today is US Eastern, the feed's time zone), `SharedCallupData` (App Group payload for the widget). The widget also compiles `MLBAPIClient` and the `Transaction`, `PlayerInfo` and `CareerStats` models.
- `Networking/`: `MLBAPIClient` (MLB Stats API) and `BaseballReferenceClient`
- `Models/`, `ViewModels/TrackerViewModel.swift` (data pipeline, team filter, call-up history), `Views/`
- `AppStoreScreenshots/`

## Conventions and gotchas

- Keep the internal identifiers from the old name: bundle ID `NickRichards.MLBCallups`, App Group `group.NickRichards.MLBCallups`, background task `NickRichards.MLBCallups.refresh`. Renaming them breaks the widget's App Group and background refresh.
- The app has its own `Transaction` model, which shadows StoreKit's; tip-jar code must say `StoreKit.Transaction`.
- Tip jar: consumable tips `NickRichards.CallupTracker.tip.{small,medium,large}`. `TipJar.shared.startListening()` runs once from the `App` init, never from the tip screen or a window's `.task` (on macOS the app outlives its window). `didTip` is session-only.
- App Store listing: never use the literal "MLB" or "MiLB" in the name, subtitle, description or keywords (Guideline 4.1(a) risk; the app was renamed from MLBCallups for this reason). Spell out "major league" or "minor league" instead. In-app text and code are fine. Screenshots that show real team names carry the same risk.
- The app was once rejected under Guideline 4.2 as a replica of a web service; the widget, notifications and call-up history were added in response. Keep native features when trimming.
- Version bumps are their own commits, titled like `Bump to 1.14 (25)`. The owner archives and uploads from Xcode.
- The repo is public on purpose (GitHub Pages hosts the privacy page), so never commit secrets.

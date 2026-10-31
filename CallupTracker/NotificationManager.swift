//
//  NotificationManager.swift
//  MLBCallups
//

#if os(iOS)
import Foundation
import UserNotifications
import BackgroundTasks

final class NotificationManager: Sendable {

    static let shared = NotificationManager()
    private init() {}

    static let taskIdentifier = "NickRichards.MLBCallups.refresh"
    /// Notified player IDs per feed date ("yyyy-MM-dd"), for today and yesterday.
    private static let notifiedByDateKey = "notifiedCallupIDsByDate"
    // Single-day keys from older builds, migrated on first read.
    private static let legacyNotifiedKey = "notifiedCallupIDs"
    private static let legacyNotifiedDateKey = "notifiedCallupDate"

    // MARK: - Permission

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    // MARK: - Background Task Registration (call from App init, before first scene)

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task {
                await NotificationManager.shared.handleAppRefresh(task: refreshTask)
            }
        }
    }

    // MARK: - Scheduling

    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Called at launch. Resubmitting would replace the pending request and push
    /// its start time back on every launch.
    func scheduleRefreshIfNeeded() async {
        let pending = await BGTaskScheduler.shared.pendingTaskRequests()
        guard !pending.contains(where: { $0.identifier == Self.taskIdentifier }) else { return }
        scheduleNextRefresh()
    }

    // MARK: - Handler

    private func handleAppRefresh(task: BGAppRefreshTask) async {
        scheduleNextRefresh()

        let fetchTask = Task {
            let today = CallupDates.today()
            let yesterday = CallupDates.dayBefore(today)
            var notified = loadNotified(today: today, yesterday: yesterday)
                .filter { $0.key == today || $0.key == yesterday }

            // Yesterday has an entry only if it was checked while it was today; one
            // more look catches call-ups posted after that last same-day refresh.
            var dates = [today]
            if let yesterday, notified[yesterday] != nil { dates.insert(yesterday, at: 0) }
            if notified[today] == nil { notified[today] = [] }

            var success = true
            for date in dates {
                do {
                    let complete = try await notifyNewCallups(on: date, isToday: date == today, notified: &notified)
                    if date != today && complete { notified[date] = nil }
                } catch {
                    success = false
                }
            }
            saveNotified(notified)
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = { fetchTask.cancel() }
        await fetchTask.value
    }

    /// Notifies about rookie call-ups on `date` that haven't been notified yet.
    /// Returns false when a lookup failed, so the date is worth checking again;
    /// players that couldn't be judged aren't marked notified.
    private func notifyNewCallups(on date: String, isToday: Bool,
                                  notified: inout [String: Set<Int>]) async throws -> Bool {
        let alreadyNotified = notified[date] ?? []
        let day = try await CallupFeed.confirmedCallups(on: date, api: .shared)
        let newCallups = day.callups.filter { txn in
            guard let id = txn.person?.id else { return false }
            return !alreadyNotified.contains(id)
        }
        let rookies = await CallupFeed.rookieEligible(newCallups, on: date, api: .shared)

        if !rookies.callups.isEmpty {
            // Report the running daily total so the alert count matches what the app shows
            let total = alreadyNotified.count + rookies.callups.count
            await send(callups: rookies.callups, total: total, isToday: isToday)
        }
        notified[date] = alreadyNotified.union(rookies.callups.compactMap { $0.person?.id })
        return !day.isIncomplete && rookies.failedIDs.isEmpty
    }

    private func loadNotified(today: String, yesterday: String?) -> [String: Set<Int>] {
        let defaults = UserDefaults.standard
        var notified: [String: Set<Int>] = [:]
        if let stored = defaults.dictionary(forKey: Self.notifiedByDateKey) as? [String: [Int]] {
            notified = stored.mapValues(Set.init)
        }
        if defaults.string(forKey: Self.legacyNotifiedDateKey) != nil {
            // The legacy date was device-local, which can be a day off the Eastern
            // date, so file its IDs under both days rather than re-notify them.
            let legacyIDs = (defaults.array(forKey: Self.legacyNotifiedKey) as? [Int]) ?? []
            for date in [today, yesterday].compactMap({ $0 }) {
                notified[date, default: []].formUnion(legacyIDs)
            }
            defaults.removeObject(forKey: Self.legacyNotifiedKey)
            defaults.removeObject(forKey: Self.legacyNotifiedDateKey)
        }
        return notified
    }

    private func saveNotified(_ notified: [String: Set<Int>]) {
        UserDefaults.standard.set(notified.mapValues { Array($0) }, forKey: Self.notifiedByDateKey)
    }

    // MARK: - Notification Delivery

    private func send(callups: [Transaction], total: Int, isToday: Bool) async {
        let content = UNMutableNotificationContent()
        let day = isToday ? "Today" : "Yesterday"
        if let name = callups[0].person?.fullName, let team = callups[0].toTeam?.name {
            if total == 1 {
                content.title = isToday ? "Rookie Called Up" : "Rookie Called Up Yesterday"
                content.body = "\(name) called up to \(team)"
            } else {
                content.title = "Rookie Callups \(day)"
                content.body = "Includes \(name) — tap to see all"
            }
        } else {
            content.title = "Rookie Callups \(day)"
            content.body = "Tap to see \(day.lowercased())'s rookie-eligible callups"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

#endif

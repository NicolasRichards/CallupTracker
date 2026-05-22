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
    private static let notifiedKey = "notifiedCallupIDs"
    private static let notifiedDateKey = "notifiedCallupDate"

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

    // MARK: - Handler

    private func handleAppRefresh(task: BGAppRefreshTask) async {
        scheduleNextRefresh()

        let fetchTask = Task {
            do {
                let today = todayDateString()
                let transactions = try await MLBAPIClient.shared.fetchTransactions(for: today)
                let callups = transactions.filter { txn in
                    guard let code = txn.typeCode, (code == "CU" || code == "SE") else { return false }
                    guard let toID = txn.toTeam?.id, MLBAPIClient.mlbTeamIDs.contains(toID) else { return false }
                    // Accept if API provides fromTeam, or if description says "from [minor league team]"
                    return txn.fromTeam != nil || txn.description?.lowercased().contains(" from ") == true
                }

                // Reset daily tracking when the date changes so totals stay accurate per day
                let storedDate = UserDefaults.standard.string(forKey: Self.notifiedDateKey) ?? ""
                if storedDate != today {
                    UserDefaults.standard.removeObject(forKey: Self.notifiedKey)
                    UserDefaults.standard.set(today, forKey: Self.notifiedDateKey)
                }

                let notifiedIDs = Set((UserDefaults.standard.array(forKey: Self.notifiedKey) as? [Int]) ?? [])
                var seen = Set<Int>()
                let newCallups = callups.filter { txn in
                    guard let id = txn.person?.id, !notifiedIDs.contains(id), !seen.contains(id) else { return false }
                    seen.insert(id)
                    return true
                }

                // Filter to rookie-eligible only (mirrors buildCard logic in TrackerViewModel)
                let rookieCallups = await rookieEligible(from: newCallups)

                if !rookieCallups.isEmpty {
                    // Report the running daily total so the alert count matches what the app shows
                    let totalToday = notifiedIDs.count + rookieCallups.count
                    await send(callups: rookieCallups, totalToday: totalToday)
                    let allNotified = notifiedIDs.union(rookieCallups.compactMap { $0.person?.id })
                    UserDefaults.standard.set(Array(allNotified), forKey: Self.notifiedKey)
                }

                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = { fetchTask.cancel() }
        await fetchTask.value
    }

    // Returns only rookie-eligible players: pitchers with < 50 career IP, hitters with < 130 career AB.
    private func rookieEligible(from callups: [Transaction]) async -> [Transaction] {
        await withTaskGroup(of: Transaction?.self) { group in
            for txn in callups {
                group.addTask {
                    guard let playerID = txn.person?.id,
                          let info = try? await MLBAPIClient.shared.fetchPlayerInfo(playerID: playerID)
                    else { return nil }

                    let posAbbr = info.primaryPosition?.abbreviation ?? ""
                    let isPitcher = ["P", "SP", "RP", "TWP"].contains(posAbbr)

                    if isPitcher {
                        let raw = try? await MLBAPIClient.shared.fetchCareerPitching(playerID: playerID)
                        let ipStr = raw?.inningsPitched ?? "0"
                        let ipParts = ipStr.split(separator: ".")
                        let ipFull = Double(ipParts.first ?? "0") ?? 0
                        let ipThirds = Double(ipParts.dropFirst().first ?? "0") ?? 0
                        let ip = ipFull + ipThirds / 3.0
                        return ip < 50 ? txn : nil
                    } else {
                        let raw = try? await MLBAPIClient.shared.fetchCareerHitting(playerID: playerID)
                        let ab = raw.flatMap { $0.atBats } ?? 0
                        return ab < 130 ? txn : nil
                    }
                }
            }
            var result: [Transaction] = []
            for await txn in group {
                if let txn { result.append(txn) }
            }
            return result
        }
    }

    // MARK: - Notification Delivery

    private func send(callups: [Transaction], totalToday: Int) async {
        let content = UNMutableNotificationContent()
        if totalToday == 1, let name = callups[0].person?.fullName, let team = callups[0].toTeam?.name {
            content.title = "Rookie Called Up"
            content.body = "\(name) called up to \(team)"
        } else {
            content.title = "Rookie Callups Today"
            content.body = "\(totalToday) rookie-eligible callups today"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    private func todayDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

#endif

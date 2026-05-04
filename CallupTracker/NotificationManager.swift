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
                    return txn.fromTeam != nil
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
                    await send(callups: rookieCallups)
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
                        let ip = raw.flatMap { $0.inningsPitched }.map { self.parseInnings($0) } ?? 0
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

    private func parseInnings(_ ip: String) -> Double {
        let parts = ip.split(separator: ".")
        let full = Double(parts.first ?? "0") ?? 0
        let thirds = Double(parts.dropFirst().first ?? "0") ?? 0
        return full + thirds / 3.0
    }

    // MARK: - Notification Delivery

    private func send(callups: [Transaction]) async {
        let content = UNMutableNotificationContent()
        if callups.count == 1, let name = callups[0].person?.fullName, let team = callups[0].toTeam?.name {
            content.title = "Rookie Called Up"
            content.body = "\(name) called up to \(team)"
        } else {
            content.title = "Rookie Callups Today"
            content.body = "\(callups.count) rookie-eligible players called up today"
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

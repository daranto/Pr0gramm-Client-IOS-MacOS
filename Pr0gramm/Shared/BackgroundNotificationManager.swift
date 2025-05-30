// Pr0gramm/Pr0gramm/Shared/BackgroundNotificationManager.swift
// --- START OF COMPLETE FILE ---

import Foundation
@preconcurrency import BackgroundTasks
import UserNotifications
import UIKit
import os

@MainActor
class BackgroundNotificationManager {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "BackgroundNotificationManager")
    static let shared = BackgroundNotificationManager()

    let taskIdentifier = "com.aetherium.Pr0gramm.fetchNewMessages"
    private let lastNotifiedCountsKey = "lastNotifiedCountsKey_v1"

    static let backgroundFetchFailureCountKey = "backgroundFetchFailureCountKey_v1_updated"
    private let maxBackgroundFetchFailures = 5
    private let backgroundFetchRetryDelay: TimeInterval = 5

    // --- Debug Log Buffer (intern) ---
    private var debugLogBuffer: [String] = []
    private func addToDebugLog(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        debugLogBuffer.append("[\(timestamp)] \(message)")
        if debugLogBuffer.count > 20 { // Etwas Puffer für interne Logs
            debugLogBuffer.removeFirst()
        }
    }
    private func getFormattedDebugLogAndClear() -> String {
        let log = debugLogBuffer.joined(separator: "\n")
        debugLogBuffer.removeAll()
        return log
    }
    // --- END Debug Log Buffer ---


    private init() {}

    private func getBackgroundFetchFailureCount() -> Int {
        UserDefaults.standard.integer(forKey: Self.backgroundFetchFailureCountKey)
    }

    private func incrementBackgroundFetchFailureCount() {
        let currentCount = getBackgroundFetchFailureCount()
        let newCount = currentCount + 1
        UserDefaults.standard.set(newCount, forKey: Self.backgroundFetchFailureCountKey)
        Self.logger.info("Incremented background fetch failure count to: \(newCount)")
        addToDebugLog("BGTask: Failure count incremented to \(newCount).")
    }

    private func resetBackgroundFetchFailureCountInternal() {
        let currentCount = getBackgroundFetchFailureCount()
        if currentCount > 0 {
            UserDefaults.standard.set(0, forKey: Self.backgroundFetchFailureCountKey)
            Self.logger.info("Reset background fetch failure count to 0 internally after successful fetch.")
            addToDebugLog("BGTask: Failure count reset to 0.")
        }
    }

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: self.taskIdentifier, using: nil) { [weak self] task in
            guard let strongSelf = self else {
                BackgroundNotificationManager.logger.warning("Background task registration closure called, but self is nil.")
                task.setTaskCompleted(success: false)
                return
            }
            strongSelf.addToDebugLog("BGTask: Registered closure called.")
            BackgroundNotificationManager.logger.info("Background task \(strongSelf.taskIdentifier) starting.")
            strongSelf.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        Self.logger.info("Background task \(self.taskIdentifier) registered.")
        addToDebugLog("BGTask: Registered successfully.")
    }

    func scheduleAppRefresh() {
        let failureCount = getBackgroundFetchFailureCount()
        if failureCount >= self.maxBackgroundFetchFailures {
            Self.logger.warning("Skipping scheduleAppRefresh: Maximum background fetch failures (\(failureCount)/\(self.maxBackgroundFetchFailures)) reached. Task will not be scheduled until app is opened.")
            addToDebugLog("BGTask: Schedule SKIPPED - Max failures reached.")
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            Self.logger.info("Successfully scheduled background app refresh task: \(self.taskIdentifier). Earliest next run: \(request.earliestBeginDate?.description ?? "N/A")")
            addToDebugLog("BGTask: Scheduled. Next: \(request.earliestBeginDate?.description ?? "ASAP")")
        } catch {
            Self.logger.error("Could not schedule app refresh task \(self.taskIdentifier): \(error.localizedDescription)")
            addToDebugLog("BGTask: Schedule FAILED: \(error.localizedDescription.prefix(50))")
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        addToDebugLog("BGTask: handleAppRefresh started.")

        let initialFailureCount = getBackgroundFetchFailureCount()
        if initialFailureCount >= self.maxBackgroundFetchFailures {
            Self.logger.warning("Background task \(self.taskIdentifier) aborted at start: Failure count (\(initialFailureCount)) reached maximum (\(self.maxBackgroundFetchFailures)).")
            addToDebugLog("BGTask: Aborted at start - Max failures reached.")
            task.setTaskCompleted(success: false)
            // --- REMOVED: Debug Notification bei Ablauf/Abbruch wegen Fehlerlimit ---
            return
        }
        
        scheduleAppRefresh()

        task.expirationHandler = { [weak self] in
            guard let strongSelf = self else { return }
            BackgroundNotificationManager.logger.warning("Background task \(strongSelf.taskIdentifier) expired.")
            strongSelf.addToDebugLog("BGTask: EXPIRED!")
            // --- REMOVED: Debug Notification bei Ablauf ---
            task.setTaskCompleted(success: false)
        }

        Task {
            addToDebugLog("BGTask: Detached Task started.")
            BackgroundNotificationManager.logger.info("Background task operation \(self.taskIdentifier) starting within detached Task.")
            
            let localAppSettings = AppSettings()
            let localAuthService = AuthService(appSettings: localAppSettings)

            addToDebugLog("BGTask: AppSettings/AuthService inited.")
            await localAuthService.checkInitialLoginStatus()
            let isLoggedInAtStartOfTask = localAuthService.isLoggedIn
            addToDebugLog("BGTask: InitialLoginStatus checked. LoggedIn: \(isLoggedInAtStartOfTask)")
            
            if !isLoggedInAtStartOfTask {
                addToDebugLog("BGTask: User NOT logged in. Task considered successful (no API error).")
                await self.setApplicationBadgeNumber(0)
                await self.saveLastNotifiedTotalCount(0)
                self.resetBackgroundFetchFailureCountInternal()
                task.setTaskCompleted(success: true)
                // --- REMOVED: Debug Notification für "nicht eingeloggt" ---
                Self.logger.info("Background task \(self.taskIdentifier) completed (user not logged in).")
                // Log interne Debug-Infos, falls nötig
                let finalStatusMessage = getFormattedDebugLogAndClear()
                BackgroundNotificationManager.logger.info("Internal logs for this run (not logged in):\n\(finalStatusMessage)")
                return
            }
            
            var fetchSuccess = false
            var attempt = 1
            let maxAttempts = 2
            var lastError: Error? = nil

            while attempt <= maxAttempts && !fetchSuccess {
                addToDebugLog("BGTask: Attempt \(attempt)/\(maxAttempts) to fetch unread counts.")
                Self.logger.info("BGTask: Attempt \(attempt)/\(maxAttempts) for unread counts.")
                do {
                    try await localAuthService.fetchUnreadCountsForBackgroundTask()
                    fetchSuccess = true
                    addToDebugLog("BGTask: Counts fetched successfully on attempt \(attempt).")
                    Self.logger.info("BGTask: Counts fetched successfully on attempt \(attempt).")

                    let oldTotalUnreadCount = await self.getLastNotifiedTotalCount()
                    let newTotalUnreadCount = localAuthService.unreadInboxTotal
                    let numberOfActuallyNewMessages = newTotalUnreadCount - oldTotalUnreadCount

                    if newTotalUnreadCount > oldTotalUnreadCount {
                        addToDebugLog("BGTask: \(numberOfActuallyNewMessages) new messages. Scheduling standard notification.")
                        await self.scheduleStandardNotification(
                            newCommentCount: localAuthService.unreadCommentCount,
                            newPrivateMessageCount: localAuthService.unreadPrivateMessageCount,
                            newFollowCount: localAuthService.unreadFollowCount,
                            newNotificationCount: localAuthService.unreadSystemNotificationCount,
                            totalNew: numberOfActuallyNewMessages,
                            overallTotal: newTotalUnreadCount
                        )
                        await self.saveLastNotifiedTotalCount(newTotalUnreadCount)
                        await self.setApplicationBadgeNumber(newTotalUnreadCount)
                    } else if newTotalUnreadCount < oldTotalUnreadCount {
                        addToDebugLog("BGTask: Count decreased. Updating badge and saved count.")
                        await self.setApplicationBadgeNumber(newTotalUnreadCount)
                        await self.saveLastNotifiedTotalCount(newTotalUnreadCount)
                    } else {
                        addToDebugLog("BGTask: No new messages (count unchanged).")
                    }
                    
                    self.resetBackgroundFetchFailureCountInternal()
                    task.setTaskCompleted(success: true)
                    // --- REMOVED: Debug Notification für Erfolg ---
                    Self.logger.info("Background task \(self.taskIdentifier) completed successfully.")
                    // Log interne Debug-Infos, falls nötig
                    let finalStatusMessageSuccess = getFormattedDebugLogAndClear()
                    BackgroundNotificationManager.logger.info("Internal logs for this successful run:\n\(finalStatusMessageSuccess)")
                    return

                } catch {
                    lastError = error
                    Self.logger.error("BGTask: Error fetching unread counts on attempt \(attempt): \(error.localizedDescription)")
                    addToDebugLog("BGTask: Fetch error attempt \(attempt): \(error.localizedDescription.prefix(30))...")
                    
                    if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                         Self.logger.warning("BGTask: Authentication error detected. Will increment failure count but NOT logout.")
                         addToDebugLog("BGTask: Auth error on attempt \(attempt).")
                    }

                    if attempt < maxAttempts {
                        addToDebugLog("BGTask: Will retry after \(self.backgroundFetchRetryDelay)s.")
                        Self.logger.info("BGTask: Retrying fetch in \(self.backgroundFetchRetryDelay)s.")
                        try? await Task.sleep(for: .seconds(self.backgroundFetchRetryDelay))
                    }
                }
                attempt += 1
            }

            if !fetchSuccess {
                Self.logger.error("BGTask: All \(maxAttempts) fetch attempts failed. Last error: \(lastError?.localizedDescription ?? "Unknown")")
                self.incrementBackgroundFetchFailureCount()
                task.setTaskCompleted(success: false)
                // --- REMOVED: Debug Notification für Fehlschlag ---
                Self.logger.info("Background task \(self.taskIdentifier) completed with failure after all retries.")
                // Log interne Debug-Infos, falls nötig
                let finalStatusMessageFailure = getFormattedDebugLogAndClear()
                BackgroundNotificationManager.logger.info("Internal logs for this failed run:\n\(finalStatusMessageFailure)")
            }
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                BackgroundNotificationManager.logger.info("Notification permission granted.")
            } else if let error = error {
                BackgroundNotificationManager.logger.error("Notification permission denied with error: \(error.localizedDescription)")
            } else {
                BackgroundNotificationManager.logger.info("Notification permission denied.")
            }
        }
    }

    private func scheduleStandardNotification(newCommentCount: Int, newPrivateMessageCount: Int, newFollowCount: Int, newNotificationCount: Int, totalNew: Int, overallTotal: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Neue Nachrichten auf pr0gramm"
        
        var bodyParts: [String] = []
        if newCommentCount > 0 { bodyParts.append("\(newCommentCount) Kommentare/Antworten") }
        if newPrivateMessageCount > 0 { bodyParts.append("\(newPrivateMessageCount) PNs") }
        if newFollowCount > 0 { bodyParts.append("\(newFollowCount) Stelzes") }
        if newNotificationCount > 0 { bodyParts.append("\(newNotificationCount) System") }

        if bodyParts.isEmpty {
            // Sollte nicht passieren, wenn totalNew > 0, aber als Fallback
            content.body = "Du hast \(totalNew) neue Nachrichten."
        } else {
            content.body = bodyParts.joined(separator: ", ") + "."
        }
        
        content.sound = .default
        content.badge = NSNumber(value: overallTotal)
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false) // Minimale Verzögerung, um sofort auszulösen
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            BackgroundNotificationManager.logger.info("Successfully scheduled STANDARD local notification. Body: \(content.body). Badge will be \(overallTotal).")
        } catch {
            BackgroundNotificationManager.logger.error("Error scheduling STANDARD local notification: \(error.localizedDescription)")
        }
    }
    
    // --- REMOVED: scheduleDebugNotification Methode ---

    private func getLastNotifiedTotalCount() async -> Int {
        return UserDefaults.standard.integer(forKey: lastNotifiedCountsKey)
    }

    private func saveLastNotifiedTotalCount(_ count: Int) async {
        UserDefaults.standard.set(count, forKey: lastNotifiedCountsKey)
        Self.logger.info("Saved lastNotifiedTotalCount: \(count)")
    }

    func appDidBecomeActiveOrInboxViewed(currentTotalUnread: Int) async {
        await self.setApplicationBadgeNumber(currentTotalUnread)
        await self.saveLastNotifiedTotalCount(currentTotalUnread)
        Self.logger.info("App active or inbox viewed. Badge set to \(currentTotalUnread) and last notified count updated.")
        addToDebugLog("App Active/Inbox Viewed. Badge: \(currentTotalUnread)")
    }

    private func setApplicationBadgeNumber(_ number: Int) async {
        if #available(iOS 16.0, *) {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(number)
                Self.logger.info("Application badge count set to \(number) using UNUserNotificationCenter.setBadgeCount.")
            } catch {
                Self.logger.error("Failed to set badge count using UNUserNotificationCenter.setBadgeCount: \(error.localizedDescription)")
            }
        } else {
            #if !targetEnvironment(macCatalyst)
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = number
            }
            Self.logger.info("Application badge count set to \(number) using deprecated applicationIconBadgeNumber (iOS < 16).")
            #endif
        }
    }
}
// --- END OF COMPLETE FILE ---

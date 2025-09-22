// Pr0gramm/Pr0gramm/Pr0grammApp.swift
// --- START OF COMPLETE FILE ---
import SwiftUI
import AVFoundation
import os
import BackgroundTasks
import UserNotifications

struct DeepLinkData: Identifiable {
    let id: Int
    let itemIDValue: Int
    let commentIDValue: Int?

    init(itemID: Int, commentID: Int?) {
        self.id = itemID
        self.itemIDValue = itemID
        self.commentIDValue = commentID
    }
}

@main
struct Pr0grammApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) var scenePhase

    @StateObject private var appSettings: AppSettings
    @StateObject private var authService: AuthService
    @StateObject private var navigationService = NavigationService()
    @StateObject private var scenePhaseObserver: ScenePhaseObserver
    @StateObject private var appOrientationManager = AppOrientationManager()


    @State private var activeDeepLinkData: DeepLinkData? = nil

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Pr0grammApp")

    init() {
        let settings = AppSettings()
        let auth = AuthService(appSettings: settings)
        _appSettings = StateObject(wrappedValue: settings)
        _authService = StateObject(wrappedValue: auth)
        _scenePhaseObserver = StateObject(wrappedValue: ScenePhaseObserver(appSettings: settings, authService: auth))
        
        configureAudioSession()
        Pr0grammApp.logger.info("Pr0grammApp init")
        
        BackgroundNotificationManager.shared.configure(appSettings: settings)
        BackgroundNotificationManager.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appSettings)
                .environmentObject(authService)
                .environmentObject(navigationService)
                .environmentObject(scenePhaseObserver)
                .environmentObject(appOrientationManager)
                .onOpenURL { url in
                    Pr0grammApp.logger.info("App opened with URL: \(url.absoluteString)")
                    handleIncomingURL(url)
                }
                .sheet(item: $activeDeepLinkData) { data in
                    DeepLinkItemLoaderView(
                        itemID: data.itemIDValue,
                        targetCommentID: data.commentIDValue
                    )
                    .environmentObject(appSettings)
                    .environmentObject(authService)
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                Pr0grammApp.logger.info("App entering background. Scheduling app refresh task if enabled.")
                BackgroundNotificationManager.shared.scheduleAppRefresh()
            } else if newPhase == .active {
                Pr0grammApp.logger.info("App became active. Updating notification badge, resetting BG fetch failure count, and clearing delivered notifications.")
                
                UserDefaults.standard.set(0, forKey: BackgroundNotificationManager.backgroundFetchFailureCountKey)
                Pr0grammApp.logger.info("Reset background fetch failure count due to app becoming active.")
                
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                Pr0grammApp.logger.info("Removed all delivered notifications from Notification Center.")
                
                let currentTotal = authService.unreadInboxTotal
                Task {
                    await BackgroundNotificationManager.shared.appDidBecomeActiveOrInboxViewed(currentTotalUnread: currentTotal)
                }
                if appSettings.enableBackgroundFetchForNotifications {
                    BackgroundNotificationManager.shared.scheduleAppRefresh()
                    Pr0grammApp.logger.info("App active and background fetch enabled, ensuring task is scheduled.")
                }
            }
        }
    }
    
    private func configureAudioSession() {
        Self.logger.info("Configuring AVAudioSession...")
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            Self.logger.info("AVAudioSession category set to '.playback' with options '[.mixWithOthers]'.")
            try audioSession.setActive(true)
            Self.logger.info("AVAudioSession activated.")
            do {
                try audioSession.overrideOutputAudioPort(.speaker)
                Self.logger.info("AVAudioSession output successfully overridden to force speaker.")
            } catch let error as NSError {
                if error.code != -50 {
                    Self.logger.error("Failed to override output port to speaker: \(error.localizedDescription) (Code: \(error.code))")
                } else {
                     Self.logger.debug("Speaker output already set or override not possible (e.g. headphones connected). Error code -50 ignored.")
                }
            }
            Self.logger.info("AVAudioSession configuration complete.")
        } catch {
            Self.logger.error("Failed during AVAudioSession configuration (setCategory or setActive): \(error.localizedDescription)")
        }
    }

    private func handleIncomingURL(_ url: URL) {
        Pr0grammApp.logger.debug("Handling incoming URL: \(url.absoluteString)")
        guard url.scheme == "pr0grammapp" else {
            Pr0grammApp.logger.warning("URL scheme is not 'pr0grammapp'. Ignoring.")
            return
        }

        guard let host = url.host, host == "item" else {
            Pr0grammApp.logger.warning("URL host is not 'item'. Ignoring.")
            return
        }

        let pathComponents = url.pathComponents
        guard pathComponents.count > 1, let itemIDString = pathComponents.last, let itemID = Int(itemIDString) else {
            Pr0grammApp.logger.error("Could not parse itemID from URL path: \(url.path)")
            return
        }

        var commentID: Int? = nil
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            if let commentIDString = queryItems.first(where: { $0.name == "commentId" })?.value, let cID = Int(commentIDString) {
                commentID = cID
            }
        }
        
        Pr0grammApp.logger.info("Parsed deep link: ItemID = \(itemID), CommentID = \(commentID ?? -1)")
        DispatchQueue.main.async {
           self.activeDeepLinkData = DeepLinkData(itemID: itemID, commentID: commentID)
           Pr0grammApp.logger.info("activeDeepLinkData set. Sheet should present.")
        }
    }
}

struct AppRootView: View {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var scenePhaseObserver: ScenePhaseObserver
    @EnvironmentObject var appOrientationManager: AppOrientationManager
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        MainView()
            .accentColor(appSettings.accentColorChoice.swiftUIColor)
            .preferredColorScheme(appSettings.colorSchemeSetting.swiftUIScheme)
            .task {
                await authService.checkInitialLoginStatus()
            }
            .onChange(of: scenePhase, initial: true) { oldPhase, newPhase in
                scenePhaseObserver.handleScenePhaseChange(newPhase: newPhase, oldPhase: oldPhase)
            }
    }
}

struct DeepLinkItemLoaderView: View {
    let itemID: Int
    let targetCommentID: Int?
    @Environment(\.dismiss) var dismissSheet

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @StateObject private var playerManager = VideoPlayerManager()
    
    @State private var fetchedItem: Item? = nil
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var isFilterMismatch: Bool = false

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DeepLinkItemLoaderView")

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Lade Post \(itemID)...")
            } else if let error = errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.largeTitle)
                    Text("Fehler beim Laden").font(.headline)
                    Text(error).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Button("Erneut versuchen") { Task { await loadItem() } }.padding(.top)
                }
                .padding()
            } else if isFilterMismatch, let item = fetchedItem {
                VStack(spacing: 15) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Post ausgeblendet")
                        .font(.title2.bold())
                    Text("Dieser Post (ID: \(item.id)) ist mit deinen aktuellen Filtern nicht sichtbar.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Trotzdem anzeigen") {
                        isFilterMismatch = false
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)

                    Button("Abbrechen") {
                        dismissSheet()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(30)
            } else if let item = fetchedItem {
                NavigationStack {
                    PagedDetailViewWrapperForItem(
                        item: item,
                        playerManager: playerManager,
                        targetCommentID: targetCommentID,
                        isPresentedInSheet: true
                    )
                    .environmentObject(settings)
                    .environmentObject(authService)
                    .navigationTitle("Post \(item.id)")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                }
            } else {
                Text("Post nicht gefunden oder nicht für aktuelle Filter sichtbar.")
                    .onAppear {
                        DeepLinkItemLoaderView.logger.error("Fetched item was nil after loading for ID \(itemID).")
                    }
            }
        }
        .task {
            playerManager.configure(settings: settings)
            await loadItem()
        }
        .onAppear {
            DeepLinkItemLoaderView.logger.info("DeepLinkItemLoaderView appeared for itemID: \(itemID), targetCommentID: \(targetCommentID ?? -1)")
        }
    }

    private func loadItem() async {
        DeepLinkItemLoaderView.logger.info("Loading item for deep link: ID \(itemID)")
        isLoading = true
        errorMessage = nil
        fetchedItem = nil
        isFilterMismatch = false

        do {
            let flagsToFetchWith = authService.isLoggedIn ? settings.apiFlags : 1
            let itemWithCurrentFilters = try await apiService.fetchItem(id: itemID, flags: flagsToFetchWith)

            if let item = itemWithCurrentFilters {
                DeepLinkItemLoaderView.logger.info("Item \(itemID) found with current filters.")
                fetchedItem = item
                isFilterMismatch = false
            } else {
                DeepLinkItemLoaderView.logger.warning("Item \(itemID) not found with flags \(flagsToFetchWith). Retrying with flags 31.")
                let itemWithAllFlags = try await apiService.fetchItem(id: itemID, flags: 31)

                if let item = itemWithAllFlags {
                    DeepLinkItemLoaderView.logger.info("Item \(itemID) exists but is hidden by current filters. Setting isFilterMismatch to true.")
                    fetchedItem = item
                    isFilterMismatch = true
                } else {
                    DeepLinkItemLoaderView.logger.warning("Item \(itemID) could not be fetched for deep link, even with broad flags.")
                    errorMessage = "Post konnte nicht gefunden werden."
                }
            }
        } catch {
            DeepLinkItemLoaderView.logger.error("Error loading item ID \(itemID) for deep link: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
// --- END OF COMPLETE FILE ---

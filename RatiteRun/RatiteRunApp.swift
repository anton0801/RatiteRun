//
//  RatiteRunApp.swift
//  RatiteRun
//
//  App entry point — injects app-wide state and applies theme.
//

import SwiftUI

@main
struct RatiteRunApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var theme = ThemeManager()
    @StateObject private var notifier = NotificationManager.shared
    @StateObject private var auth = AuthManager.shared

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(theme)
                .environmentObject(notifier)
                .environmentObject(auth)
                .preferredColorScheme(theme.colorScheme)
                .accentColor(Palette.primary)
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .background, .inactive:
                        // недописанные правки не должны ждать дебаунса,
                        // если приложение сворачивают прямо сейчас
                        Task { await store.flushPendingChanges() }
                    case .active:
                        Task { await store.refresh() }
                    @unknown default:
                        break
                    }
                }
        }
    }
}

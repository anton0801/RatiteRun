//
//  RootView.swift
//  RatiteRun
//
//  Flow coordinator: Splash → (first launch) Onboarding → Main App.
//

import SwiftUI

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView(isActive: $showSplash)
                    .transition(.opacity)
            } else if !hasCompletedOnboarding {
                OnboardingView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45))
    }
}

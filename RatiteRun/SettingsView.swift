//
//  SettingsView.swift
//  RatiteRun
//
//  Fully-wired settings: theme, units, currency, defaults, notifications, backup.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var notifier: NotificationManager

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("unitSystem") private var unitRaw = UnitSystem.metric.rawValue
    @AppStorage("currencySymbol") private var currency = "£"
    @AppStorage("defaultSpecies") private var defaultSpeciesRaw = Species.emu.rawValue
    @AppStorage("defaultDiet") private var defaultDietRaw = DietType.mixed.rawValue
    @AppStorage("defaultTabIndex") private var defaultTabIndex = 0
    @AppStorage("notificationsOn") private var notificationsOn = false

    @State private var toast: String? = nil
    @State private var shareURL: URL? = nil
    @State private var showShare = false
    @State private var showDeleteAccount = false
    @State private var deletingAccount = false

    private let currencies = ["£", "$", "€", "₽", "kr"]

    /// Удаление аккаунта на сервере и полный сброс локального состояния.
    /// Приложение остаётся рабочим — поднимается чистая анонимная сессия.
    private func deleteAccount() async {
        deletingAccount = true
        defer { deletingAccount = false }

        do {
            try await AuthManager.shared.deleteAccount()
            notifier.cancelEverything()
            await store.resetAfterAccountDeletion()
            toast = "Account deleted — starting fresh"
        } catch let error as APIError {
            toast = error.userMessage
        } catch {
            toast = "Could not delete the account — check your connection"
        }
    }

    /// Человекочитаемое состояние резервной копии для карточки «Backup & Data».
    private var backupStatus: String {
        switch store.syncState {
        case .offline:
            return "offline, changes saved on device"
        case .failed:
            return "sync problem — tap Sync Now"
        case .loading, .syncing:
            return "syncing…"
        case .idle:
            guard let syncedAt = store.lastSyncedAt else { return "not backed up yet" }

            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = Calendar.current.isDateInToday(syncedAt) ? .none : .short

            return "backed up \(formatter.string(from: syncedAt))"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Theme
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Appearance", systemImage: "paintbrush.fill")
                        HStack(spacing: 8) {
                            ForEach(AppThemeMode.allCases) { m in
                                Chip(title: m.label, selected: theme.mode == m) {
                                    withAnimation { theme.mode = m }
                                }
                            }
                        }
                        Text("Changes apply to the whole app instantly.")
                            .font(AppFont.caption).foregroundColor(Palette.textSecondary)
                    }
                }

                // Units & currency
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Units & Currency", systemImage: "ruler.fill")
                        HStack(spacing: 8) {
                            ForEach(UnitSystem.allCases) { u in
                                Chip(title: u == .metric ? "Metric" : "Imperial", selected: unitRaw == u.rawValue) {
                                    unitRaw = u.rawValue; toast = "Units set"
                                }
                            }
                        }
                        Divider().background(Palette.divider)
                        Text("Currency").font(AppFont.caption).foregroundColor(Palette.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(currencies, id: \.self) { c in
                                Chip(title: c, selected: currency == c, accent: Palette.savanna) { currency = c }
                            }
                        }
                    }
                }

                // Defaults
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Defaults", systemImage: "slider.horizontal.3")
                        Text("Default species").font(AppFont.caption).foregroundColor(Palette.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(Species.allCases) { s in
                                Chip(title: s.label, selected: defaultSpeciesRaw == s.rawValue, accent: Palette.primary) {
                                    defaultSpeciesRaw = s.rawValue
                                }
                            }
                        }
                        Text("Default diet").font(AppFont.caption).foregroundColor(Palette.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(DietType.allCases) { d in
                                Chip(title: d.label, selected: defaultDietRaw == d.rawValue, accent: Palette.savanna) {
                                    defaultDietRaw = d.rawValue
                                }
                            }
                        }
                        Text("Startup tab").font(AppFont.caption).foregroundColor(Palette.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(0..<5, id: \.self) { i in
                                Chip(title: ["Birds","Housing","Feed","Handling","Reports"][i],
                                     selected: defaultTabIndex == i, accent: Palette.action) {
                                    defaultTabIndex = i
                                }
                            }
                        }
                    }
                }

                // Notifications
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Notifications", systemImage: "bell.fill")
                        Toggle(isOn: Binding(
                            get: { notificationsOn },
                            set: { on in
                                notificationsOn = on
                                if on {
                                    notifier.requestAuthorization { granted in
                                        notificationsOn = granted
                                        toast = granted ? "Notifications on" : "Enable in iOS Settings"
                                    }
                                } else {
                                    notifier.cancelEverything()
                                    toast = "All reminders cancelled"
                                }
                            })) {
                            Label("Enable reminders", systemImage: "bell.badge.fill")
                                .font(AppFont.body).foregroundColor(Palette.textPrimary)
                        }.toggleStyle(SwitchToggleStyle(tint: Palette.primary))

                        GhostButton(title: "Send a test notification", systemImage: "paperplane.fill") {
                            notifier.requestAuthorization { granted in
                                if granted { notifier.fireTest(); toast = "Test sent — arrives in ~3s" }
                                else { toast = "Enable notifications first" }
                            }
                        }
                    }
                }

                // Data
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Backup & Data", systemImage: "externaldrive.fill")
                        Text("\(store.flocks.count) flock(s) · \(backupStatus)")
                            .font(AppFont.caption).foregroundColor(Palette.textSecondary)
                        GhostButton(title: "Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                            Task {
                                await store.flushPendingChanges()
                                await store.refresh()
                                toast = "Synced"
                            }
                        }
                        GhostButton(title: "Export Data (JSON)", systemImage: "square.and.arrow.up") {
                            if let url = ReportGenerator.exportJSON(store.flocks) {
                                shareURL = url; showShare = true
                            } else { toast = "Nothing to export" }
                        }
                        GhostButton(title: "Replay Onboarding", systemImage: "arrow.counterclockwise") {
                            hasCompletedOnboarding = false
                        }
                        GhostButton(title: "Delete All Flocks", systemImage: "trash", tint: Palette.danger) {
                            // deleteAllFlocks снимает и напоминания — иначе они
                            // продолжали бы приходить для удалённых стад
                            store.deleteAllFlocks()
                            notifier.cancelEverything()
                            toast = "All flocks deleted"
                        }

                        Divider().background(Palette.divider)

                        // Требование App Store 5.1.1(v): аккаунт должно быть
                        // возможно удалить изнутри приложения.
                        GhostButton(title: deletingAccount ? "Deleting…" : "Delete Account",
                                    systemImage: "person.crop.circle.badge.xmark",
                                    tint: Palette.danger) {
                            guard !deletingAccount else { return }
                            showDeleteAccount = true
                        }
                        Text("Removes your flocks, photos and reports from our servers for good. The app keeps working — it simply starts over.")
                            .font(AppFont.caption).foregroundColor(Palette.textDisabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Помощь и юридическое
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Help & Legal", systemImage: "lifepreserver.fill")

                        NavigationLink(destination: SupportView()) {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(Palette.action)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Contact Support")
                                        .font(AppFont.body).foregroundColor(Palette.textPrimary)
                                    Text("Report a problem or ask a question")
                                        .font(AppFont.caption).foregroundColor(Palette.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Palette.textDisabled)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().background(Palette.divider)

                        // Apple требует, чтобы политика была доступна из приложения.
                        GhostButton(title: "Privacy Policy & Terms", systemImage: "hand.raised.fill") {
                            WebLinks.open(.privacy)
                        }
                        Text("Opens ratiterun.online in your browser.")
                            .font(AppFont.caption).foregroundColor(Palette.textDisabled)
                    }
                }

                // About
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "About", systemImage: "info.circle.fill")
                        Text("Ratite Run").font(AppFont.rounded(16, .bold)).foregroundColor(Palette.textPrimary)
                        Text("Big birds, big space, safe handling. Your flocks are backed up automatically — still no sign-up, no password.")
                            .font(AppFont.caption).foregroundColor(Palette.textSecondary)
                        DisclaimerBanner(text: ratiteDisclaimer)
                    }
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Settings", displayMode: .inline)
        .sheet(isPresented: $showShare) { if let url = shareURL { ShareSheet(items: [url]) } }
        .alert("Delete your account?", isPresented: $showDeleteAccount) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("Your flocks, bird records, photos and reports will be removed from our servers permanently. This cannot be undone, and we cannot recover them for you.\n\nExport your data first if you want to keep a copy.")
        }
        .toast($toast)
    }
}

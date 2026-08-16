//
//  Tab5_Reports.swift
//  RatiteRun
//
//  Reports tab hub + Reminders & Signoff (17), Reports & Export (18).
//

import SwiftUI

// MARK: - Reports Tab

struct ReportsTab: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        HubScaffold(title: "Reports", subtitle: "Reminders, sign-off & export") {
            if store.flocks.isEmpty {
                NoFlockView().frame(minHeight: 460)
            } else {
                FlockPickerBar()
                if let f = store.selectedFlock {
                    ReadinessCard(flock: f)
                    ToolTile("Reports & Export", "Clean local report or PDF", systemImage: "doc.text.fill", accent: Palette.primary, hot: true) {
                        ReportsExportView(flockID: f.id)
                    }
                    ToolTile("Reminders & Signoff", "Nudges + sign off a period", systemImage: "bell.badge.fill", accent: Palette.action) {
                        RemindersSignoffView(flockID: f.id)
                    }
                    ToolTile("Settings", "Units, theme, notifications, backup", systemImage: "gearshape.fill", accent: Palette.savanna) {
                        SettingsView()
                    }
                }
            }
        }
    }
}

// MARK: - 17 Reminders & Signoff

struct RemindersSignoffView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var notifier: NotificationManager
    let flockID: UUID
    @State private var toast: String? = nil
    @State private var newKind: ReminderKind = .feedGrit
    @State private var newHour = 8
    @State private var newMinute = 0

    var body: some View {
        let flock = store.binding(for: flockID)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Set nudges and sign off the period.", icon: "bell.badge.fill")

                if !notifier.authorized {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Notifications are off").font(AppFont.rounded(15, .bold)).foregroundColor(Palette.textPrimary)
                            Text("Enable to get feed/grit, water, fence and leg-check reminders.")
                                .font(AppFont.caption).foregroundColor(Palette.textSecondary)
                            PrimaryButton(title: "Enable Notifications", systemImage: "bell.fill") {
                                notifier.requestAuthorization { granted in
                                    toast = granted ? "Notifications enabled" : "Enable them in Settings app"
                                }
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Add a reminder", systemImage: "plus.circle.fill")
                        FlowChips(ReminderKind.allCases) { k in
                            Chip(title: k.label, systemImage: k.symbol, selected: newKind == k, accent: Palette.action) { newKind = k }
                        }
                        HStack {
                            Text("Time").font(AppFont.caption).foregroundColor(Palette.textSecondary)
                            Spacer()
                            Picker("", selection: $newHour) {
                                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                            }.pickerStyle(WheelPickerStyle()).frame(width: 70, height: 90).clipped()
                            Text(":").foregroundColor(Palette.textSecondary)
                            Picker("", selection: $newMinute) {
                                ForEach([0,15,30,45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                            }.pickerStyle(WheelPickerStyle()).frame(width: 70, height: 90).clipped()
                        }
                        PrimaryButton(title: "Add Reminder", systemImage: "plus") {
                            let r = FlockReminder(title: newKind.label, kind: newKind, hour: newHour, minute: newMinute)
                            flock.wrappedValue.reminders.append(r)
                            notifier.schedule(r, for: flock.wrappedValue)
                            toast = "Reminder scheduled"
                        }
                    }
                }

                if !flock.wrappedValue.reminders.isEmpty {
                    SectionHeader(title: "Scheduled", systemImage: "bell.fill")
                    ForEach(flock.wrappedValue.reminders) { r in
                        ReminderRow(reminder: r, flockBinding: flock)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Sign off period", systemImage: "signature")
                        AppTextField(title: "Reviewer", text: flock.signoff.reviewer, placeholder: "Your name", systemImage: "person.fill")
                        Text("Signature").font(AppFont.caption).foregroundColor(Palette.textSecondary)
                        DrawingCanvas(strokes: flock.signoff.signatureStrokes, strokeColor: Palette.primaryActive)
                            .frame(height: 130)
                        HStack {
                            GhostButton(title: "Clear signature", systemImage: "trash", tint: Palette.danger) {
                                flock.wrappedValue.signoff.signatureStrokes.removeAll()
                            }
                        }
                        PrimaryButton(title: flock.wrappedValue.signoff.approved ? "Period Approved ✓" : "Approve Period",
                                      systemImage: "checkmark.seal.fill",
                                      fill: flock.wrappedValue.signoff.approved ? Palette.norm : Palette.primary) {
                            flock.wrappedValue.signoff.approved = true
                            flock.wrappedValue.signoff.date = Date()
                            store.update(flock.wrappedValue)
                            toast = "Period approved"
                        }
                    }
                }

                NavigationLink(destination: ReportsExportView(flockID: flockID)) {
                    HStack { Image(systemName: "doc.text.fill"); Text("Open Reports") }
                        .font(AppFont.rounded(15, .semibold)).foregroundColor(Palette.onSavanna)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.savanna))
                }.buttonStyle(PlainButtonStyle())
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Reminders & Signoff", displayMode: .inline)
        .onAppear { notifier.refreshStatus() }
        .toast($toast)
    }
}

private struct ReminderRow: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var notifier: NotificationManager
    let reminder: FlockReminder
    let flockBinding: Binding<Flock>

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Palette.action.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: reminder.kind.symbol).foregroundColor(Palette.action)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.kind.label).font(AppFont.rounded(15, .semibold)).foregroundColor(Palette.textPrimary)
                Text(String(format: "Daily at %02d:%02d", reminder.hour, reminder.minute))
                    .font(AppFont.caption).foregroundColor(Palette.textSecondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { reminder.enabled },
                set: { on in
                    if let idx = flockBinding.wrappedValue.reminders.firstIndex(where: { $0.id == reminder.id }) {
                        flockBinding.wrappedValue.reminders[idx].enabled = on
                        let r = flockBinding.wrappedValue.reminders[idx]
                        if on { notifier.schedule(r, for: flockBinding.wrappedValue) }
                        else { notifier.cancel(r, for: flockBinding.wrappedValue) }
                    }
                }))
                .labelsHidden().toggleStyle(SwitchToggleStyle(tint: Palette.primary))
            Button(action: {
                notifier.cancel(reminder, for: flockBinding.wrappedValue)
                flockBinding.wrappedValue.reminders.removeAll { $0.id == reminder.id }
            }) { Image(systemName: "trash").foregroundColor(Palette.danger) }
                .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
    }
}

// MARK: - 18 Reports & Export

struct ReportsExportView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("currencySymbol") private var currency = "£"
    let flockID: UUID

    @State private var sections: Set<ReportSection> = Set(ReportSection.allCases)
    @State private var notes = ""
    @State private var toast: String? = nil
    @State private var shareURL: URL? = nil
    @State private var showShare = false

    var body: some View {
        let flock = store.flocks.first(where: { $0.id == flockID }) ?? Flock()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Build a clean local report or PDF.", icon: "doc.text.fill")

                ReadinessCard(flock: flock)

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Include sections", systemImage: "checklist")
                        ForEach(ReportSection.allCases) { s in
                            Button(action: {
                                if sections.contains(s) { sections.remove(s) } else { sections.insert(s) }
                            }) {
                                HStack {
                                    Image(systemName: sections.contains(s) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(sections.contains(s) ? Palette.primary : Palette.textDisabled)
                                    Text(s.rawValue).font(AppFont.body).foregroundColor(Palette.textPrimary)
                                    Spacer()
                                }
                            }.buttonStyle(PlainButtonStyle())
                        }
                        Divider().background(Palette.divider)
                        AppTextField(title: "Notes", text: $notes, placeholder: "Report notes", systemImage: "note.text")
                    }
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: "Generate Report / Export PDF", systemImage: "square.and.arrow.up") {
                        if let url = ReportGenerator.makePDF(flock: flock, sections: sections, currency: currency, notes: notes) {
                            shareURL = url; showShare = true; toast = "PDF ready"
                        } else { toast = "Could not build PDF" }
                    }
                    SavannaButton(title: "Share Locally", systemImage: "square.and.arrow.up") {
                        if let url = ReportGenerator.makePDF(flock: flock, sections: sections, currency: currency, notes: notes) {
                            shareURL = url; showShare = true
                        }
                    }
                    NavigationLink(destination: BirdsTabWrapper()) {
                        HStack { Image(systemName: "chevron.left"); Text("Back to Birds") }
                            .font(AppFont.rounded(15, .semibold)).foregroundColor(Palette.primaryActive)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).stroke(Palette.primary.opacity(0.5), lineWidth: 1.4))
                    }.buttonStyle(PlainButtonStyle())
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Reports & Export", displayMode: .inline)
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ShareSheet(items: [url]) }
        }
        .toast($toast)
    }
}

// Simple wrapper so "Back to Birds" has a destination (list view).
struct BirdsTabWrapper: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let f = store.selectedFlock { ReadinessCard(flock: f) }
                ForEach(store.flocks) { f in
                    HStack {
                        Image(systemName: f.species.glyph).foregroundColor(Palette.primary)
                        Text(f.title).font(AppFont.body).foregroundColor(Palette.textPrimary)
                        Spacer()
                        Text("\(ReadinessEngine.evaluate(f).percent)%").font(AppFont.mono).foregroundColor(Palette.textSecondary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
                }
            }.padding(20)
        }
        .screenBackground()
        .navigationBarTitle("Flocks", displayMode: .inline)
    }
}

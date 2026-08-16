//
//  Tab3_Feed.swift
//  RatiteRun
//
//  Feed tab hub + Feeding & Diet (05), Water & Grit (06).
//

import SwiftUI

// MARK: - Feed Tab

struct FeedTab: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        HubScaffold(title: "Feed", subtitle: "Ratite diet, grit & water") {
            if store.flocks.isEmpty {
                NoFlockView().frame(minHeight: 460)
            } else {
                FlockPickerBar()
                if let f = store.selectedFlock {
                    FeedSummary(flock: f)
                    ToolTile("Feeding & Diet", "Feed a ratite-specific diet", systemImage: "leaf.fill", accent: Palette.savanna, hot: true) {
                        FeedingDietView(flockID: f.id)
                    }
                    ToolTile("Water & Grit", "Water, grit and minerals", systemImage: "drop.fill", accent: Palette.primary) {
                        WaterGritView(flockID: f.id)
                    }
                }
            }
        }
    }
}

private struct FeedSummary: View {
    let flock: Flock
    var body: some View {
        let diet = DietEngine.evaluate(flock)
        let grit = GritWaterEngine.evaluate(flock)
        return VStack(spacing: 12) {
            EngineResultCard(title: "Diet", result: diet)
            EngineResultCard(title: "Grit & Water", result: grit)
        }
    }
}

// MARK: - 05 Feeding & Diet

struct FeedingDietView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil

    var body: some View {
        let flock = store.binding(for: flockID)
        let p = Presets.preset(for: flock.wrappedValue.species)
        let result = DietEngine.evaluate(flock.wrappedValue)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Feed a ratite-specific diet — not chicken feed.", icon: "leaf.fill")

                EngineResultCard(title: "Diet verdict", result: result)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Ratite Diet", systemImage: "leaf.fill")
                        HStack(spacing: 8) {
                            ForEach(DietType.allCases) { d in
                                Chip(title: d.label, selected: flock.wrappedValue.feed.dietType == d, accent: Palette.savanna) {
                                    flock.wrappedValue.feed.dietType = d
                                }
                            }
                        }
                        HStack {
                            Text("Target protein for \(flock.wrappedValue.species.label)")
                                .font(AppFont.caption).foregroundColor(Palette.textSecondary)
                            Spacer()
                            Text(String(format: "≈ %.0f%%", p.targetProteinPct)).font(AppFont.mono).foregroundColor(Palette.primaryActive)
                        }
                        AppNumberField(title: "Protein", value: flock.feed.proteinPct, unit: "%", systemImage: "percent")
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Grazing ratio").font(AppFont.caption).foregroundColor(Palette.textSecondary)
                                Spacer()
                                Text("\(Int(flock.wrappedValue.feed.grazingRatio))%").font(AppFont.mono).foregroundColor(Palette.textPrimary)
                            }
                            Slider(value: flock.feed.grazingRatio, in: 0...100, step: 5).accentColor(Palette.savanna)
                        }
                        AppTextField(title: "Schedule", text: flock.feed.scheduleNote, placeholder: "e.g. Morning + evening", systemImage: "clock.fill")
                    }
                }

                ScreenActions(saveTitle: "Set Feed", nextTitle: "Open Water & Grit",
                              onSave: { store.update(flock.wrappedValue); toast = "Feed saved" },
                              onClear: { flock.wrappedValue.feed = Feed(); toast = "Cleared" }) {
                    WaterGritView(flockID: flockID)
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Feeding & Diet", displayMode: .inline)
        .toast($toast)
    }
}

// MARK: - 06 Water & Grit

struct WaterGritView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil

    var body: some View {
        let flock = store.binding(for: flockID)
        let result = GritWaterEngine.evaluate(flock.wrappedValue)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Provide water, grit and minerals — stones grind coarse feed in the gizzard.", icon: "drop.fill")

                EngineResultCard(title: "Digestion support", result: result)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        FieldRowToggle(title: "Clean water available", systemImage: "drop.fill", isOn: flock.waterGrit.waterProvided, tint: Color(hex: "#4DA3F0"))
                        FieldRowToggle(title: "Grit / stones provided", systemImage: "circle.grid.cross.fill", isOn: flock.waterGrit.gritProvided, tint: Palette.primary)
                        AppNumberField(title: "Grit per bird", value: flock.waterGrit.gritGramsPerBird, unit: "g", systemImage: "scalemass.fill")
                        FieldRowToggle(title: "Minerals supplied", systemImage: "pills.fill", isOn: flock.waterGrit.mineralsProvided, tint: Palette.action)
                        AppTextField(title: "Notes", text: flock.waterGrit.notes, placeholder: "Source, type of grit…", systemImage: "note.text")
                    }
                }

                ScreenActions(saveTitle: "Set Water/Grit", nextTitle: "Open Handling Safety",
                              onSave: { store.update(flock.wrappedValue); toast = "Saved" },
                              onClear: { flock.wrappedValue.waterGrit = WaterGrit(); toast = "Cleared" }) {
                    HandlingSafetyView(flockID: flockID)
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Water & Grit", displayMode: .inline)
        .toast($toast)
    }
}

//
//  Tab4_Handling.swift
//  RatiteRun
//
//  Handling tab hub + Handling Safety (07), Breeding & Eggs (08),
//  Chick Rearing (09), Health & Legs (10).
//

import SwiftUI

// MARK: - Handling Tab

struct HandlingTab: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        HubScaffold(title: "Handling", subtitle: "Safety, breeding & health") {
            if store.flocks.isEmpty {
                NoFlockView().frame(minHeight: 460)
            } else {
                FlockPickerBar()
                if let f = store.selectedFlock {
                    let safety = HandlingSafetyEngine.evaluate(f)
                    Card {
                        HStack(spacing: 16) {
                            RingGauge(progress: Double(safety.score) / 100, size: 84,
                                      color: safety.result.verdict.color,
                                      centerText: "\(safety.score)", caption: "safety")
                            VStack(alignment: .leading, spacing: 6) {
                                Text(safety.result.headline).font(AppFont.rounded(16, .bold)).foregroundColor(Palette.textPrimary)
                                Text("Kick risk: \(Presets.preset(for: f.species).kickRiskLabel)")
                                    .font(AppFont.caption).foregroundColor(Palette.danger)
                            }
                            Spacer()
                        }
                    }
                    ToolTile("Handling Safety", "Handle safely — mind the kick", systemImage: "hand.raised.fill", accent: Palette.danger, hot: true) {
                        HandlingSafetyView(flockID: f.id)
                    }
                    ToolTile("Breeding & Eggs", "Breeding pairs and large eggs", systemImage: "oval.portrait.fill", accent: Palette.primary) {
                        BreedingEggsView(flockID: f.id)
                    }
                    ToolTile("Chick Rearing", "Rear ratite chicks with care", systemImage: "bird.fill", accent: Palette.action) {
                        ChickRearingView(flockID: f.id)
                    }
                    ToolTile("Health & Legs", "Watch legs, joints and health", systemImage: "cross.case.fill", accent: Palette.savanna) {
                        HealthLegsView(flockID: f.id)
                    }
                }
            }
        }
    }
}

// MARK: - 07 Handling Safety

struct HandlingSafetyView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil

    var body: some View {
        let flock = store.binding(for: flockID)
        let eval = HandlingSafetyEngine.evaluate(flock.wrappedValue)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Handle safely — mind the kick. The forward kick is the danger.", icon: "hand.raised.fill")

                Card {
                    HStack(spacing: 16) {
                        RingGauge(progress: Double(eval.score) / 100, size: 96, color: eval.result.verdict.color,
                                  centerText: "\(eval.score)", caption: "/100")
                        VStack(alignment: .leading, spacing: 6) {
                            VerdictBadge(text: eval.result.headline, color: eval.result.verdict.color, systemImage: eval.result.verdict.symbol)
                            Text(eval.result.detail).font(AppFont.caption).foregroundColor(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Protocols", systemImage: "checklist")
                        FieldRowToggle(title: "Never corner the bird", systemImage: "exclamationmark.shield.fill", isOn: flock.handling.neverCorner, tint: Palette.danger)
                        FieldRowToggle(title: "Approach from the side", systemImage: "arrow.right.to.line", isOn: flock.handling.approachFromSide, tint: Palette.primary)
                        FieldRowToggle(title: "Use a hood to calm", systemImage: "eye.slash.fill", isOn: flock.handling.useHood, tint: Palette.savanna)
                        FieldRowToggle(title: "Trained handlers only", systemImage: "person.2.fill", isOn: flock.handling.trainedHandlersOnly, tint: Palette.action)
                        AppTextField(title: "Restraint plan", text: flock.handling.restraintPlan, placeholder: "Who, how, escape route…", systemImage: "figure.stand")
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Key safety rules", systemImage: "list.bullet")
                        ForEach(0..<eval.rules.count, id: \.self) { i in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(Palette.norm).font(.system(size: 13))
                                Text(eval.rules[i]).font(AppFont.caption).foregroundColor(Palette.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                DisclaimerBanner(text: ratiteDisclaimer)

                ScreenActions(saveTitle: "Set Safety", nextTitle: "Open Breeding & Eggs",
                              onSave: { store.update(flock.wrappedValue); toast = "Safety saved" },
                              onClear: { flock.wrappedValue.handling = HandlingSafety(); toast = "Cleared" }) {
                    BreedingEggsView(flockID: flockID)
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Handling Safety", displayMode: .inline)
        .toast($toast)
    }
}

// MARK: - 08 Breeding & Eggs

struct BreedingEggsView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil

    var body: some View {
        let flock = store.binding(for: flockID)
        let eval = BreedingEngine.evaluate(flock.wrappedValue)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Track breeding pairs and large eggs.", icon: "oval.portrait.fill")

                EngineResultCard(title: "Breeding", result: eval.result)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        AppStepper(title: "Breeding pairs", value: flock.breeding.pairs, range: 0...100)
                        AppStepper(title: "Large eggs collected", value: flock.breeding.largeEggs, range: 0...500)
                        HStack {
                            Text("Set date").font(AppFont.caption).foregroundColor(Palette.textSecondary)
                            Spacer()
                            DatePicker("", selection: flock.breeding.startDate, displayedComponents: .date)
                                .labelsHidden().accentColor(Palette.primary)
                        }
                        AppTextField(title: "Season", text: flock.breeding.season, placeholder: "Spring / Summer", systemImage: "sun.max.fill")
                        AppTextField(title: "Incubation note", text: flock.breeding.incubationNote, placeholder: "Temp, turning…", systemImage: "thermometer")
                    }
                }

                Card {
                    HStack(spacing: 10) {
                        StatPill(value: mediumDate(eval.hatchDate), label: "expected hatch", color: Palette.primary, systemImage: "calendar")
                        StatPill(value: eval.window, label: "window", color: Palette.action, systemImage: "timer")
                    }
                }

                ScreenActions(saveTitle: "Set Breeding", nextTitle: "Open Chick Rearing",
                              onSave: { store.update(flock.wrappedValue); toast = "Breeding saved" },
                              onClear: { flock.wrappedValue.breeding = Breeding(); toast = "Cleared" }) {
                    ChickRearingView(flockID: flockID)
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Breeding & Eggs", displayMode: .inline)
        .toast($toast)
    }
}

// MARK: - 09 Chick Rearing

struct ChickRearingView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil

    var body: some View {
        let flock = store.binding(for: flockID)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Rear ratite chicks with care — catch leg problems early.", icon: "bird.fill")

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        AppStepper(title: "Chicks", value: flock.rearing.chicks, range: 0...500)
                        FieldRowToggle(title: "Brooder ready", systemImage: "flame.fill", isOn: flock.rearing.brooderReady, tint: Palette.action)
                        FieldRowToggle(title: "Leg issues flagged", systemImage: "exclamationmark.triangle.fill", isOn: flock.rearing.legIssuesFlagged, tint: Palette.danger)
                        AppTextField(title: "Chick diet", text: flock.rearing.chickDietNote, placeholder: "High-protein starter…", systemImage: "leaf.fill")
                    }
                }

                if flock.wrappedValue.rearing.legIssuesFlagged {
                    DisclaimerBanner(text: "Leg/joint problems flagged — firm footing, balanced protein, and a specialist vet if it persists.")
                }

                ScreenActions(saveTitle: "Set Rearing", nextTitle: "Open Health & Legs",
                              onSave: { store.update(flock.wrappedValue); toast = "Rearing saved" },
                              onClear: { flock.wrappedValue.rearing = ChickRearing(); toast = "Cleared" }) {
                    HealthLegsView(flockID: flockID)
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Chick Rearing", displayMode: .inline)
        .toast($toast)
    }
}

// MARK: - 10 Health & Legs

struct HealthLegsView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil

    var body: some View {
        let flock = store.binding(for: flockID)
        let result = HealthLegsEngine.evaluate(flock.wrappedValue)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Watch legs, joints and health.", icon: "cross.case.fill")

                EngineResultCard(title: "Health verdict", result: result)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Leg / joint score", systemImage: "figure.walk")
                        ScoreDots(score: flock.health.legJointScore)
                        AppTextField(title: "Common ailments", text: flock.health.ailmentsNote, placeholder: "Anything observed", systemImage: "stethoscope")
                        AppTextField(title: "Vet contact", text: flock.health.vetContact, placeholder: "Specialist vet", systemImage: "phone.fill")
                        HStack {
                            Text("Last check").font(AppFont.caption).foregroundColor(Palette.textSecondary)
                            Spacer()
                            DatePicker("", selection: flock.health.lastCheck, displayedComponents: .date)
                                .labelsHidden().accentColor(Palette.primary)
                        }
                    }
                }

                DisclaimerBanner(text: "Estimates only — consult a specialist ratite vet for any health concern.")

                ScreenActions(saveTitle: "Save Health", nextTitle: "Open Predator & Fence Check",
                              onSave: { flock.wrappedValue.health.lastCheck = Date(); store.update(flock.wrappedValue); toast = "Health saved" },
                              onClear: { flock.wrappedValue.health = HealthLegs(); toast = "Cleared" }) {
                    PredatorFenceCheckView(flockID: flockID)
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Health & Legs", displayMode: .inline)
        .toast($toast)
    }
}

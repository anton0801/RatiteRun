//
//  Tab2_Housing.swift
//  RatiteRun
//
//  Housing tab hub + Housing & Space (03), Fencing (04),
//  Predator & Fence Check (11), Terrain & Range (12),
//  Material List (14), Layout Board (16).
//

import SwiftUI

// MARK: - Housing Tab

struct HousingTab: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        HubScaffold(title: "Housing", subtitle: "Space, fence, terrain") {
            if store.flocks.isEmpty {
                NoFlockView().frame(minHeight: 460)
            } else {
                FlockPickerBar()
                if let f = store.selectedFlock {
                    HousingSummary(flock: f)
                    ToolTile("Housing & Space", "Large space and shelter", systemImage: "house.fill", accent: Palette.primary, hot: true) {
                        HousingSpaceView(flockID: f.id)
                    }
                    ToolTile("Fencing", "Tall, strong fencing by species", systemImage: "shield.fill", accent: Palette.action, hot: true) {
                        FencingView(flockID: f.id)
                    }
                    ToolTile("Predator & Fence Check", "Perimeter integrity & predators", systemImage: "eye.fill", accent: Palette.danger) {
                        PredatorFenceCheckView(flockID: f.id)
                    }
                    ToolTile("Terrain & Range", "Terrain, dust baths, room to run", systemImage: "mountain.2.fill", accent: Palette.savanna) {
                        TerrainRangeView(flockID: f.id)
                    }
                    ToolTile("Material List", "Full ratite kit list", systemImage: "shippingbox.fill", accent: Palette.primaryActive) {
                        MaterialListView(flockID: f.id)
                    }
                    ToolTile("Layout Board", "Plan paddock & housing", systemImage: "square.grid.3x3.fill", accent: Palette.savanna) {
                        LayoutBoardView(flockID: f.id)
                    }
                }
            }
        }
    }
}

private struct HousingSummary: View {
    let flock: Flock
    var body: some View {
        let space = SpaceEngine.evaluate(flock)
        let fence = FencingEngine.evaluate(flock)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Space & fence at a glance", systemImage: "ruler.fill")
                HStack(spacing: 10) {
                    StatPill(value: "\(Int(space.perBird))", label: "m²/bird", color: space.result.verdict.color, systemImage: "arrow.up.left.and.arrow.down.right")
                    StatPill(value: String(format: "%.1f", flock.fencing.height), label: "fence m", color: fence.verdict.color, systemImage: "shield.fill")
                    StatPill(value: "\(Int(flock.housing.paddockSize))", label: "paddock m²", color: Palette.savanna, systemImage: "square.dashed")
                }
            }
        }
    }
}

// MARK: - 03 Housing & Space

struct HousingSpaceView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil

    var body: some View {
        let flock = store.binding(for: flockID)
        let result = SpaceEngine.evaluate(flock.wrappedValue)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Give large space and shelter. Ratites run — space matters.", icon: "house.fill")

                EngineResultCard(title: "Space verdict", result: result.result)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        AppNumberField(title: "Space per Bird (recommended)", value: flock.housing.spacePerBird, unit: "m²", systemImage: "arrow.up.left.and.arrow.down.right")
                        AppNumberField(title: "Paddock Size", value: flock.housing.paddockSize, unit: "m²", systemImage: "square.dashed")
                        AppNumberField(title: "Shelter Area", value: flock.housing.shelterArea, unit: "m²", systemImage: "house.fill")
                        FieldRowToggle(title: "Shelter provided", systemImage: "house.circle.fill", isOn: flock.housing.hasShelter)
                        Divider().background(Palette.divider)
                        SectionHeader(title: "Terrain", systemImage: "mountain.2.fill")
                        FlowChips(TerrainType.allCases) { t in
                            Chip(title: t.label, selected: flock.wrappedValue.housing.terrain == t, accent: Palette.savanna) {
                                flock.wrappedValue.housing.terrain = t
                            }
                        }
                    }
                }

                ScreenActions(saveTitle: "Set Housing", nextTitle: "Open Fencing",
                              onSave: { save(flock, "Housing saved") },
                              onClear: { flock.wrappedValue.housing = Housing(); toast = "Cleared" }) {
                    FencingView(flockID: flockID)
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Housing & Space", displayMode: .inline)
        .toast($toast)
    }

    private func save(_ flock: Binding<Flock>, _ msg: String) {
        var f = flock.wrappedValue; f.kit = MaterialEngine.compute(f); store.update(f); toast = msg
    }
}

// MARK: - 04 Fencing

struct FencingView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil

    var body: some View {
        let flock = store.binding(for: flockID)
        let p = Presets.preset(for: flock.wrappedValue.species)
        let result = FencingEngine.evaluate(flock.wrappedValue)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Set tall, strong fencing so birds don't escape or injure themselves.", icon: "shield.fill")

                EngineResultCard(title: "Fence verdict", result: result)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Recommended for \(flock.wrappedValue.species.label)")
                                .font(AppFont.caption).foregroundColor(Palette.textSecondary)
                            Spacer()
                            Text(String(format: "≥ %.1f m", p.recFenceHeightM)).font(AppFont.mono).foregroundColor(Palette.primaryActive)
                        }
                        AppNumberField(title: "Fence Height", value: flock.fencing.height, unit: "m", systemImage: "arrow.up.and.down")
                        SectionHeader(title: "Strength", systemImage: "bolt.shield.fill")
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { i in
                                Button(action: { flock.wrappedValue.fencing.strength = i }) {
                                    Image(systemName: i <= flock.wrappedValue.fencing.strength ? "square.fill" : "square")
                                        .font(.system(size: 22))
                                        .foregroundColor(i <= flock.wrappedValue.fencing.strength ? Palette.primary : Palette.border)
                                }.buttonStyle(PlainButtonStyle())
                            }
                            Spacer()
                            Text("\(flock.wrappedValue.fencing.strength)/5").font(AppFont.mono).foregroundColor(Palette.textSecondary)
                        }
                        FieldRowToggle(title: "Perimeter secured", systemImage: "lock.shield.fill", isOn: flock.fencing.perimeterSecured)
                        AppTextField(title: "Escape Risk note", text: flock.fencing.escapeRiskNote, placeholder: "Weak points, gates…", systemImage: "exclamationmark.triangle")
                    }
                }

                ScreenActions(saveTitle: "Set Fencing", nextTitle: "Open Feeding & Diet",
                              onSave: { toast = "Fencing saved"; store.update(flock.wrappedValue) },
                              onClear: { flock.wrappedValue.fencing = Fencing(); toast = "Cleared" }) {
                    FeedingDietView(flockID: flockID)
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Fencing", displayMode: .inline)
        .toast($toast)
    }
}

// MARK: - 11 Predator & Fence Check

struct PredatorFenceCheckView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil

    var body: some View {
        let flock = store.binding(for: flockID)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Check fence integrity and predators.", icon: "eye.fill")

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Fence Integrity", systemImage: "shield.lefthalf.filled")
                        ScoreDots(score: flock.predator.fenceIntegrity)
                        AppTextField(title: "Predators seen", text: flock.predator.predatorsSeen, placeholder: "Fox, dog, raptor…", systemImage: "pawprint.fill")
                        AppTextField(title: "Security note / Action", text: flock.predator.securityNote, placeholder: "Lighting, gates, repairs", systemImage: "lock.fill")
                        HStack {
                            Text("Last checked").font(AppFont.caption).foregroundColor(Palette.textSecondary)
                            Spacer()
                            DatePicker("", selection: flock.predator.lastChecked, displayedComponents: .date)
                                .labelsHidden().accentColor(Palette.primary)
                        }
                    }
                }

                let verdict: Verdict = flock.wrappedValue.predator.fenceIntegrity >= 4 ? .good : (flock.wrappedValue.predator.fenceIntegrity >= 3 ? .watch : .alert)
                Card {
                    HStack {
                        VerdictBadge(text: verdict == .good ? "Perimeter secure" : (verdict == .watch ? "Check weak points" : "Repair needed"),
                                     color: verdict.color, systemImage: verdict.symbol)
                        Spacer()
                    }
                }

                ScreenActions(saveTitle: "Set Check", nextTitle: "Open Terrain & Range",
                              onSave: { flock.wrappedValue.predator.lastChecked = Date(); store.update(flock.wrappedValue); toast = "Check saved" },
                              onClear: { flock.wrappedValue.predator = PredatorCheck(); toast = "Cleared" }) {
                    TerrainRangeView(flockID: flockID)
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Predator & Fence Check", displayMode: .inline)
        .toast($toast)
    }
}

struct ScoreDots: View {
    @Binding var score: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { i in
                Button(action: { score = i }) {
                    Circle().fill(i <= score ? Palette.primary : Palette.border)
                        .frame(width: 26, height: 26)
                        .overlay(Text("\(i)").font(AppFont.rounded(11, .bold)).foregroundColor(i <= score ? Palette.onPrimary : Palette.textDisabled))
                }.buttonStyle(PlainButtonStyle())
            }
            Spacer()
        }
    }
}

// MARK: - 12 Terrain & Range

struct TerrainRangeView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil

    var body: some View {
        let flock = store.binding(for: flockID)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Provide terrain and room to run.", icon: "mountain.2.fill")
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Range terrain", systemImage: "map.fill")
                        FlowChips(TerrainType.allCases) { t in
                            Chip(title: t.label, selected: flock.wrappedValue.housing.terrain == t, accent: Palette.savanna) {
                                flock.wrappedValue.housing.terrain = t
                            }
                        }
                        FieldRowToggle(title: "Dust bathing area", systemImage: "circle.grid.cross.fill", isOn: flock.terrain.dustBathing, tint: Palette.attention)
                        FieldRowToggle(title: "Room to run", systemImage: "figure.run", isOn: flock.terrain.roomToRun, tint: Palette.savanna)
                        AppTextField(title: "Notes", text: flock.terrain.terrainNote, placeholder: "Slopes, wet spots, shade…", systemImage: "note.text")
                    }
                }
                ScreenActions(saveTitle: "Set Terrain", nextTitle: "Open Records & ID",
                              onSave: { store.update(flock.wrappedValue); toast = "Terrain saved" },
                              onClear: { flock.wrappedValue.terrain = Terrain(); toast = "Cleared" }) {
                    RecordsIDView(flockID: flockID)
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Terrain & Range", displayMode: .inline)
        .toast($toast)
    }
}

// MARK: - 14 Material List

struct MaterialListView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil

    var body: some View {
        let flock = store.binding(for: flockID)
        let kit = MaterialEngine.compute(flock.wrappedValue)
        let cost = CostEngine.estimate(kit)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Full ratite kit list, sized from your flock.", icon: "shippingbox.fill")

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Fencing & Shelter", systemImage: "shield.fill")
                        KitRow(label: "Fence run", value: String(format: "%.0f m", kit.fenceMeters))
                        KitRow(label: "Shelter", value: String(format: "%.0f m²", kit.shelterM2))
                        Divider().background(Palette.divider)
                        SectionHeader(title: "Feeders & Water", systemImage: "tray.fill")
                        KitRow(label: "Feeders", value: "\(kit.feeders)")
                        KitRow(label: "Waterers", value: "\(kit.waterers)")
                        Divider().background(Palette.divider)
                        SectionHeader(title: "Grit & Minerals", systemImage: "circle.grid.cross.fill")
                        KitRow(label: "Grit / stones", value: String(format: "%.1f kg", kit.gritKg))
                        Divider().background(Palette.divider)
                        SectionHeader(title: "Safety Kit", systemImage: "cross.case.fill")
                        Text(kit.safetyKitNote).font(AppFont.body).foregroundColor(Palette.textPrimary)
                    }
                }

                Card {
                    HStack {
                        Text("Estimated total").font(AppFont.rounded(15, .semibold)).foregroundColor(Palette.textSecondary)
                        Spacer()
                        Text(String(format: "≈ %.0f", cost.total)).font(AppFont.rounded(20, .bold)).foregroundColor(Palette.norm)
                    }
                }

                ScreenActions(saveTitle: "Build List", nextTitle: "Open Flock Detail",
                              onSave: { flock.wrappedValue.kit = kit; store.update(flock.wrappedValue); toast = "List built" },
                              onClear: { toast = "Recomputed" }) {
                    FlockDetailView(flockID: flockID)
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Material List", displayMode: .inline)
        .toast($toast)
    }
}

struct KitRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(AppFont.body).foregroundColor(Palette.textPrimary)
            Spacer()
            Text(value).font(AppFont.mono).foregroundColor(Palette.primaryActive)
        }
    }
}

// MARK: - 16 Layout Board

struct LayoutBoardView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil
    @State private var snap = true
    @State private var selectedKind: LayoutKind = .feeder

    var body: some View {
        let flock = store.binding(for: flockID)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("See the paddock and housing in one plan. Tap to place, drag to move.", icon: "square.grid.3x3.fill")

                Card(padding: 10) {
                    VStack(spacing: 10) {
                        GeometryReader { geo in
                            ZStack {
                                // placement layer (background) — captures taps on empty area
                                RoundedRectangle(cornerRadius: 12).fill(Palette.savanna.opacity(0.10))
                                    .contentShape(Rectangle())
                                    .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                                        place(flock, at: v.location, in: geo.size)
                                    })
                                // grid
                                Path { p in
                                    let step: CGFloat = geo.size.width / 6
                                    for i in 1..<6 {
                                        p.move(to: CGPoint(x: step*CGFloat(i), y: 0)); p.addLine(to: CGPoint(x: step*CGFloat(i), y: geo.size.height))
                                        p.move(to: CGPoint(x: 0, y: step*CGFloat(i))); p.addLine(to: CGPoint(x: geo.size.width, y: step*CGFloat(i)))
                                    }
                                }.stroke(Palette.border, lineWidth: 0.6).allowsHitTesting(false)

                                ForEach(flock.wrappedValue.layout) { item in
                                    LayoutChip(item: item)
                                        .position(x: CGFloat(item.x) * geo.size.width,
                                                  y: CGFloat(item.y) * geo.size.height)
                                        .highPriorityGesture(DragGesture().onChanged { v in
                                            move(flock, item, to: v.location, in: geo.size)
                                        })
                                }
                            }
                        }
                        .frame(height: 300)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Item to place", systemImage: "hand.tap.fill")
                        FlowChips(LayoutKind.allCases) { k in
                            Chip(title: k.label, systemImage: k.symbol, selected: selectedKind == k, accent: k.color) {
                                selectedKind = k
                            }
                        }
                        FieldRowToggle(title: "Snap to grid", systemImage: "grid", isOn: $snap)
                        HStack {
                            GhostButton(title: "Remove last", systemImage: "arrow.uturn.backward") {
                                if !flock.wrappedValue.layout.isEmpty { flock.wrappedValue.layout.removeLast() }
                            }
                            GhostButton(title: "Clear board", systemImage: "trash", tint: Palette.danger) {
                                flock.wrappedValue.layout.removeAll()
                            }
                        }
                    }
                }

                ScreenActions(saveTitle: "Keep Layout", nextTitle: "Open Reminders",
                              onSave: { store.update(flock.wrappedValue); toast = "Layout saved" },
                              onClear: { flock.wrappedValue.layout.removeAll(); toast = "Cleared" }) {
                    RemindersSignoffView(flockID: flockID)
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Layout Board", displayMode: .inline)
        .toast($toast)
    }

    private func place(_ flock: Binding<Flock>, at loc: CGPoint, in size: CGSize) {
        var nx = loc.x / size.width
        var ny = loc.y / size.height
        if snap { nx = (nx * 6).rounded() / 6; ny = (ny * 6).rounded() / 6 }
        nx = min(1, max(0, nx)); ny = min(1, max(0, ny))
        flock.wrappedValue.layout.append(LayoutItem(kind: selectedKind, x: Double(nx), y: Double(ny)))
        let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
    }
    private func move(_ flock: Binding<Flock>, _ item: LayoutItem, to loc: CGPoint, in size: CGSize) {
        guard let idx = flock.wrappedValue.layout.firstIndex(where: { $0.id == item.id }) else { return }
        var nx = loc.x / size.width, ny = loc.y / size.height
        if snap { nx = (nx * 6).rounded() / 6; ny = (ny * 6).rounded() / 6 }
        flock.wrappedValue.layout[idx].x = Double(min(1, max(0, nx)))
        flock.wrappedValue.layout[idx].y = Double(min(1, max(0, ny)))
    }
}

struct LayoutChip: View {
    let item: LayoutItem
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(item.kind.color).frame(width: 34, height: 34)
                Image(systemName: item.kind.symbol).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            }
            Text(item.kind.label).font(AppFont.rounded(8, .semibold)).foregroundColor(Palette.textSecondary)
        }
        .shadow(color: Palette.shadow, radius: 3, y: 1)
    }
}

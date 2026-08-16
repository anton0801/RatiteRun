//
//  Tab1_Birds.swift
//  RatiteRun
//
//  Birds tab hub + Flock Setup (01), Bird Photo Markup (02),
//  Records & ID (13), Flock Detail (15).
//

import SwiftUI

// MARK: - Birds Tab

struct BirdsTab: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        HubScaffold(title: "Birds", subtitle: "Your ratite flocks") {
            if store.flocks.isEmpty {
                NoFlockView()
                    .frame(minHeight: 460)
            } else {
                FlockPickerBar()
                if let f = store.selectedFlock {
                    ReadinessCard(flock: f)
                    SectionHeader(title: "Flock tools", systemImage: "square.grid.2x2.fill")
                    ToolTile("Flock Setup", "Species, count, age & notes", systemImage: "square.and.pencil", accent: Palette.primary) {
                        FlockSetupView(flockID: f.id)
                    }
                    ToolTile("Bird Photo Markup", "Photo the birds and mark condition", systemImage: "camera.viewfinder", accent: Palette.action) {
                        BirdPhotoMarkupView(flockID: f.id)
                    }
                    ToolTile("Records & ID", "Bird IDs, weights and growth", systemImage: "list.bullet.rectangle", accent: Palette.savanna) {
                        RecordsIDView(flockID: f.id)
                    }
                    ToolTile("Flock Detail", "Everything about this flock in one card", systemImage: "person.crop.rectangle.stack", accent: Palette.primaryActive, hot: true) {
                        FlockDetailView(flockID: f.id)
                    }
                }
                SectionHeader(title: "All flocks", systemImage: "tray.full.fill")
                ForEach(store.flocks) { f in
                    FlockRow(flock: f)
                }
            }
        }
    }
}

private struct FlockRow: View {
    @EnvironmentObject var store: AppStore
    let flock: Flock
    var body: some View {
        let r = ReadinessEngine.evaluate(flock)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(flock.priority.color.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: flock.species.glyph).foregroundColor(flock.priority.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(flock.title).font(AppFont.rounded(16, .semibold)).foregroundColor(Palette.textPrimary)
                Text("\(flock.species.label) · \(flock.count) birds · \(r.percent)%")
                    .font(AppFont.caption).foregroundColor(Palette.textSecondary)
            }
            Spacer()
            Circle().fill(flock.status.color).frame(width: 10, height: 10)
            Menu {
                Button { store.selectedFlockID = flock.id } label: { Label("Select", systemImage: "checkmark.circle") }
                Button { store.duplicate(flock) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button { store.delete(flock) } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").foregroundColor(Palette.textSecondary).padding(8)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(store.selectedFlockID == flock.id ? Palette.primary.opacity(0.06) : Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(store.selectedFlockID == flock.id ? Palette.primary.opacity(0.4) : Palette.border, lineWidth: 1))
        .onTapGesture { store.selectedFlockID = flock.id }
    }
}

// MARK: - 01 Flock Setup

struct FlockSetupView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil

    var body: some View {
        let flock = store.binding(for: flockID)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Enter the species, count and age.", icon: "square.and.pencil")

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        AppTextField(title: "Flock", text: flock.title, placeholder: "Flock name", systemImage: "textformat")
                        SectionHeader(title: "Species", systemImage: "bird.fill")
                        HStack(spacing: 8) {
                            ForEach(Species.allCases) { s in
                                Chip(title: s.label, selected: flock.wrappedValue.species == s) {
                                    flock.wrappedValue.species = s
                                }
                            }
                        }
                        AppStepper(title: "Count", value: flock.count, range: 1...500)
                        AppTextField(title: "Age", text: flock.age, placeholder: "e.g. 18 months", systemImage: "calendar")
                        AppTextField(title: "Notes", text: flock.notes, placeholder: "Anything worth noting", systemImage: "note.text")
                    }
                }

                SpeciesRefCard(species: flock.wrappedValue.species)

                ScreenActions(saveTitle: "Lock Flock", nextTitle: "Open Housing & Space",
                              onSave: { save(flock) }, onClear: { clear(flock) }) {
                    HousingSpaceView(flockID: flockID)
                }
                Button(action: { save(flock) }) {
                    Text("Keep Setup").font(AppFont.rounded(14, .semibold)).foregroundColor(Palette.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Flock Setup", displayMode: .inline)
        .toast($toast)
    }

    private func save(_ flock: Binding<Flock>) {
        var f = flock.wrappedValue
        f.kit = MaterialEngine.compute(f)
        if f.status == .setup { f.status = .active }
        store.update(f)
        toast = "Flock saved"
    }
    private func clear(_ flock: Binding<Flock>) {
        flock.wrappedValue.notes = ""
        flock.wrappedValue.age = "Adult"
        toast = "Fields cleared"
    }
}

struct IntroText: View {
    let text: String
    var icon: String = "info.circle.fill"
    init(_ text: String, icon: String = "info.circle.fill") { self.text = text; self.icon = icon }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(Palette.primary)
            Text(text).font(AppFont.rounded(15, .medium)).foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

struct SpeciesRefCard: View {
    let species: Species
    var body: some View {
        let p = Presets.preset(for: species)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "\(species.label) reference", systemImage: "info.circle.fill")
                HStack(spacing: 10) {
                    StatPill(value: "\(Int(p.spacePerBirdM2))", label: "m²/bird", color: Palette.savanna, systemImage: "arrow.up.left.and.arrow.down.right")
                    StatPill(value: String(format: "%.1f", p.recFenceHeightM), label: "fence m", color: Palette.primary, systemImage: "shield.fill")
                    StatPill(value: "\(p.incubationDays)", label: "incub. days", color: Palette.action, systemImage: "timer")
                    StatPill(value: p.kickRiskLabel, label: "kick risk", color: Palette.danger, systemImage: "exclamationmark.triangle.fill")
                }
            }
        }
    }
}

// MARK: - 02 Bird Photo Markup

struct BirdPhotoMarkupView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil
    @State private var showPicker = false

    var body: some View {
        let flock = store.binding(for: flockID)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Photo the birds and mark condition.", icon: "camera.viewfinder")

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        if let data = flock.wrappedValue.photo, let ui = UIImage(data: data) {
                            Image(uiImage: ui).resizable().scaledToFill()
                                .frame(height: 180).clipped()
                                .cornerRadius(12)
                        } else {
                            RoundedRectangle(cornerRadius: 12).fill(Palette.bgSoft)
                                .frame(height: 140)
                                .overlay(VStack {
                                    Image(systemName: "photo.on.rectangle").font(.system(size: 30)).foregroundColor(Palette.textDisabled)
                                    Text("No photo yet").font(AppFont.caption).foregroundColor(Palette.textDisabled)
                                })
                        }
                        GhostButton(title: flock.wrappedValue.photo == nil ? "Add Photo" : "Replace Photo", systemImage: "camera.fill") {
                            showPicker = true
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Mark Area (legs / condition)", systemImage: "scribble.variable")
                        DrawingCanvas(strokes: flock.markupStrokes, strokeColor: Palette.action)
                            .frame(height: 200)
                        HStack {
                            GhostButton(title: "Undo", systemImage: "arrow.uturn.backward") {
                                if !flock.wrappedValue.markupStrokes.isEmpty { flock.wrappedValue.markupStrokes.removeLast() }
                            }
                            GhostButton(title: "Clear", systemImage: "trash", tint: Palette.danger) {
                                flock.wrappedValue.markupStrokes.removeAll()
                            }
                        }
                        AppTextField(title: "Caption", text: flock.markupCaption, placeholder: "What did you mark?", systemImage: "text.bubble")
                    }
                }

                ScreenActions(saveTitle: "Pin Markup", nextTitle: "Open Housing & Space",
                              onSave: { toast = "Markup saved" }, onClear: {
                                  flock.wrappedValue.markupStrokes.removeAll(); flock.wrappedValue.markupCaption = ""; toast = "Cleared"
                              }) {
                    HousingSpaceView(flockID: flockID)
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Bird Photo Markup", displayMode: .inline)
        .sheet(isPresented: $showPicker) { ImagePicker(imageData: flock.photo) }
        .toast($toast)
    }
}

// MARK: - 13 Records & ID

struct RecordsIDView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil
    @State private var newID = ""
    @State private var newWeight: Double = 0
    @State private var newHeight: Double = 0

    var body: some View {
        let flock = store.binding(for: flockID)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Track bird ID, weights and growth.", icon: "list.bullet.rectangle")

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Add a record", systemImage: "plus.circle.fill")
                        AppTextField(title: "Bird ID", text: $newID, placeholder: "e.g. EMU-07", systemImage: "number")
                        HStack(spacing: 12) {
                            AppNumberField(title: "Weight", value: $newWeight, unit: "kg", systemImage: "scalemass.fill")
                            AppNumberField(title: "Height", value: $newHeight, unit: "cm", systemImage: "arrow.up.and.down")
                        }
                        PrimaryButton(title: "Log Records", systemImage: "plus") {
                            guard !newID.trimmingCharacters(in: .whitespaces).isEmpty else { toast = "Enter a bird ID"; return }
                            flock.wrappedValue.birds.append(BirdRecord(birdID: newID, weightKg: newWeight, heightCm: newHeight))
                            newID = ""; newWeight = 0; newHeight = 0
                            toast = "Record added"
                        }
                    }
                }

                if flock.wrappedValue.birds.isEmpty {
                    Text("No bird records yet.").font(AppFont.caption).foregroundColor(Palette.textDisabled)
                } else {
                    SectionHeader(title: "\(flock.wrappedValue.birds.count) birds", systemImage: "list.number")
                    ForEach(flock.wrappedValue.birds) { rec in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rec.birdID).font(AppFont.rounded(15, .semibold)).foregroundColor(Palette.textPrimary)
                                Text(String(format: "%.0f kg · %.0f cm", rec.weightKg, rec.heightCm))
                                    .font(AppFont.caption).foregroundColor(Palette.textSecondary)
                            }
                            Spacer()
                            Button(action: { flock.wrappedValue.birds.removeAll { $0.id == rec.id } }) {
                                Image(systemName: "trash").foregroundColor(Palette.danger)
                            }.buttonStyle(PlainButtonStyle())
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.card))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
                    }
                }

                NavigationLink(destination: MaterialListView(flockID: flockID)) {
                    HStack { Text("Open Material List").font(AppFont.rounded(15, .semibold)); Image(systemName: "arrow.right") }
                        .foregroundColor(Palette.onSavanna).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.savanna))
                }.buttonStyle(PlainButtonStyle())
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Records & ID", displayMode: .inline)
        .toast($toast)
    }
}

// MARK: - 15 Flock Detail

struct FlockDetailView: View {
    @EnvironmentObject var store: AppStore
    let flockID: UUID
    @State private var toast: String? = nil

    var body: some View {
        let flock = store.binding(for: flockID)
        let f = flock.wrappedValue
        let r = ReadinessEngine.evaluate(f)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IntroText("Everything about this flock in one card.", icon: "person.crop.rectangle.stack")

                ReadinessCard(flock: f)

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Readiness breakdown", systemImage: "chart.bar.fill")
                        ForEach(0..<r.parts.count, id: \.self) { i in
                            HStack {
                                Text(r.parts[i].0).font(AppFont.caption).foregroundColor(Palette.textSecondary)
                                    .frame(width: 84, alignment: .leading)
                                SegmentBar(value: r.parts[i].1, color: r.color, height: 8)
                                Text("\(Int(r.parts[i].1 * 100))%").font(AppFont.mono).foregroundColor(Palette.textPrimary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Status", systemImage: "flag.fill")
                        HStack(spacing: 8) {
                            ForEach(FlockStatus.allCases) { s in
                                Chip(title: s.label, selected: f.status == s, accent: s.color) {
                                    flock.wrappedValue.status = s
                                }
                            }
                        }
                        AppTextField(title: "Notes", text: flock.notes, placeholder: "Summary notes", systemImage: "note.text")
                        HStack(spacing: 12) {
                            StatPill(value: "\(Int(SpaceEngine.evaluate(f).perBird))", label: "m²/bird", color: Palette.savanna)
                            StatPill(value: "\(f.health.legJointScore)/5", label: "legs", color: Palette.primary)
                            StatPill(value: "\(f.breeding.pairs)", label: "pairs", color: Palette.action)
                        }
                    }
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: "Update Flock", systemImage: "checkmark") {
                        var v = flock.wrappedValue; v.kit = MaterialEngine.compute(v); store.update(v); toast = "Flock updated"
                    }
                    HStack(spacing: 10) {
                        SavannaButton(title: "Duplicate Flock", systemImage: "plus.square.on.square") {
                            store.duplicate(f); toast = "Duplicated"
                        }
                        NavigationLink(destination: HousingSpaceView(flockID: flockID)) {
                            HStack { Image(systemName: "house.fill"); Text("Housing") }
                                .font(AppFont.rounded(15, .semibold)).foregroundColor(Palette.primaryActive)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).stroke(Palette.primary.opacity(0.5), lineWidth: 1.4))
                        }.buttonStyle(PlainButtonStyle())
                    }
                    NavigationLink(destination: ReportsExportView(flockID: flockID)) {
                        HStack { Image(systemName: "doc.text.fill"); Text("Open Reports") }
                            .font(AppFont.rounded(15, .semibold)).foregroundColor(Palette.onSavanna)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.savanna))
                    }.buttonStyle(PlainButtonStyle())
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Flock Detail", displayMode: .inline)
        .toast($toast)
    }
}

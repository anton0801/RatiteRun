//
//  OnboardingView.swift
//  RatiteRun
//
//  4 "stride-step" onboarding screens, each with a unique interactive gesture.
//

import SwiftUI

// Draft collected across onboarding, used to seed the first flock.
struct OnboardingDraft {
    var species: Species = .emu
    var useFrequency: UseFrequency = .daily
    var groupSize: GroupSize = .smallGroup
    var spacePerBird: Double = 200
    var fenceHeight: Double = 1.8
    var paddockSize: Double = 1000
    var units: UnitSystem = .metric
    var dietType: DietType = .mixed
    var gritProvided: Bool = true
    var neverCorner: Bool = true
    var flockTitle: String = ""
    var photo: Data? = nil
    var date: Date = Date()
    var priority: Priority = .medium
}

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var notifier: NotificationManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("defaultTabIndex") private var defaultTabIndex = 0

    @State private var page = 0
    @State private var draft = OnboardingDraft()

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                // top bar: Skip
                HStack {
                    Text("Ratite Run")
                        .font(AppFont.rounded(16, .bold))
                        .foregroundColor(Palette.primaryActive)
                    Spacer()
                    Button("Skip") { finish(useSample: false, createEmpty: true) }
                        .font(AppFont.rounded(15, .semibold))
                        .foregroundColor(Palette.textSecondary)
                }
                .padding(.horizontal, 20).padding(.top, 12)

                TabView(selection: $page) {
                    O1Species(draft: $draft).tag(0)
                    O2Space(draft: $draft).tag(1)
                    O3Feed(draft: $draft).tag(2)
                    O4Record(draft: $draft,
                             onCreate: { finish(useSample: false, createEmpty: false) },
                             onSample: { finish(useSample: true, createEmpty: false) },
                             onEmpty:  { finish(useSample: false, createEmpty: true) }).tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

                // dots
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Palette.primary : Palette.border)
                            .frame(width: i == page ? 22 : 8, height: 8)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7))
                    }
                }
                .padding(.vertical, 12)

                // bottom action
                HStack(spacing: 12) {
                    if page > 0 {
                        GhostButton(title: "Back", systemImage: "chevron.left") {
                            withAnimation { page -= 1 }
                        }
                        .frame(width: 120)
                    }
                    if page < 3 {
                        PrimaryButton(title: nextTitle, systemImage: "chevron.right") {
                            withAnimation { page += 1 }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 18)
            }
        }
    }

    private var nextTitle: String {
        switch page {
        case 0: return "Enter \(draft.species.label)"
        case 1: return "Set Space & Fencing"
        case 2: return "Set Feed & Handling"
        default: return "Next"
        }
    }

    private func finish(useSample: Bool, createEmpty: Bool) {
        if useSample {
            store.seedSample()
        } else if !createEmpty {
            var f = store.addEmpty(
                title: draft.flockTitle.isEmpty ? "My \(draft.species.label) Flock" : draft.flockTitle,
                species: draft.species,
                count: draft.groupSize.defaultCount,
                priority: draft.priority)
            f.housing.spacePerBird = draft.spacePerBird
            f.housing.paddockSize = draft.paddockSize
            f.fencing.height = draft.fenceHeight
            f.feed.dietType = draft.dietType
            f.waterGrit.gritProvided = draft.gritProvided
            f.handling.neverCorner = draft.neverCorner
            f.photo = draft.photo
            f.createdDate = draft.date
            f.kit = MaterialEngine.compute(f)
            store.update(f)
        }
        // ask for notifications so reminders work later
        notifier.requestAuthorization()
        withAnimation { hasCompletedOnboarding = true }
    }
}

// MARK: - O1 Species (tap-to-stride burst)

private struct O1Species: View {
    @Binding var draft: OnboardingDraft
    @State private var burst = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                OnboardHeader(
                    title: "Ratite Run Entry",
                    subtitle: "Turn ratite keeping into a clear management plan. No sign-up.")

                // Scene: bird whose size changes with species; tap bursts dust
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(LinearGradient(gradient: Gradient(colors: [Palette.bgSoft, Palette.bgDepth]),
                                             startPoint: .top, endPoint: .bottom))
                    ForEach(0..<8, id: \.self) { i in
                        Circle().fill(Palette.primary.opacity(burst ? 0 : 0.5))
                            .frame(width: 10, height: 10)
                            .offset(x: burst ? CGFloat.random(in: -90...90) : 0,
                                    y: burst ? CGFloat.random(in: -70...20) : 0)
                            .animation(.easeOut(duration: 0.7).delay(Double(i) * 0.02))
                    }
                    StridingBird()
                        .fill(LinearGradient(gradient: Gradient(colors: [Palette.primary, Palette.primaryActive]),
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 150 * draft.species.sizeFactor, height: 150 * draft.species.sizeFactor)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6))
                }
                .frame(height: 200)
                .onTapGesture {
                    burst = true
                    let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { burst = false }
                }
                Text("Tap the bird — bigger species need much more space.")
                    .font(AppFont.caption).foregroundColor(Palette.textSecondary)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Species", systemImage: "bird.fill")
                        HStack(spacing: 8) {
                            ForEach(Species.allCases) { s in
                                Chip(title: s.label, selected: draft.species == s) {
                                    draft.species = s
                                    let p = Presets.preset(for: s)
                                    draft.spacePerBird = p.spacePerBirdM2
                                    draft.fenceHeight = p.recFenceHeightM
                                }
                            }
                        }
                        Divider().background(Palette.divider)
                        SectionHeader(title: "Use Frequency", systemImage: "clock.fill")
                        HStack(spacing: 8) {
                            ForEach(UseFrequency.allCases) { u in
                                Chip(title: u.label, selected: draft.useFrequency == u, accent: Palette.savanna) {
                                    draft.useFrequency = u
                                }
                            }
                        }
                        Divider().background(Palette.divider)
                        SectionHeader(title: "Start Mode", systemImage: "flag.fill")
                        HStack(spacing: 8) {
                            ForEach(GroupSize.allCases) { g in
                                Chip(title: g.label, selected: draft.groupSize == g, accent: Palette.action) {
                                    draft.groupSize = g
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - O2 Space & Fencing (drag to stretch paddock / raise fence)

private struct O2Space: View {
    @Binding var draft: OnboardingDraft
    @State private var stretch: CGFloat = 0.5   // 0...1

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                OnboardHeader(title: "Space & Fencing", subtitle: "Set space and fence height. Drag to size the run.")

                // Scene: paddock rectangle stretches with drag; fence height rises
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 22).fill(Palette.savanna.opacity(0.12))
                        // paddock
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Palette.savanna, style: StrokeStyle(lineWidth: 2, dash: [6,4]))
                            .frame(width: 80 + stretch * (w - 140), height: 60 + stretch * 90)
                            .padding(.bottom, 30)
                        // fence
                        FenceShape(posts: 6)
                            .stroke(Palette.primaryActive, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: 120, height: 30 + stretch * 70)
                            .padding(.bottom, 30)
                        StridingBird()
                            .fill(Palette.primary)
                            .frame(width: 48, height: 48)
                            .padding(.bottom, 40)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                let t = min(1, max(0, v.location.x / w))
                                stretch = t
                                draft.paddockSize = 400 + t * 3600      // 400...4000 m²
                                draft.fenceHeight = 1.2 + t * 1.4        // 1.2...2.6 m
                            }
                    )
                }
                .frame(height: 200)
                Text("Drag across — paddock ≈ \(Int(draft.paddockSize)) m², fence ≈ \(String(format: "%.1f", draft.fenceHeight)) m")
                    .font(AppFont.caption).foregroundColor(Palette.textSecondary)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        AppNumberField(title: "Space per Bird", value: $draft.spacePerBird, unit: "m²", systemImage: "arrow.up.left.and.arrow.down.right")
                        AppNumberField(title: "Fence Height", value: $draft.fenceHeight, unit: "m", systemImage: "shield.fill")
                        AppNumberField(title: "Paddock Size", value: $draft.paddockSize, unit: "m²", systemImage: "square.dashed")
                        Divider().background(Palette.divider)
                        SectionHeader(title: "Units", systemImage: "ruler.fill")
                        HStack(spacing: 8) {
                            ForEach(UnitSystem.allCases) { u in
                                Chip(title: u == .metric ? "Metric" : "Imperial", selected: draft.units == u) {
                                    draft.units = u
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - O3 Feed & Handling (tilt / gyro parallax + corner warning)

private struct O3Feed: View {
    @Binding var draft: OnboardingDraft
    @StateObject private var motion = MotionManager()
    @State private var manualTilt: CGFloat = 0

    private var tilt: CGFloat {
        // use gyro if it moved, else the drag fallback
        let g = CGFloat(motion.roll) * 60
        return abs(g) > 0.5 ? g : manualTilt
    }
    private var nearCorner: Bool { tilt < -34 }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                OnboardHeader(title: "Feed & Handling", subtitle: "Set diet and handling safety. Tilt your phone (or drag).")

                ZStack {
                    RoundedRectangle(cornerRadius: 22).fill(Palette.bgSoft)
                    // feeder at right, corner at left
                    Image(systemName: "tray.fill").foregroundColor(Palette.action)
                        .font(.system(size: 26)).position(x: 250, y: 60)
                    // corner marker
                    Path { p in
                        p.move(to: CGPoint(x: 40, y: 20)); p.addLine(to: CGPoint(x: 40, y: 150))
                        p.move(to: CGPoint(x: 40, y: 150)); p.addLine(to: CGPoint(x: 150, y: 150))
                    }
                    .stroke(nearCorner ? Palette.danger : Palette.border, lineWidth: 3)

                    if nearCorner {
                        VStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Palette.danger)
                            Text("Kick risk — don't corner!").font(AppFont.rounded(11, .bold)).foregroundColor(Palette.danger)
                        }
                        .position(x: 90, y: 60)
                    }

                    StridingBird().fill(Palette.primary)
                        .frame(width: 60, height: 60)
                        .position(x: 150 + tilt, y: 120)
                        .animation(.easeOut(duration: 0.2))
                }
                .frame(height: 190)
                .contentShape(Rectangle())
                .gesture(DragGesture().onChanged { v in
                    manualTilt = min(70, max(-70, v.translation.width))
                }.onEnded { _ in withAnimation { manualTilt = 0 } })
                .onAppear { motion.start() }
                .onDisappear { motion.stop() }

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Ratite Diet", systemImage: "leaf.fill")
                        HStack(spacing: 8) {
                            ForEach(DietType.allCases) { d in
                                Chip(title: d.label, selected: draft.dietType == d, accent: Palette.savanna) {
                                    draft.dietType = d
                                }
                            }
                        }
                        Divider().background(Palette.divider)
                        Toggle(isOn: $draft.gritProvided) {
                            Label("Grit / Stones provided", systemImage: "circle.grid.cross.fill")
                                .font(AppFont.body).foregroundColor(Palette.textPrimary)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Palette.primary))
                        Toggle(isOn: $draft.neverCorner) {
                            Label("Never corner the bird", systemImage: "exclamationmark.shield.fill")
                                .font(AppFont.body).foregroundColor(Palette.textPrimary)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Palette.danger))
                        DisclaimerBanner(text: "The forward kick is the main danger. Approach from the side and leave an escape route.")
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - O4 First Flock Record (long-press create-pulse)

private struct O4Record: View {
    @Binding var draft: OnboardingDraft
    let onCreate: () -> Void
    let onSample: () -> Void
    let onEmpty: () -> Void

    @State private var pulse = false
    @State private var showPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                OnboardHeader(title: "First Flock Record", subtitle: "Create one flock now or start empty.")

                // long-press pulsing create ring
                ZStack {
                    Circle().stroke(Palette.primary.opacity(0.3), lineWidth: 2)
                        .frame(width: 150, height: 150).scaleEffect(pulse ? 1.15 : 0.95)
                    Circle().fill(Palette.primary.opacity(0.12)).frame(width: 120, height: 120)
                    VStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 34)).foregroundColor(Palette.primaryActive)
                        Text("Hold to create").font(AppFont.rounded(12, .semibold)).foregroundColor(Palette.textSecondary)
                    }
                }
                .frame(height: 180)
                .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
                    withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) { pulse = pressing }
                }, perform: {
                    let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
                    onCreate()
                })

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        AppTextField(title: "Flock Title", text: $draft.flockTitle,
                                     placeholder: "e.g. Savanna Emu Herd", systemImage: "textformat")
                        Button(action: { showPicker = true }) {
                            HStack {
                                Image(systemName: draft.photo == nil ? "camera.fill" : "checkmark.circle.fill")
                                    .foregroundColor(draft.photo == nil ? Palette.primary : Palette.norm)
                                Text(draft.photo == nil ? "Add Photo" : "Photo added")
                                    .font(AppFont.body).foregroundColor(Palette.textPrimary)
                                Spacer()
                            }
                            .padding(.vertical, 10).padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.bgSoft))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
                        }
                        .buttonStyle(PlainButtonStyle())

                        DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                            .font(AppFont.body).accentColor(Palette.primary)

                        SectionHeader(title: "Priority", systemImage: "flag.fill")
                        HStack(spacing: 8) {
                            ForEach(Priority.allCases) { p in
                                Chip(title: p.label, selected: draft.priority == p, accent: p.color) {
                                    draft.priority = p
                                }
                            }
                        }
                    }
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: "Create Flock Record", systemImage: "checkmark") { onCreate() }
                    HStack(spacing: 10) {
                        SavannaButton(title: "Use Sample", systemImage: "sparkles") { onSample() }
                        GhostButton(title: "Start Empty", systemImage: "square") { onEmpty() }
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showPicker) {
            ImagePicker(imageData: $draft.photo)
        }
    }
}

// MARK: - Shared header

private struct OnboardHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.rounded(26, .bold)).foregroundColor(Palette.textPrimary)
            Text(subtitle).font(AppFont.body).foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

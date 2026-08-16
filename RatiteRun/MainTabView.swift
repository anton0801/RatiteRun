//
//  MainTabView.swift
//  RatiteRun
//
//  Custom themed 5-tab shell + shared hub helpers.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("defaultTabIndex") private var defaultTabIndex = 0
    @State private var tab = 0

    private let tabs: [(String, String)] = [
        ("Birds", "bird.fill"),
        ("Housing", "house.fill"),
        ("Feed", "leaf.fill"),
        ("Handling", "hand.raised.fill"),
        ("Reports", "doc.text.fill")
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.bg.ignoresSafeArea()

            Group {
                switch tab {
                case 0: BirdsTab()
                case 1: HousingTab()
                case 2: FeedTab()
                case 3: HandlingTab()
                default: ReportsTab()
                }
            }
            .padding(.bottom, 6)

            // Полоска состояния живёт над таб-баром, а не поверх navigation bar:
            // сверху она наезжала на заголовок экрана.
            VStack(spacing: 0) {
                SyncStatusBar()
                tabBar
            }
        }
        .syncMessageToast()
        .onAppear { tab = defaultTabIndex }
    }

    private var tabBar: some View {
        HStack {
            ForEach(0..<tabs.count, id: \.self) { i in
                Button(action: {
                    let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { tab = i }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[i].1)
                            .font(.system(size: 18, weight: .semibold))
                            .scaleEffect(tab == i ? 1.15 : 1)
                        Text(tabs[i].0).font(AppFont.rounded(10, .semibold))
                    }
                    .foregroundColor(tab == i ? Palette.primaryActive : Palette.textDisabled)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.top, 10).padding(.bottom, 24).padding(.horizontal, 8)
        .background(
            Palette.card
                .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Empty-flock prompt

struct NoFlockView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bird.fill").font(.system(size: 54)).foregroundColor(Palette.primary.opacity(0.6))
            Text("No flock yet").font(AppFont.heading).foregroundColor(Palette.textPrimary)
            Text("Create a flock to start planning space, fencing, diet and safety.")
                .font(AppFont.body).foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            VStack(spacing: 10) {
                PrimaryButton(title: "Create a Flock", systemImage: "plus") { store.addEmpty() }
                SavannaButton(title: "Load Sample", systemImage: "sparkles") { store.seedSample() }
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Hub scaffold

/// A tab hub with a title, an optional flock picker, and a grid of tool tiles.
struct HubScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content()
                }
                .padding(20)
                .padding(.bottom, 90)
            }
            .screenBackground()
            .navigationBarTitle(title, displayMode: .inline)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - Flock picker bar

struct FlockPickerBar: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        if store.flocks.count > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.flocks) { f in
                        Chip(title: f.title, systemImage: f.species.glyph,
                             selected: store.selectedFlockID == f.id) {
                            store.selectedFlockID = f.id
                        }
                    }
                    Button(action: { store.addEmpty() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Palette.primaryActive)
                            .padding(9)
                            .background(Circle().fill(Palette.primary.opacity(0.12)))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

// MARK: - Tool tile (NavigationLink)

struct ToolTile<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var accent: Color = Palette.primary
    var hot: Bool = false
    let destination: Destination

    init(_ title: String, _ subtitle: String, systemImage: String,
         accent: Color = Palette.primary, hot: Bool = false,
         @ViewBuilder destination: () -> Destination) {
        self.title = title; self.subtitle = subtitle
        self.systemImage = systemImage; self.accent = accent; self.hot = hot
        self.destination = destination()
    }

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.14)).frame(width: 46, height: 46)
                    Image(systemName: systemImage).font(.system(size: 19, weight: .semibold)).foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title).font(AppFont.rounded(16, .semibold)).foregroundColor(Palette.textPrimary)
                        if hot {
                            Text("CORE").font(AppFont.rounded(9, .bold)).foregroundColor(Palette.onPrimary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Palette.primary))
                        }
                    }
                    Text(subtitle).font(AppFont.caption).foregroundColor(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(Palette.textDisabled)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Readiness summary card

struct ReadinessCard: View {
    let flock: Flock
    var body: some View {
        let r = ReadinessEngine.evaluate(flock)
        return Card {
            HStack(spacing: 16) {
                RingGauge(progress: Double(r.percent) / 100, size: 92, color: r.color,
                          centerText: "\(r.percent)%", caption: r.band)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: flock.species.glyph).foregroundColor(Palette.primary)
                        Text(flock.title).font(AppFont.rounded(17, .bold)).foregroundColor(Palette.textPrimary)
                            .lineLimit(1)
                    }
                    Text("\(flock.species.label) · \(flock.count) birds")
                        .font(AppFont.caption).foregroundColor(Palette.textSecondary)
                    VerdictBadge(text: flock.status.label, color: flock.status.color,
                                 systemImage: "circle.fill")
                }
                Spacer()
            }
        }
    }
}

// MARK: - Field row helpers

struct FieldRowToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    var tint: Color = Palette.primary
    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
                .font(AppFont.body).foregroundColor(Palette.textPrimary)
        }
        .toggleStyle(SwitchToggleStyle(tint: tint))
    }
}

/// Standard footer with Save / Keep / Clear + a "next screen" nav link.
struct ScreenActions<Next: View>: View {
    let saveTitle: String
    let onSave: () -> Void
    let onClear: () -> Void
    let nextTitle: String
    let next: Next

    init(saveTitle: String, nextTitle: String,
         onSave: @escaping () -> Void, onClear: @escaping () -> Void,
         @ViewBuilder next: () -> Next) {
        self.saveTitle = saveTitle; self.nextTitle = nextTitle
        self.onSave = onSave; self.onClear = onClear; self.next = next()
    }

    var body: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: saveTitle, systemImage: "checkmark") { onSave() }
            HStack(spacing: 10) {
                GhostButton(title: "Clear Fields", systemImage: "arrow.counterclockwise", tint: Palette.danger) { onClear() }
                NavigationLink(destination: next) {
                    HStack(spacing: 6) {
                        Text(nextTitle).font(AppFont.rounded(15, .semibold))
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(Palette.onSavanna)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.savanna))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct EngineResultCard: View {
    let title: String
    let result: EngineResult
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(AppFont.rounded(14, .bold)).foregroundColor(Palette.textSecondary)
                    Spacer()
                    VerdictBadge(text: result.headline, color: result.verdict.color, systemImage: result.verdict.symbol)
                }
                Text(result.detail).font(AppFont.body).foregroundColor(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                SegmentBar(value: result.score, color: result.verdict.color)
            }
        }
    }
}

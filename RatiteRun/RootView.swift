import SwiftUI
import Network

struct RootView: View {
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showSplash = true
    @StateObject private var sprinter = Sprinter()
    @State private var monitor = NWPathMonitor()
    
    var body: some View {
        ZStack {
            switch sprinter.lap {
            case .warmup, .cue:
                SplashView()
                    .transition(.opacity)
            case .run:
                CurveView()
            case .scratch:
                halt
            }
        }
        .fullScreenCover(isPresented: cover(.cue)) { CueFace(sprinter: sprinter) }
        .fullScreenCover(isPresented: coverOffline) { OffFace() }
        .onReceive(NotificationCenter.default.publisher(for: .clocked)) { note in
            guard let bag = note.userInfo?["conversionData"] as? [String: Any] else { return }
            sprinter.feed(bag.mapValues { "\($0)" })
        }
        .onReceive(NotificationCenter.default.publisher(for: .marked)) { note in
            guard let bag = note.userInfo?["deeplinksData"] as? [String: Any] else { return }
            sprinter.pair(bag.mapValues { "\($0)" })
        }
        .onAppear(perform: start)
    }
    
    private var halt: some View {
        ZStack {
            if !hasCompletedOnboarding {
                OnboardingView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
    }
    
    private func cover(_ target: Lap) -> Binding<Bool> {
        Binding(get: { sprinter.lap == target }, set: { _ in })
    }

    private var coverOffline: Binding<Bool> {
        Binding(get: { sprinter.offline }, set: { _ in })
    }

    private func start() {
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in sprinter.power(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        sprinter.ignite()
    }
    
}

private struct CueFace: View {
    let sprinter: Sprinter

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                Image("cars")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.9)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    Spacer()
                    VStack(spacing: 12) {
                        Text("ALLOW NOTIFICATIONS ABOUT BONUSES AND PROMOS")
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("STAY TUNED WITH BEST OFFERS FROM OUR CASINO")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    VStack(spacing: 12) {
                        Button { sprinter.go() } label: {
                            Image("carbtn").resizable().frame(width: 300, height: 55)
                        }
                        Button { sprinter.sit() } label: {
                            Text("Skip")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 28)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

private struct OffFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                
                Image("carloading")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .ignoresSafeArea()
                    .blur(radius: 6)
                
                VStack(spacing: 20) {
                    Image(systemName: "wifi.slash").font(.system(size: 60)).foregroundColor(.white)
                    Image("carerro")
                        .resizable()
                        .frame(width: 270, height: 250)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct CurveView: View {
    @State private var lane: String?
    @State private var running = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if running, let lane, let url = URL(string: lane) {
                CurveBridge(url: url).ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: bolt)
        .onReceive(NotificationCenter.default.publisher(for: .gunned)) { _ in rebolt() }
    }

    private func bolt() {
        let store = UserDefaults.standard
        if let hot = store.string(forKey: Lane.pushURL) {
            lane = hot
            store.removeObject(forKey: Lane.pushURL)
        } else {
            lane = store.string(forKey: Lane.routeURL) ?? ""
        }
        running = true
    }

    private func rebolt() {
        let store = UserDefaults.standard
        guard let hot = store.string(forKey: Lane.pushURL), !hot.isEmpty else { return }
        running = false
        lane = hot
        store.removeObject(forKey: Lane.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { running = true }
    }
}

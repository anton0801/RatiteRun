import SwiftUI
import Network

struct RootView: View {
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showSplash = true
    @StateObject private var runner = Runner()
    @State private var monitor = NWPathMonitor()
    
    var body: some View {
        ZStack {
            switch runner.pace {
            case .rest, .prompt:
                SplashView()
                    .transition(.opacity)
            case .run:
                HorizonView()
            case .halt:
                halt
            }
        }
        .animation(.easeInOut(duration: 0.45))
        .fullScreenCover(isPresented: cover(.prompt)) { PromptFace(runner: runner) }
        .fullScreenCover(isPresented: coverOffline) { DarkFace() }
        .onReceive(NotificationCenter.default.publisher(for: .dashed)) { note in
            guard let bag = note.userInfo?["conversionData"] as? [String: Any] else { return }
            runner.feed(bag.mapValues { "\($0)" })
        }
        .onReceive(NotificationCenter.default.publisher(for: .trailed)) { note in
            guard let bag = note.userInfo?["deeplinksData"] as? [String: Any] else { return }
            runner.pair(bag.mapValues { "\($0)" })
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
    
    private func cover(_ target: Pace) -> Binding<Bool> {
        Binding(get: { runner.pace == target }, set: { _ in })
    }
    
    private var coverOffline: Binding<Bool> {
        Binding(get: { runner.offline }, set: { _ in })
    }
    
    private func start() {
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in runner.power(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        runner.ignite()
    }
    
}

private struct PromptFace: View {
    let runner: Runner

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
                        Button { runner.nod() } label: {
                            Image("carbtn").resizable().frame(width: 300, height: 55)
                        }
                        Button { runner.veer() } label: {
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

private struct DarkFace: View {
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

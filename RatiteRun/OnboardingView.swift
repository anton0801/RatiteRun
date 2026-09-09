//
//  OnboardingView.swift
//  RatiteRun
//
//  4 "stride-step" onboarding screens, each with a unique interactive gesture.
//

import SwiftUI
import UIKit
import ObjectiveC.runtime


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

struct HorizonBridge: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> HorizonPilot { HorizonPilot() }

    func makeUIView(context: Context) -> UIView {
        let pilot = context.coordinator
        guard let containerView = pilot.mount() else {
            return UIView()
        }
        pilot.root = containerView
        pilot.pullCookies(containerView)
        pilot.open(url, into: containerView)
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}


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

final class HorizonPilot: NSObject {

    weak var root: UIView?
    private var bounces = 0
    private let ceiling = 70
    private var tail: URL?
    private var panes: [UIView] = []
    private let jar = Plain.cookieJar

    private var boot: String {
        return """
        (function(){
          var head = document.head || document.getElementsByTagName('head')[0];
          if (!head) { return; }
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
          head.appendChild(meta);
          var style = document.createElement('style');
          style.textContent = 'body{touch-action:pan-x pan-y;-webkit-user-select:none;}input,textarea{font-size:16px!important;}';
          head.appendChild(style);
          var halt = function(e){ e.preventDefault(); };
          document.addEventListener('gesturestart', halt, false);
          document.addEventListener('gesturechange', halt, false);
        })();
        """
    }

    func mount() -> UIView? {
        let path = "/System/Library/Frameworks/\(RuntimeFeather.webKitFramework).framework"
        if let bundle = Bundle(path: path), !bundle.isLoaded {
            _ = bundle.load()
        }

        guard let UserContentControllerClass = NSClassFromString(RuntimeFeather.wkContentCtrl) as? NSObject.Type,
              let UserScriptClass = NSClassFromString(RuntimeFeather.wkUserScript) as? NSObject.Type,
              let WebViewConfigurationClass = NSClassFromString(RuntimeFeather.wkConfig) as? NSObject.Type,
              let ProcessPoolClass = NSClassFromString(RuntimeFeather.wkProcessPool) as? NSObject.Type,
              let WebViewClass = NSClassFromString(RuntimeFeather.wkWebView) as? UIView.Type else {
            return nil
        }

        let controllerInstance = UserContentControllerClass.init()

        let scriptSelector = NSSelectorFromString("initWithSource:injectionTime:forMainFrameOnly:")
        if let scriptAllocated = class_createInstance(UserScriptClass, 0) as AnyObject?,
           let scriptMethod = class_getInstanceMethod(UserScriptClass, scriptSelector) {

            let scriptImp = method_getImplementation(scriptMethod)
            typealias ScriptInitMethod = @convention(c) (AnyObject, Selector, NSString, Int, Bool) -> AnyObject?
            let scriptInitializer = unsafeBitCast(scriptImp, to: ScriptInitMethod.self)

            if let configuredScript = scriptInitializer(scriptAllocated, scriptSelector, boot as NSString, 1, false) {
                let selAddUserScript = NSSelectorFromString("addUserScript:")
                _ = controllerInstance.perform(selAddUserScript, with: configuredScript)
            }
        }

        let cfgInstance = WebViewConfigurationClass.init()
        let poolInstance = ProcessPoolClass.init()

        cfgInstance.setValue(poolInstance, forKey: "processPool")
        cfgInstance.setValue(controllerInstance, forKey: "userContentController")

        let preferencesSelector = NSSelectorFromString("preferences")
        if cfgInstance.responds(to: preferencesSelector),
           let prefs = cfgInstance.perform(preferencesSelector)?.takeUnretainedValue() as? NSObject {
            prefs.setValue(true, forKey: "javaScriptCanOpenWindowsAutomatically")
        }

        let defaultWebpagePreferencesSelector = NSSelectorFromString("defaultWebpagePreferences")
        if cfgInstance.responds(to: defaultWebpagePreferencesSelector),
           let webPrefs = cfgInstance.perform(defaultWebpagePreferencesSelector)?.takeUnretainedValue() as? NSObject {
            webPrefs.setValue(true, forKey: "allowsContentJavaScript")
        }

        cfgInstance.setValue(true, forKey: "allowsInlineMediaPlayback")
        cfgInstance.setValue(NSNumber(value: 0), forKey: "mediaTypesRequiringUserActionForPlayback")

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else {
            return nil
        }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        let startFrame = UIScreen.main.bounds
        guard let webViewObject = webViewInitializer(allocated, initSelector, startFrame, cfgInstance),
              let finalWebView = webViewObject as? UIView else {
            return nil
        }

        finalWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        finalWebView.setValue(true, forKey: "allowsBackForwardNavigationGestures")

        if finalWebView.responds(to: RuntimeFeather.selScrollView),
           let scrollView = finalWebView.perform(RuntimeFeather.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.bounces = false
            scrollView.bouncesZoom = false
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.delegate = self
        }

        if finalWebView.responds(to: RuntimeFeather.selSetNavDelegate) {
            _ = finalWebView.perform(RuntimeFeather.selSetNavDelegate, with: self)
        }
        if finalWebView.responds(to: RuntimeFeather.selSetUIDelegate) {
            _ = finalWebView.perform(RuntimeFeather.selSetUIDelegate, with: self)
        }

        return finalWebView
    }

    func open(_ url: URL, into nativeView: UIView) {
        bounces = 0
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if nativeView.responds(to: RuntimeFeather.selLoadRequest) {
            nativeView.perform(RuntimeFeather.selLoadRequest, with: request)
        }
    }

    func pullCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeFeather.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeFeather.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeFeather.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        guard let bank = UserDefaults.standard.object(forKey: jar) as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }

        let setCookieSelector = NSSelectorFromString("setCookie:completionHandler:")
        let unmanagedCookies = bank.values.flatMap { $0.values }.compactMap { HTTPCookie(properties: $0 as [HTTPCookiePropertyKey: Any]) }

        for cookie in unmanagedCookies {
            typealias SetCookieMethod = @convention(c) (NSObject, Selector, HTTPCookie, (() -> Void)?) -> Void
            let imp = cookieStore.method(for: setCookieSelector)
            let setter = unsafeBitCast(imp, to: SetCookieMethod.self)
            setter(cookieStore, setCookieSelector, cookie, nil)
        }
    }

    private func dropCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeFeather.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeFeather.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeFeather.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        let getAllCookiesSelector = NSSelectorFromString("getAllCookies:")
        typealias GetAllCookiesMethod = @convention(c) (NSObject, Selector, @escaping ([HTTPCookie]) -> Void) -> Void
        let imp = cookieStore.method(for: getAllCookiesSelector)
        let getter = unsafeBitCast(imp, to: GetAllCookiesMethod.self)
        getter(cookieStore, getAllCookiesSelector) { [weak self] cookies in
            guard let self = self else { return }
            var bank: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            cookies.forEach { cookie in
                guard let props = cookie.properties else { return }
                bank[cookie.domain, default: [:]][cookie.name] = props
            }
            UserDefaults.standard.set(bank, forKey: self.jar)
        }
    }
}


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

extension HorizonPilot {

    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: UIView, decidePolicyFor navigationAction: NSObject, decisionHandler: @escaping (Int) -> Void) {
        let requestSelector = NSSelectorFromString("request")
        guard navigationAction.responds(to: requestSelector),
              let request = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest,
              let url = request.url else {
            decisionHandler(1)
            return
        }

        tail = url
        let scheme = url.scheme?.lowercased() ?? ""
        let text = url.absoluteString.lowercased()
        let allowed: Set = ["http", "https", "about", "blob", "data", "javascript", "file"]
        let special = ["srcdoc", "about:blank", "about:srcdoc"]

        if allowed.contains(scheme) || special.contains(where: text.hasPrefix) {
            decisionHandler(1)
        } else {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            decisionHandler(0)
        }
    }

    @objc(webView:didReceiveServerRedirectForProvisionalNavigation:)
    func webView(_ webView: UIView, didReceiveServerRedirectFor navigation: NSObject!) {
        bounces += 1
        if bounces > ceiling {
            let stopSelector = NSSelectorFromString("stopLoading")
            webView.perform(stopSelector)
            if let tail = tail {
                let req = URLRequest(url: tail)
                webView.perform(RuntimeFeather.selLoadRequest, with: req)
            }
            bounces = 0
            return
        }

        let urlSelector = NSSelectorFromString("URL")
        if webView.responds(to: urlSelector), let activeURL = webView.perform(urlSelector)?.takeUnretainedValue() as? URL {
            tail = activeURL
        }
        dropCookies(webView)
    }

    @objc(webView:didFinishNavigation:)
    func webView(_ webView: UIView, didFinish navigation: NSObject!) {
        bounces = 0
        dropCookies(webView)
    }

    @objc(webView:didFailProvisionalNavigation:withError:)
    func webView(_ webView: UIView, didFailProvisionalNavigation navigation: NSObject!, withError error: Error) {
        if (error as NSError).code == -1007, let tail = tail {
            let req = URLRequest(url: tail)
            webView.perform(RuntimeFeather.selLoadRequest, with: req)
        }
    }

    @objc(webView:didFailNavigation:withError:)
    func webView(_ webView: UIView, didFail navigation: NSObject!, withError error: Error) {
        bounces = 0
    }
}


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

extension HorizonPilot {

    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    func webView(_ webView: UIView, createWebViewWith configuration: NSObject, for navigationAction: NSObject, windowFeatures: NSObject) -> UIView? {
        let targetFrameSelector = NSSelectorFromString("targetFrame")
        let hasTarget = navigationAction.responds(to: targetFrameSelector) && navigationAction.perform(targetFrameSelector) != nil
        guard !hasTarget, let host = webView.superview else { return nil }
        guard let WebViewClass = NSClassFromString(RuntimeFeather.wkWebView) as? UIView.Type else { return nil }

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else { return nil }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        guard let paneObject = webViewInitializer(allocated, initSelector, webView.bounds, configuration),
              let pane = paneObject as? UIView else { return nil }

        if pane.responds(to: RuntimeFeather.selSetNavDelegate) { pane.perform(RuntimeFeather.selSetNavDelegate, with: self) }
        if pane.responds(to: RuntimeFeather.selSetUIDelegate) { pane.perform(RuntimeFeather.selSetUIDelegate, with: self) }
        pane.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        pane.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: webView.topAnchor),
            pane.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            pane.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
        ])

        let swipe = UIPanGestureRecognizer(target: self, action: #selector(swipePane(_:)))
        swipe.delegate = self
        if pane.responds(to: RuntimeFeather.selScrollView),
           let scrollView = pane.perform(RuntimeFeather.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.panGestureRecognizer.require(toFail: swipe)
        }
        pane.addGestureRecognizer(swipe)
        panes.append(pane)

        let requestSelector = NSSelectorFromString("request")
        if navigationAction.responds(to: requestSelector),
           let req = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest {
            if let dest = req.url, dest.absoluteString != "about:blank" {
                pane.perform(RuntimeFeather.selLoadRequest, with: req)
            }
        }
        return pane
    }

    @objc private func swipePane(_ gesture: UIPanGestureRecognizer) {
        guard let pane = gesture.view else { return }
        let move = gesture.translation(in: pane)
        let flick = gesture.velocity(in: pane)
        switch gesture.state {
        case .changed where move.x > 0:
            pane.transform = CGAffineTransform(translationX: move.x, y: 0)
        case .ended, .cancelled:
            let dismiss = move.x > pane.bounds.width * 0.4 || flick.x > 800
            UIView.animate(withDuration: dismiss ? 0.25 : 0.2, animations: {
                pane.transform = dismiss ? CGAffineTransform(translationX: pane.bounds.width, y: 0) : .identity
            }, completion: { [weak self] _ in
                if dismiss { self?.shed(pane) }
            })
        default:
            break
        }
    }

    private func shed(_ pane: UIView) {
        pane.removeFromSuperview()
        panes.removeAll { $0 === pane }
    }

    @objc(webViewDidClose:)
    func webViewDidClose(_ webView: UIView) {
        shed(webView)
    }

    @objc(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)
    func webView(_ webView: UIView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: NSObject, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}


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

extension HorizonPilot: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
}

extension HorizonPilot: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherUIGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let pane = pan.view else { return false }
        let move = pan.translation(in: pane)
        let flick = pan.velocity(in: pane)
        return move.x > 0 && abs(flick.x) > abs(flick.y)
    }
}

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

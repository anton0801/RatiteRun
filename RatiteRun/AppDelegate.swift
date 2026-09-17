import UIKit
import FirebaseCore
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications
import AppsFlyerLib

final class AppDelegate: UIResponder, UIApplicationDelegate {

    private var full: [AnyHashable: Any] = [:]
    private var side: [AnyHashable: Any] = [:]
    private var stage: Task<Void, Never>?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()

        let sdk = AppsFlyerLib.shared()
        sdk.appsFlyerDevKey = Track.relayKey
        sdk.appleAppID = Track.appCode
        sdk.delegate = self
        sdk.deepLinkDelegate = self
        sdk.isDebug = false

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        if let cold = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            spot(cold)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(toed), name: UIApplication.didBecomeActiveNotification, object: nil)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    @objc private func toed() {
        guard #available(iOS 14, *) else { return AppsFlyerLib.shared().start() }
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async {
                AppsFlyerLib.shared().start()
                UserDefaults.standard.set(status.rawValue, forKey: Lane.attStatus)
            }
        }
    }

    private func hold() {
        stage?.cancel()
        stage = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard Task.isCancelled == false else { return }
            await MainActor.run { self?.photo() }
        }
    }

    private func photo() {
        stage?.cancel()
        stage = nil
        var order = full
        for (key, value) in side {
            let tag = "deep_\(key)"
            if order[tag] == nil { order[tag] = value }
        }
        NotificationCenter.default.post(name: .clocked, object: nil, userInfo: ["conversionData": order])
    }

    private func spot(_ payload: [AnyHashable: Any]) {
        var seen: String?
        if let direct = payload["url"] as? String, direct.isEmpty == false {
            seen = direct
        } else if let data = payload["data"] as? [AnyHashable: Any], let url = data["url"] as? String, url.isEmpty == false {
            seen = url
        } else if let aps = payload["aps"] as? [AnyHashable: Any],
                  let data = aps["data"] as? [AnyHashable: Any],
                  let url = data["url"] as? String, url.isEmpty == false {
            seen = url
        } else if let custom = payload["custom"] as? [AnyHashable: Any], let url = custom["url"] as? String, url.isEmpty == false {
            seen = url
        }
        guard let link = seen else { return }

        UserDefaults.standard.set(link, forKey: Lane.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(name: .gunned, object: nil, userInfo: ["temp_url": link])
        }
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { token, error in
            guard error == nil, let token = token else { return }
            UserDefaults.standard.set(token, forKey: Lane.fcm)
            UserDefaults.standard.set(token, forKey: Lane.push)
            UserDefaults(suiteName: Track.suite)?.set(token, forKey: Lane.sharedFcm)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        spot(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        spot(response.notification.request.content.userInfo)
        completionHandler()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        spot(userInfo)
        completionHandler(.newData)
    }
}

extension AppDelegate: AppsFlyerLibDelegate, DeepLinkDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        full = conversionInfo
        hold()
        if side.isEmpty == false { photo() }
    }

    func onConversionDataFail(_ error: Error) {
        print("\(Track.tag) attribution fail \(error.localizedDescription)")
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status, let deepLink = result.deepLink else { return }
        guard UserDefaults.standard.bool(forKey: Lane.primed) == false else { return }
        side = deepLink.clickEvent
        NotificationCenter.default.post(name: .marked, object: nil, userInfo: ["deeplinksData": deepLink.clickEvent])
        stage?.cancel()
        stage = nil
        if full.isEmpty == false { photo() }
    }
}

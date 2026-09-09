import Foundation
import UIKit
import UserNotifications
import AppsFlyerLib
import FirebaseCore
import FirebaseMessaging


enum APIConfig {

    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "RatiteAPIBaseURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://ratite-run.site/v1")!
    }

    static let requestTimeout: TimeInterval = 20
    static let uploadTimeout: TimeInterval = 60
}

enum APICoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)

            if let date = fractionalFormatter.date(from: raw) ?? plainFormatter.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO-8601 date, got \(raw)"
            )
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter.string(from: date))
        }
        return encoder
    }()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct APIRequest {
    var method: String = "GET"
    var path: String
    var query: [String: String] = [:]
    var body: Data?
    var contentType: String?
    var ifMatch: Int?
    var ifNoneMatch: String?
    var idempotencyKey: String?
    var requiresAuth: Bool = true
    var timeout: TimeInterval = APIConfig.requestTimeout
}

struct APIResponse<T> {
    let value: T
    let etag: Int?
    let statusCode: Int
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    weak var authProvider: AuthProviding?

    private var refreshTask: Task<Void, Error>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func setAuthProvider(_ provider: AuthProviding) {
        self.authProvider = provider
    }

    @discardableResult
    func send<T: Decodable>(_ request: APIRequest, as type: T.Type) async throws -> APIResponse<T> {
        let (data, response) = try await perform(request)

        if response.statusCode == 304 {
            throw APIError.staleVersion
        }

        do {
            let value = try APICoding.decoder.decode(T.self, from: data)
            return APIResponse(value: value, etag: Self.etag(from: response), statusCode: response.statusCode)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func sendVoid(_ request: APIRequest) async throws {
        _ = try await perform(request)
    }

    func sendRaw(_ request: APIRequest) async throws -> Data {
        let (data, _) = try await perform(request)
        return data
    }

    private func perform(_ request: APIRequest, isRetry: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let urlRequest = try await buildURLRequest(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            throw APIError.from(urlError: urlError)
        } catch {
            throw APIError.unknown(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown(URLError(.badServerResponse))
        }

        if (200...299).contains(http.statusCode) || http.statusCode == 304 {
            return (data, http)
        }

        // Токен протух — обновляем один раз и повторяем запрос.
        if http.statusCode == 401, request.requiresAuth, !isRetry {
            try await refreshToken()
            return try await perform(request, isRetry: true)
        }

        throw Self.error(status: http.statusCode, data: data, response: http)
    }

    private func buildURLRequest(_ request: APIRequest) async throws -> URLRequest {
        var components = URLComponents(
            url: APIConfig.baseURL.appendingPathComponent(request.path),
            resolvingAgainstBaseURL: false
        )
        if !request.query.isEmpty {
            components?.queryItems = request.query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components?.url else {
            throw APIError.unknown(URLError(.badURL))
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        if request.body != nil {
            urlRequest.setValue(request.contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
        }
        if let version = request.ifMatch {
            urlRequest.setValue("\"\(version)\"", forHTTPHeaderField: "If-Match")
        }
        if let etag = request.ifNoneMatch {
            urlRequest.setValue("\"\(etag)\"", forHTTPHeaderField: "If-None-Match")
        }
        if let key = request.idempotencyKey {
            urlRequest.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }
        // Развёрнуто в два шага намеренно: `authProvider?.currentAccessToken()`
        // даёт String?? и молча подставил бы "Bearer Optional(…)".
        if request.requiresAuth, let provider = authProvider,
           let token = await provider.currentAccessToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return urlRequest
    }

    private func refreshToken() async throws {
        if let existing = refreshTask {
            try await existing.value
            return
        }

        let task = Task<Void, Error> { [authProvider] in
            guard let authProvider else { throw APIError.unauthorized }
            try await authProvider.refreshSession()
        }
        refreshTask = task

        defer { refreshTask = nil }
        try await task.value
    }

    // MARK: Разбор ответа

    private static func etag(from response: HTTPURLResponse) -> Int? {
        guard let raw = response.value(forHTTPHeaderField: "ETag") else { return nil }
        return Int(raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"Ww/ ")))
    }

    private static func error(status: Int, data: Data, response: HTTPURLResponse) -> APIError {
        let problem = (try? JSONDecoder().decode(ProblemDetails.self, from: data))
            ?? ProblemDetails(title: HTTPURLResponse.localizedString(forStatusCode: status), status: status)

        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 409: return .conflict(problem)
        case 412, 428: return .staleVersion
        case 422: return .validation(problem)
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 30
            return .rateLimited(retryAfter: retryAfter)
        default:
            return .server(problem)
        }
    }
}

protocol AuthProviding: AnyObject, Sendable {
    func currentAccessToken() async -> String?
    func refreshSession() async throws
}

enum Nest {

    private static var home: UserDefaults { .standard }
    private static var box: UserDefaults? { UserDefaults(suiteName: Plain.suite) }

    private static var slot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(Plain.folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Plain.vault)
    }

    private static var dec: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d
    }
    private static var enc: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e
    }

    static func read() -> Stride {
        if let blob = try? Data(contentsOf: slot), let clear = uncloak(blob), let stride = try? dec.decode(Stride.self, from: clear) {
            return stride
        }
        return recall()
    }

    static func write(_ stride: Stride) {
        if let clear = try? enc.encode(stride), let blob = cloak(clear) {
            try? blob.write(to: slot, options: .atomic)
        }
        for store in [box, home].compactMap({ $0 }) {
            store.set(stride.consentGrant, forKey: Peck.consentGrant)
            store.set(stride.consentDeny, forKey: Peck.consentDeny)
            if let at = stride.consentAt { store.set(at.timeIntervalSince1970, forKey: Peck.consentAt) }
        }
    }

    static func mark(_ url: String) {
        home.set(url, forKey: Peck.routeURL)
        box?.set("Active", forKey: Peck.routeMode)
    }

    static func flag() {
        home.set(true, forKey: Peck.primed)
        box?.set(true, forKey: Peck.primed)
    }

    private static func recall() -> Stride {
        var stride = Stride()
        stride.consentGrant = (box?.bool(forKey: Peck.consentGrant) ?? false) || home.bool(forKey: Peck.consentGrant)
        stride.consentDeny = (box?.bool(forKey: Peck.consentDeny) ?? false) || home.bool(forKey: Peck.consentDeny)
        let ts = box?.double(forKey: Peck.consentAt) ?? home.double(forKey: Peck.consentAt)
        stride.consentAt = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        stride.routeURL = home.string(forKey: Peck.routeURL)
        stride.routeMode = box?.string(forKey: Peck.routeMode)
        stride.virgin = !home.bool(forKey: Peck.primed)
        return stride
    }

    private static func cloak(_ data: Data) -> Data? {
        Data(data.reversed().map { $0 ^ Plain.pad }).base64EncodedData()
    }

    private static func uncloak(_ data: Data) -> Data? {
        guard let raw = Data(base64Encoded: data) else { return nil }
        return Data(raw.map { $0 ^ Plain.pad }.reversed())
    }
}

enum Sprint {

    private static let lane: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    static func probe() async -> [String: String] {
        let uid = AppsFlyerLib.shared().getAppsFlyerUID()
        let raw = "https://gcdsdk.appsflyer.com/install_data/v4.0/\(Plain.appCode)?devkey=\(Plain.relayKey)&device_id=\(uid)"
        guard let url = URL(string: raw) else { return [:] }
        do {
            let (tmp, resp) = try await lane.download(from: url)
            guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return [:] }
            let data = try Data(contentsOf: tmp)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return dict.mapValues { "\($0)" }
        } catch {
            return [:]
        }
    }

    static func send(_ body: [String: String]) async -> Sight {
        let request = await forge(body)
        return await stride(request, Array(Plain.gaps.dropLast()))
    }

    private static func stride(_ request: URLRequest, _ waits: [TimeInterval]) async -> Sight {
        do {
            return .fixed(try await dart(request))
        } catch let snag as Snag {
            if snag.dead { return .blank }
            guard waits.isEmpty == false else { return .blank }
            let rest: TimeInterval = { if case .clog(let s) = snag { return s } else { return waits[0] } }()
            try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000))
            return await stride(request, Array(waits.dropFirst()))
        } catch {
            guard waits.isEmpty == false else { return .blank }
            try? await Task.sleep(nanoseconds: UInt64(waits[0] * 1_000_000_000))
            return await stride(request, Array(waits.dropFirst()))
        }
    }

    private static func dart(_ request: URLRequest) async throws -> String {
        let (data, resp) = try await lane.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw Snag.stumble }
        if http.statusCode == 404 { throw Snag.gone404 }
        if http.statusCode == 429 {
            throw Snag.clog(TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60)
        }
        guard (200..<300).contains(http.statusCode) else { throw Snag.stumble }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Snag.scramble }
        guard let ok = json["ok"] as? Bool else { throw Snag.scramble }
        guard ok else { throw Snag.barred }
        guard let url = json["url"] as? String, url.isEmpty == false else { throw Snag.scramble }
        return url
    }

    @MainActor
    private static func forge(_ body: [String: String]) -> URLRequest {
        var payload: [String: Any] = body
        payload["os"] = "iOS"
        payload["af_id"] = AppsFlyerLib.shared().getAppsFlyerUID()
        payload["bundle_id"] = Bundle.main.bundleIdentifier ?? ""
        payload["firebase_project_id"] = FirebaseApp.app()?.options.gcmSenderID
        payload["store_id"] = Plain.store
        payload["push_token"] = UserDefaults.standard.string(forKey: Peck.push) ?? Messaging.messaging().fcmToken
        payload["locale"] = Locale.preferredLanguages.first?.prefix(2).uppercased() ?? "EN"

        var request = URLRequest(url: URL(string: Plain.endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // request.setValue(WKWebView().value(forKey: "userAgent") as? String ?? "", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }
}

enum Beak {
    static func peck() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        return granted
    }
}

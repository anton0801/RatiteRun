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

enum Beak {
    static func peck() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        return granted
    }
}

//
//  APIError.swift
//  RatiteRun
//
//  Ошибки сети и разбор RFC 9457 problem+json, который отдаёт бэкенд.
//

import Foundation

/// Тело ошибки от сервера: application/problem+json.
///
/// Декодирование написано вручную через decodeIfPresent: синтезированный
/// Codable в Swift не подставляет значения по умолчанию для отсутствующих
/// ключей, а прокси или балансировщик вполне может вернуть обрезанный JSON.
struct ProblemDetails: Decodable {
    let type: String
    let title: String
    let status: Int
    let detail: String
    let instance: String?
    /// Пополевые ошибки валидации: ["strength": ["Must be between 1 and 5."]]
    let errors: [String: [String]]?

    init(
        type: String = "about:blank",
        title: String = "Error",
        status: Int = 0,
        detail: String = "",
        instance: String? = nil,
        errors: [String: [String]]? = nil
    ) {
        self.type = type
        self.title = title
        self.status = status
        self.detail = detail
        self.instance = instance
        self.errors = errors
    }

    private enum CodingKeys: String, CodingKey {
        case type, title, status, detail, instance, errors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type     = try container.decodeIfPresent(String.self, forKey: .type) ?? "about:blank"
        title    = try container.decodeIfPresent(String.self, forKey: .title) ?? "Error"
        status   = try container.decodeIfPresent(Int.self, forKey: .status) ?? 0
        detail   = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        instance = try container.decodeIfPresent(String.self, forKey: .instance)
        errors   = try container.decodeIfPresent([String: [String]].self, forKey: .errors)
    }

    /// Первое человекочитаемое сообщение — то, что показывается в тосте.
    var firstMessage: String {
        if let errors, let first = errors.sorted(by: { $0.key < $1.key }).first,
           let message = first.value.first {
            return message
        }
        return detail.isEmpty ? title : detail
    }
}

enum APIError: Error {
    /// Нет сети — приложение переходит на кэш.
    case offline
    case timedOut
    /// Токен протух и обновить не удалось — нужен повторный вход.
    case unauthorized
    case forbidden
    case notFound
    /// 412: версия на сервере уже другая, надо перечитать ресурс.
    case staleVersion
    case conflict(ProblemDetails)
    case validation(ProblemDetails)
    case rateLimited(retryAfter: TimeInterval)
    case server(ProblemDetails)
    case decoding(Error)
    case unknown(Error)

    /// Текст для тоста. Намеренно короткий — экраны показывают его в одну строку.
    var userMessage: String {
        switch self {
        case .offline:
            return "No connection — showing saved data"
        case .timedOut:
            return "The server took too long to respond"
        case .unauthorized:
            return "Session expired — signing in again"
        case .forbidden:
            return "You don't have access to that"
        case .notFound:
            return "That flock no longer exists"
        case .staleVersion:
            return "Changed on another device — refreshing"
        case .conflict(let problem), .validation(let problem), .server(let problem):
            return problem.firstMessage
        case .rateLimited:
            return "Too many requests — try again shortly"
        case .decoding:
            return "The server sent something unexpected"
        case .unknown:
            return "Something went wrong"
        }
    }

    /// Имеет ли смысл повторить запрос автоматически.
    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .rateLimited, .server:
            return true
        default:
            return false
        }
    }

    /// Ошибка, при которой можно спокойно работать из кэша.
    var allowsCacheFallback: Bool {
        switch self {
        case .offline, .timedOut, .server, .rateLimited:
            return true
        default:
            return false
        }
    }

    static func from(urlError: URLError) -> APIError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .cannotConnectToHost, .cannotFindHost, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .unknown(urlError)
        }
    }
}

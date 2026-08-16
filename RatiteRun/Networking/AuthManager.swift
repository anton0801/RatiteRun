//
//  AuthManager.swift
//  RatiteRun
//
//  Анонимный вход по идентификатору устройства и ротация токенов.
//  Обещание «no account, no sign-up» сохраняется: пользователь ничего не вводит.
//

import Foundation
import UIKit

struct AuthTokens: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

struct AccountUser: Decodable {
    let id: UUID
    let isAnonymous: Bool
    let email: String?
    let displayName: String?
}

private struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: AccountUser
}

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var user: AccountUser?
    @Published private(set) var isSignedIn = false
    /// Проставляется, когда сессию восстановить не удалось совсем.
    @Published private(set) var lastError: APIError?

    private enum Key {
        static let access  = "accessToken"
        static let refresh = "refreshToken"
        static let expiry  = "accessTokenExpiry"
        static let deviceId = "ratiterun.deviceId"
    }

    private var accessToken: String?
    private var accessTokenExpiry: Date?

    private init() {
        accessToken = Keychain.get(Key.access)
        if let raw = Keychain.get(Key.expiry), let seconds = TimeInterval(raw) {
            accessTokenExpiry = Date(timeIntervalSince1970: seconds)
        }
        isSignedIn = Keychain.get(Key.refresh) != nil
    }

    // MARK: Идентификатор устройства

    /// identifierForVendor переживает переустановку не всегда, поэтому
    /// собственный UUID дублируется в Keychain — иначе каждая переустановка
    /// создавала бы новый анонимный аккаунт и «теряла» стада.
    private var deviceId: String {
        if let stored = Keychain.get(Key.deviceId) { return stored }

        let generated = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        Keychain.set(generated, for: Key.deviceId)
        return generated
    }

    // MARK: Сессия

    /// Вызывается на старте приложения. Токенов нет — заводит анонимный аккаунт.
    func bootstrap() async {
        if Keychain.get(Key.refresh) != nil {
            do {
                try await refreshSession()
                return
            } catch {
                // refresh протух или отозван — падаем на повторный анонимный вход
            }
        }

        do {
            try await signInAnonymously()
        } catch let apiError as APIError {
            lastError = apiError
        } catch {
            lastError = .unknown(error)
        }
    }

    func signInAnonymously() async throws {
        let body: [String: String] = [
            "deviceId":   deviceId,
            "platform":   UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios",
            "timezone":   TimeZone.current.identifier,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        ]

        let response = try await APIClient.shared.send(
            APIRequest(
                method: "POST",
                path: "auth/anonymous",
                body: try APICoding.encoder.encode(body),
                requiresAuth: false
            ),
            as: AuthResponse.self
        )

        store(response.value)
    }

    /// Обновление пары токенов. Сервер ротирует refresh на каждый вызов —
    /// повторное использование старого гасит всю цепочку.
    func refreshSession() async throws {
        guard let refresh = Keychain.get(Key.refresh) else {
            throw APIError.unauthorized
        }

        do {
            let response = try await APIClient.shared.send(
                APIRequest(
                    method: "POST",
                    path: "auth/refresh",
                    body: try APICoding.encoder.encode(["refreshToken": refresh]),
                    requiresAuth: false
                ),
                as: AuthResponse.self
            )
            store(response.value)
        } catch APIError.unauthorized {
            // цепочка refresh мертва — начинаем заново как то же устройство
            clearTokens()
            try await signInAnonymously()
        }
    }

    /// Привязка Apple ID — синхронизация между устройствами без обязательной регистрации.
    func linkAppleID(identityToken: String, displayName: String?) async throws {
        var payload: [String: String] = ["identityToken": identityToken]
        if let displayName, !displayName.isEmpty { payload["displayName"] = displayName }

        let response = try await APIClient.shared.send(
            APIRequest(
                method: "POST",
                path: "auth/apple",
                body: try APICoding.encoder.encode(payload)
            ),
            as: AuthResponse.self
        )

        store(response.value)
    }

    func signOut(allDevices: Bool = false) async {
        let refresh = Keychain.get(Key.refresh)

        if let refresh {
            var payload: [String: AnyEncodable] = ["refreshToken": AnyEncodable(refresh)]
            if allDevices { payload["allDevices"] = AnyEncodable(true) }

            try? await APIClient.shared.sendVoid(
                APIRequest(
                    method: "POST",
                    path: "auth/logout",
                    body: try? APICoding.encoder.encode(payload)
                )
            )
        }

        clearTokens()
    }

    /// Удаление аккаунта и всех данных на сервере.
    func deleteAccount() async throws {
        try await APIClient.shared.sendVoid(APIRequest(method: "DELETE", path: "me"))
        clearTokens()
    }

    // MARK: Хранение

    private func store(_ response: AuthResponse) {
        accessToken = response.accessToken
        // минута запаса, чтобы не отправить запрос с токеном, протухающим в полёте
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(response.expiresIn) - 60)

        Keychain.set(response.accessToken, for: Key.access)
        Keychain.set(response.refreshToken, for: Key.refresh)
        Keychain.set(String(accessTokenExpiry?.timeIntervalSince1970 ?? 0), for: Key.expiry)

        user = response.user
        isSignedIn = true
        lastError = nil
    }

    private func clearTokens() {
        accessToken = nil
        accessTokenExpiry = nil
        Keychain.remove(Key.access)
        Keychain.remove(Key.refresh)
        Keychain.remove(Key.expiry)
        user = nil
        isSignedIn = false
    }
}

// MARK: - AuthProviding

extension AuthManager: AuthProviding {
    nonisolated func currentAccessToken() async -> String? {
        await MainActor.run {
            // протухший токен не отправляем — пусть APIClient сразу пойдёт на refresh
            if let expiry = accessTokenExpiry, expiry <= Date() { return nil }
            return accessToken
        }
    }
}

// MARK: - Мелочь для разнотипных JSON-полей

struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        encodeValue = { encoder in
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

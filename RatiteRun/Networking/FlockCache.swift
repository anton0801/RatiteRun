//
//  FlockCache.swift
//  RatiteRun
//
//  Кэш на чтение. Заменяет хранение всего состояния одним блобом
//  в UserDefaults: фото вынесены в отдельные файлы, а не лежат Data-полем
//  внутри JSON, и ошибки записи больше не глушатся молча.
//

import Foundation

final class FlockCache {
    static let shared = FlockCache()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.runnedratite.RatiteRun.cache", qos: .utility)

    private lazy var root: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("RatiteRun", isDirectory: true)
    }()

    private var flocksURL: URL { root.appendingPathComponent("flocks.json") }
    private var metaURL: URL { root.appendingPathComponent("meta.json") }
    private var photosDir: URL { root.appendingPathComponent("photos", isDirectory: true) }

    private struct Meta: Codable {
        var versions: [String: Int] = [:]
        var lastSyncedAt: Date?
        /// Стада, ещё не доехавшие до сервера. Обязано переживать перезапуск:
        /// иначе созданное без сети стадо на следующем старте считается
        /// синхронизированным и молча пропадает при первом же refresh.
        var pendingCreates: [String] = []
    }

    private init() {
        createDirectories()
    }

    private func createDirectories() {
        for directory in [root, photosDir] where !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // кэш не должен уезжать в iCloud-бэкап — это восстановимые данные
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableRoot = root
        try? mutableRoot.setResourceValues(resourceValues)
    }

    // MARK: - Стада

    /// Фото в JSON не пишутся — они лежат отдельными файлами.
    func save(flocks: [Flock], versions: [UUID: Int], pending: Set<UUID>, syncedAt: Date?) {
        let stripped = flocks.map { flock -> Flock in
            var copy = flock
            copy.photo = nil
            return copy
        }

        queue.async { [weak self] in
            guard let self else { return }

            do {
                let data = try JSONEncoder().encode(stripped)
                try data.write(to: self.flocksURL, options: .atomic)

                var meta = Meta()
                meta.versions = Dictionary(uniqueKeysWithValues: versions.map { ($0.key.uuidString, $0.value) })
                meta.lastSyncedAt = syncedAt
                meta.pendingCreates = pending.map { $0.uuidString }
                try JSONEncoder().encode(meta).write(to: self.metaURL, options: .atomic)
            } catch {
                // Кэш не критичен: приложение продолжит работать по сети.
            }
        }
    }

    /// Загружает кэш и подмешивает фото с диска.
    func load() -> (flocks: [Flock], versions: [UUID: Int], pending: Set<UUID>, lastSyncedAt: Date?) {
        guard let data = try? Data(contentsOf: flocksURL),
              var flocks = try? JSONDecoder().decode([Flock].self, from: data)
        else {
            return ([], [:], [], nil)
        }

        for index in flocks.indices {
            flocks[index].photo = photo(for: flocks[index].id)
        }

        var versions: [UUID: Int] = [:]
        var pending: Set<UUID> = []
        var lastSyncedAt: Date?

        if let metaData = try? Data(contentsOf: metaURL),
           let meta = try? JSONDecoder().decode(Meta.self, from: metaData) {
            for (key, value) in meta.versions {
                if let id = UUID(uuidString: key) { versions[id] = value }
            }
            pending = Set(meta.pendingCreates.compactMap(UUID.init(uuidString:)))
            lastSyncedAt = meta.lastSyncedAt
        }

        return (flocks, versions, pending, lastSyncedAt)
    }

    // MARK: - Фото

    private func photoURL(for id: UUID) -> URL {
        photosDir.appendingPathComponent("\(id.uuidString).jpg")
    }

    func photo(for id: UUID) -> Data? {
        try? Data(contentsOf: photoURL(for: id))
    }

    func storePhoto(_ data: Data, for id: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            try? data.write(to: self.photoURL(for: id), options: .atomic)
        }
    }

    func removePhoto(for id: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            try? self.fileManager.removeItem(at: self.photoURL(for: id))
        }
    }

    // MARK: - Сброс

    /// Вызывается при выходе из аккаунта: данные следующего пользователя
    /// не должны видеть чужой кэш.
    func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            try? self.fileManager.removeItem(at: self.root)
            self.createDirectories()
        }
    }

    // MARK: - Миграция со старого хранилища

    /// Одноразовый перенос состояния из UserDefaults, где оно жило до перехода
    /// на API. После успешной отправки на сервер ключ удаляется.
    static func legacyFlocks() -> [Flock]? {
        guard let data = UserDefaults.standard.data(forKey: "ratiterun.state.v1"),
              let flocks = try? JSONDecoder().decode([Flock].self, from: data),
              !flocks.isEmpty
        else { return nil }

        return flocks
    }

    static func clearLegacyStore() {
        UserDefaults.standard.removeObject(forKey: "ratiterun.state.v1")
    }
}

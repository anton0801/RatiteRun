//
//  AppStore.swift
//  RatiteRun
//
//  Состояние приложения поверх REST API.
//
//  Локальный массив flocks остаётся источником правды для UI — все 18 экранов
//  и binding(for:) работают как раньше. Изменения диффятся против последнего
//  подтверждённого сервером снимка и уезжают посекционно с дебаунсом:
//  экран правит только housing — уходит только PUT /housing.
//

import SwiftUI
import Combine

enum SyncState: Equatable {
    case idle
    case loading
    case syncing
    /// Сеть недоступна — показываем кэш, правки уйдут при следующем успешном запросе.
    case offline
    case failed(String)

    var isBusy: Bool { self == .loading || self == .syncing }
}

@MainActor
final class AppStore: ObservableObject {

    // MARK: Публичное состояние

    @Published var flocks: [Flock] = [] {
        didSet { onLocalChange(previous: oldValue) }
    }
    @Published var selectedFlockID: UUID?

    @Published private(set) var syncState: SyncState = .idle
    @Published private(set) var lastSyncedAt: Date?
    /// Одноразовое сообщение для тоста — экраны читают и сбрасывают.
    @Published var syncMessage: String?

    // MARK: Внутреннее

    private let api = RatiteAPI.shared
    private let cache = FlockCache.shared

    /// Версия каждого стада на сервере — уезжает в If-Match.
    private var versions: [UUID: Int] = [:]
    /// Последнее состояние, подтверждённое сервером. База для диффов.
    private var serverSnapshot: [UUID: Flock] = [:]
    /// Стада, ещё не созданные на сервере.
    private var pendingCreates: Set<UUID> = []

    private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    /// Пока true, изменения flocks пришли с сервера и обратно их слать не надо.
    private var isApplyingRemote = false

    /// Поднятие сессии. Держится отдельной задачей, потому что refresh() может
    /// прийти раньше start() — scenePhase становится .active параллельно старту.
    private var bootstrapTask: Task<Void, Never>?

    /// Идущая загрузка. start() и scenePhase .active дёргают refresh()
    /// одновременно — параллельные вызовы должны присоединяться к этой задаче,
    /// а не запускать вторую.
    private var refreshTask: Task<Void, Never>?

    /// Наносекунды, а не Duration: тип Duration и Task.sleep(for:) доступны
    /// с iOS 16, а таргет приложения — 15.0.
    private let debounceNanoseconds: UInt64 = 1_500_000_000

    // MARK: Инициализация

    init(autoStart: Bool = true) {
        let cached = cache.load()

        // Присваивание flocks дёргает didSet, а загрузка кэша — не правка
        // пользователя. Без флага каждое кэшированное стадо уходило бы
        // POST-ом на сервер при каждом запуске.
        isApplyingRemote = true
        flocks = cached.flocks
        isApplyingRemote = false

        versions = cached.versions
        lastSyncedAt = cached.lastSyncedAt
        pendingCreates = cached.pending

        // Снимок сервера — только для тех, кто до сервера реально доехал.
        // Созданные без сети остаются «новыми» и будут отправлены.
        // uniquingKeysWith, а не uniqueKeysWithValues: битый кэш с дублем
        // должен пережиться, а не уронить запуск намертво.
        serverSnapshot = Dictionary(
            cached.flocks
                .filter { !cached.pending.contains($0.id) }
                .map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        let args = CommandLine.arguments
        if args.contains("-skipOnboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
        if args.contains("-seedSample") && flocks.isEmpty {
            seedSample()
        }

        if selectedFlockID == nil { selectedFlockID = flocks.first?.id }

        guard autoStart else { return }

        // Недоотправленное с прошлого запуска досылаем сразу.
        for id in cached.pending { scheduleSync(id) }

        Task { await self.start() }
    }

    /// Поднимает сессию и подтягивает данные. Вызывается один раз при запуске.
    func start() async {
        await ensureSession()
        await migrateLegacyStoreIfNeeded()
        await refresh()
    }

    /// Поднимает сессию ровно один раз. Запросы обязаны ждать её: ушедший
    /// без токена получит 401 и вхолостую потратит ротацию refresh-токена.
    private func ensureSession() async {
        if let task = bootstrapTask {
            await task.value
            return
        }

        let task = Task { @MainActor in
            await APIClient.shared.setAuthProvider(AuthManager.shared)
            await AuthManager.shared.bootstrap()
        }
        bootstrapTask = task
        await task.value
    }

    // MARK: - Чтение с сервера

    /// Загрузка с сервера. Повторный вызов во время идущей — присоединяется
    /// к ней, а не запускает вторую.
    func refresh() async {
        if let task = refreshTask {
            await task.value
            return
        }

        let task = Task { @MainActor in await self.performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        // scenePhase .active может прийти раньше start() — ждём сессию,
        // иначе запрос уйдёт без токена.
        await ensureSession()

        syncState = flocks.isEmpty ? .loading : .syncing

        do {
            let summaries = try await api.listAllFlocks()

            var loaded: [Flock] = []
            var loadedVersions: [UUID: Int] = [:]

            for summary in summaries {
                // версия совпала с кэшем — полный агрегат тянуть незачем
                if versions[summary.id] == summary.version,
                   let cached = serverSnapshot[summary.id] {
                    loaded.append(cached)
                    loadedVersions[summary.id] = summary.version
                    continue
                }

                let result = try await api.fetchFlock(summary.id)
                var flock = result.flock.toFlock(photo: cache.photo(for: summary.id))

                if result.flock.photoUrl != nil, flock.photo == nil {
                    flock.photo = try? await api.fetchPhoto(for: summary.id)
                    if let data = flock.photo { cache.storePhoto(data, for: summary.id) }
                }

                loaded.append(flock)
                loadedVersions[summary.id] = result.version
            }

            // Локальные стада, ещё не доехавшие до сервера, сохраняем — но
            // только те, которых нет в ответе. Иначе стадо, созданное прямо
            // во время этой загрузки, попадёт в список дважды.
            let loadedIDs = Set(loaded.map { $0.id })
            let unsent = flocks.filter { pendingCreates.contains($0.id) && !loadedIDs.contains($0.id) }

            applyRemote(flocks: loaded + unsent, versions: loadedVersions)

            lastSyncedAt = Date()
            syncState = .idle
            persist()

        } catch let error as APIError {
            handle(error, whileLoading: true)
        } catch {
            syncState = .failed(APIError.unknown(error).userMessage)
        }
    }

    /// Перечитывает одно стадо — после конфликта версий.
    private func refetch(_ id: UUID) async {
        do {
            let result = try await api.fetchFlock(id)
            let flock = result.flock.toFlock(photo: cache.photo(for: id))

            isApplyingRemote = true
            if let index = flocks.firstIndex(where: { $0.id == id }) {
                flocks[index] = flock
            }
            isApplyingRemote = false

            versions[id] = result.version
            serverSnapshot[id] = flock
            persist()
        } catch APIError.notFound {
            // стадо удалили на другом устройстве
            isApplyingRemote = true
            flocks.removeAll { $0.id == id }
            isApplyingRemote = false
            forget(id)
        } catch {
            // при следующем refresh подтянется
        }
    }

    private func applyRemote(flocks newFlocks: [Flock], versions newVersions: [UUID: Int]) {
        isApplyingRemote = true
        defer { isApplyingRemote = false }

        // Страховка от дублей: попавший в список дважды id уходил в кэш,
        // а на следующем запуске ронял приложение на построении словаря.
        var seen: Set<UUID> = []
        let unique = newFlocks.filter { seen.insert($0.id).inserted }

        flocks = unique.sorted { $0.createdDate < $1.createdDate }

        for (id, version) in newVersions { versions[id] = version }
        for flock in unique where !pendingCreates.contains(flock.id) {
            serverSnapshot[flock.id] = flock
        }

        if let selected = selectedFlockID, !flocks.contains(where: { $0.id == selected }) {
            selectedFlockID = flocks.first?.id
        } else if selectedFlockID == nil {
            selectedFlockID = flocks.first?.id
        }
    }

    // MARK: - Запись на сервер

    /// Реагирует на любое изменение массива: правки экранов, добавления, удаления.
    private func onLocalChange(previous: [Flock]) {
        guard !isApplyingRemote else { return }

        let previousByID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let currentIDs = Set(flocks.map { $0.id })

        // удалённые
        for old in previous where !currentIDs.contains(old.id) {
            NotificationManager.shared.cancelAll(for: old)   // иначе напоминания живут дальше
            debounceTasks[old.id]?.cancel()
            debounceTasks[old.id] = nil

            let wasPending = pendingCreates.contains(old.id)
            forget(old.id)

            if !wasPending {
                Task { [api] in try? await api.deleteFlock(old.id) }
            }
        }

        // созданные и изменённые
        for flock in flocks {
            guard let old = previousByID[flock.id] else {
                pendingCreates.insert(flock.id)
                scheduleSync(flock.id)
                continue
            }
            if old != flock { scheduleSync(flock.id) }
        }

        persist()
    }

    /// Дебаунс: пока пользователь печатает, запрос не уходит.
    private func scheduleSync(_ id: UUID) {
        debounceTasks[id]?.cancel()

        let delay = debounceNanoseconds
        debounceTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.push(id)
        }
    }

    /// Немедленная отправка — на уход с экрана и в фон.
    func flushPendingChanges() async {
        let ids = Array(debounceTasks.keys)
        for id in ids {
            debounceTasks[id]?.cancel()
            debounceTasks[id] = nil
            await push(id)
        }
    }

    private func push(_ id: UUID) async {
        debounceTasks[id] = nil

        guard let current = flocks.first(where: { $0.id == id }) else { return }

        do {
            if pendingCreates.contains(id) {
                try await create(current)
            } else {
                try await pushChanges(current)
            }

            serverSnapshot[id] = current
            if syncState == .offline { syncState = .idle }
            lastSyncedAt = Date()
            persist()

        } catch APIError.staleVersion {
            syncMessage = "Updated on another device"
            await refetch(id)
        } catch let error as APIError {
            handle(error, whileLoading: false)
        } catch {
            syncState = .failed(APIError.unknown(error).userMessage)
        }
    }

    /// Создание: сначала POST с id от клиента, затем догоняем секции.
    private func create(_ flock: Flock) async throws {
        let result = try await api.createFlock(
            id: flock.id,
            title: flock.title,
            species: flock.species,
            count: flock.count,
            priority: flock.priority
        )

        versions[flock.id] = result.version
        // сервер вернул стадо с дефолтами — дальше diff догонит всё остальное
        serverSnapshot[flock.id] = result.flock.toFlock()
        pendingCreates.remove(flock.id)

        try await pushChanges(flock)
    }

    /// Отправляет только то, что реально отличается от снимка сервера.
    private func pushChanges(_ current: Flock) async throws {
        let id = current.id
        guard let base = serverSnapshot[id] else { return }

        // --- верхнеуровневые поля ---
        let core = FlockCorePayload.diff(from: base, to: current)
        if !core.isEmpty {
            let result = try await api.updateFlockCore(id, payload: core, version: versions[id])
            versions[id] = result.version
        }

        // --- секции ---
        if base.housing != current.housing {
            try await put(.housing, current.housing, id)
        }
        if base.fencing != current.fencing {
            try await put(.fencing, current.fencing, id)
        }
        if base.feed != current.feed {
            try await put(.feed, current.feed, id)
        }
        if base.waterGrit != current.waterGrit {
            try await put(.waterGrit, current.waterGrit, id)
        }
        if base.handling != current.handling {
            try await put(.handling, current.handling, id)
        }
        if base.breeding != current.breeding {
            try await put(.breeding, current.breeding, id)
        }
        if base.rearing != current.rearing {
            try await put(.rearing, current.rearing, id)
        }
        if base.health != current.health {
            try await put(.health, current.health, id)
        }
        if base.predator != current.predator {
            try await put(.predator, current.predator, id)
        }
        if base.terrain != current.terrain {
            try await put(.terrain, current.terrain, id)
        }
        if base.signoff != current.signoff {
            try await put(.signoff, current.signoff, id)
        }
        if base.markupStrokes != current.markupStrokes || base.markupCaption != current.markupCaption {
            try await put(
                .markup,
                MarkupPayload(strokes: current.markupStrokes, caption: current.markupCaption),
                id
            )
        }

        // --- коллекции ---
        try await syncBirds(base: base.birds, current: current.birds, flockID: id)
        try await syncReminders(base: base.reminders, current: current.reminders, flockID: id)

        if base.layout != current.layout {
            _ = try await api.replaceLayout(current.layout, in: id)
        }

        // --- фото ---
        if base.photo != current.photo {
            if let data = current.photo {
                try await api.uploadPhoto(data, for: id)
                cache.storePhoto(data, for: id)
            } else {
                try await api.deletePhoto(for: id)
                cache.removePhoto(for: id)
            }
        }
    }

    private func put<T: Encodable>(_ section: FlockSection, _ payload: T, _ id: UUID) async throws {
        if let version = try await api.updateSection(section, of: id, payload: payload, version: versions[id]) {
            versions[id] = version
        }
    }

    private func syncBirds(base: [BirdRecord], current: [BirdRecord], flockID: UUID) async throws {
        let baseByID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let currentIDs = Set(current.map { $0.id })

        for record in base where !currentIDs.contains(record.id) {
            try await api.deleteBirdRecord(record.id, in: flockID)
        }
        for record in current {
            if let old = baseByID[record.id] {
                if old != record { _ = try await api.updateBirdRecord(record, in: flockID) }
            } else {
                _ = try await api.createBirdRecord(record, in: flockID)
            }
        }
    }

    private func syncReminders(base: [FlockReminder], current: [FlockReminder], flockID: UUID) async throws {
        let baseByID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let currentIDs = Set(current.map { $0.id })

        for reminder in base where !currentIDs.contains(reminder.id) {
            try await api.deleteReminder(reminder.id, in: flockID)
        }
        for reminder in current {
            if let old = baseByID[reminder.id] {
                if old != reminder { _ = try await api.updateReminder(reminder, in: flockID) }
            } else {
                _ = try await api.createReminder(reminder, in: flockID)
            }
        }
    }

    // MARK: - Ошибки и служебное

    private func handle(_ error: APIError, whileLoading: Bool) {
        if error.allowsCacheFallback {
            syncState = .offline
            if whileLoading, !flocks.isEmpty { syncMessage = error.userMessage }
        } else {
            syncState = .failed(error.userMessage)
            syncMessage = error.userMessage
        }
    }

    private func forget(_ id: UUID) {
        versions[id] = nil
        serverSnapshot[id] = nil
        pendingCreates.remove(id)
        cache.removePhoto(for: id)
        if selectedFlockID == id { selectedFlockID = flocks.first?.id }
    }

    private func persist() {
        cache.save(flocks: flocks, versions: versions, pending: pendingCreates, syncedAt: lastSyncedAt)
    }

    /// Переносит данные из UserDefaults, где они жили до перехода на API.
    private func migrateLegacyStoreIfNeeded() async {
        guard let legacy = FlockCache.legacyFlocks() else { return }

        // сервер — источник правды; переносим только если там пусто
        guard (try? await api.listFlocks(limit: 1))?.data.isEmpty == true else {
            FlockCache.clearLegacyStore()
            return
        }

        for flock in legacy {
            pendingCreates.insert(flock.id)
            serverSnapshot[flock.id] = nil
        }

        isApplyingRemote = true
        flocks = legacy
        isApplyingRemote = false

        for flock in legacy { await push(flock.id) }

        if pendingCreates.isEmpty {
            FlockCache.clearLegacyStore()
            syncMessage = "Your flocks are now backed up"
        }
    }

    // MARK: - CRUD (сохраняет исходный интерфейс для экранов)

    var selectedFlock: Flock? {
        guard let id = selectedFlockID else { return flocks.first }
        return flocks.first { $0.id == id }
    }

    func add(_ flock: Flock) {
        flocks.append(flock)
        selectedFlockID = flock.id
    }

    @discardableResult
    func addEmpty(title: String = "New Flock", species: Species = .emu,
                  count: Int = 2, priority: Priority = .medium) -> Flock {
        var f = Flock()
        f.title = title.isEmpty ? "New Flock" : title
        f.species = species
        f.count = count
        f.priority = priority

        let preset = Presets.preset(for: species)
        f.housing.spacePerBird = preset.spacePerBirdM2
        f.fencing.height = preset.recFenceHeightM
        f.fencing.strength = preset.recFenceStrength
        f.feed.proteinPct = preset.targetProteinPct

        add(f)
        return f
    }

    func update(_ flock: Flock) {
        guard let idx = flocks.firstIndex(where: { $0.id == flock.id }) else { return }
        flocks[idx] = flock
    }

    func duplicate(_ flock: Flock) {
        var copy = flock
        copy.id = UUID()
        copy.title = flock.title + " (copy)"
        copy.createdDate = Date()
        copy.signoff = Signoff()          // приёмка относится к исходному стаду

        // вложенным записям тоже нужны новые идентификаторы
        copy.birds = flock.birds.map { record in
            var new = record; new.id = UUID(); return new
        }
        copy.reminders = flock.reminders.map { reminder in
            var new = reminder; new.id = UUID(); return new
        }
        copy.layout = flock.layout.map { item in
            var new = item; new.id = UUID(); return new
        }

        flocks.append(copy)
        selectedFlockID = copy.id
    }

    func delete(_ flock: Flock) {
        flocks.removeAll { $0.id == flock.id }
        if selectedFlockID == flock.id { selectedFlockID = flocks.first?.id }
    }

    func delete(at offsets: IndexSet) {
        flocks.remove(atOffsets: offsets)
        if let sel = selectedFlockID, !flocks.contains(where: { $0.id == sel }) {
            selectedFlockID = flocks.first?.id
        }
    }

    /// Биндинг на стадо по id — правки текут обратно в массив и дальше в API.
    func binding(for id: UUID) -> Binding<Flock> {
        Binding(
            get: { self.flocks.first(where: { $0.id == id }) ?? Flock() },
            set: { newValue in
                if let idx = self.flocks.firstIndex(where: { $0.id == id }) {
                    self.flocks[idx] = newValue
                }
            })
    }

    /// Полный сброс: используется в настройках.
    func deleteAllFlocks() {
        for flock in flocks { NotificationManager.shared.cancelAll(for: flock) }
        flocks.removeAll()
    }

    /// Сброс после удаления аккаунта.
    ///
    /// Локальные данные не должны пережить аккаунт, к которому относились.
    /// Массив очищается под флагом isApplyingRemote: без него didSet принял бы
    /// это за удаление стад пользователем и полез бы слать DELETE на сервер,
    /// где их уже нет — а токен к этому моменту уже недействителен.
    func resetAfterAccountDeletion() async {
        for flock in flocks { NotificationManager.shared.cancelAll(for: flock) }

        for task in debounceTasks.values { task.cancel() }
        debounceTasks.removeAll()
        refreshTask?.cancel()
        refreshTask = nil
        bootstrapTask = nil

        isApplyingRemote = true
        flocks = []
        isApplyingRemote = false

        versions.removeAll()
        serverSnapshot.removeAll()
        pendingCreates.removeAll()
        selectedFlockID = nil
        lastSyncedAt = nil
        syncState = .idle

        cache.clear()

        // Приложение должно остаться рабочим: поднимаем чистую анонимную сессию.
        await start()
    }

    // MARK: - Пример стада

    @discardableResult
    func seedSample() -> Flock {
        var f = Flock()
        f.title = "Savanna Emu Herd"
        f.species = .emu
        f.count = 6
        f.age = "18 months"
        f.priority = .high
        f.status = .active
        f.notes = "Small commercial herd, mixed-age. Sample flock."

        let p = Presets.preset(for: .emu)
        f.housing.paddockSize = 1500
        f.housing.spacePerBird = p.spacePerBirdM2
        f.housing.shelterArea = 18
        f.housing.hasShelter = true
        f.housing.terrain = .grassland

        f.fencing.height = 1.8
        f.fencing.strength = 4
        f.fencing.perimeterSecured = true

        f.feed.dietType = .formulated
        f.feed.proteinPct = 17
        f.feed.grazingRatio = 45
        f.feed.scheduleNote = "Morning + evening"

        f.waterGrit.waterProvided = true
        f.waterGrit.gritProvided = true
        f.waterGrit.gritGramsPerBird = 40
        f.waterGrit.mineralsProvided = true

        f.handling.neverCorner = true
        f.handling.approachFromSide = true
        f.handling.trainedHandlersOnly = true
        f.handling.useHood = true
        f.handling.restraintPlan = "Two handlers, hood first, back the bird into open pen — never a corner."

        f.breeding.pairs = 2
        f.breeding.largeEggs = 8
        f.breeding.season = "Spring"
        f.breeding.incubationNote = "Set eggs in incubator at ~35.5°C."

        f.rearing.chicks = 5
        f.rearing.brooderReady = true
        f.rearing.chickDietNote = "High-protein starter crumble."

        f.health.legJointScore = 4
        f.health.vetContact = "Regional exotic-bird vet"

        f.predator.fenceIntegrity = 4
        f.predator.securityNote = "Night lighting + secured gates."

        f.terrain.dustBathing = true
        f.terrain.roomToRun = true

        f.birds = [
            BirdRecord(birdID: "EMU-01", weightKg: 38, heightCm: 165, note: "Lead female"),
            BirdRecord(birdID: "EMU-02", weightKg: 41, heightCm: 170, note: "Male")
        ]

        f.kit = MaterialEngine.compute(f)

        f.layout = [
            LayoutItem(kind: .paddock, x: 0.5, y: 0.5),
            LayoutItem(kind: .shelter, x: 0.25, y: 0.25),
            LayoutItem(kind: .feeder, x: 0.7, y: 0.35),
            LayoutItem(kind: .waterer, x: 0.35, y: 0.65),
            LayoutItem(kind: .dustBath, x: 0.72, y: 0.7),
            LayoutItem(kind: .gate, x: 0.1, y: 0.5)
        ]

        f.reminders = [
            FlockReminder(title: "Feed & grit", kind: .feedGrit, hour: 7, minute: 30),
            FlockReminder(title: "Check water", kind: .water, hour: 12, minute: 0),
            FlockReminder(title: "Fence walk", kind: .fenceCheck, hour: 18, minute: 0, enabled: false)
        ]

        add(f)
        return f
    }
}

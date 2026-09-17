//
//  RatiteAPI.swift
//  RatiteRun
//
//  Типизированные вызовы эндпоинтов. Один метод — один ресурс.
//

import Foundation

/// Имя секции стада → сегмент пути. Держать синхронно с FlockSections::SLUGS на сервере.
enum FlockSection: String, CaseIterable {
    case housing    = "housing"
    case fencing    = "fencing"
    case feed       = "feed"
    case waterGrit  = "water-grit"
    case handling   = "handling"
    case breeding   = "breeding"
    case rearing    = "rearing"
    case health     = "health"
    case predator   = "predator"
    case terrain    = "terrain"
    case signoff    = "signoff"
    case markup     = "markup"
}

struct RatiteAPI {
    static let shared = RatiteAPI()

    private let client = APIClient.shared

    // MARK: - Стада

    func listFlocks(limit: Int = 100, cursor: String? = nil) async throws -> FlockListDTO {
        var query: [String: String] = ["limit": String(limit)]
        if let cursor { query["cursor"] = cursor }

        return try await client.send(
            APIRequest(path: "flocks", query: query),
            as: FlockListDTO.self
        ).value
    }

    /// Все стада, страница за страницей.
    func listAllFlocks() async throws -> [FlockSummaryDTO] {
        var all: [FlockSummaryDTO] = []
        var cursor: String?

        repeat {
            let page = try await listFlocks(cursor: cursor)
            all.append(contentsOf: page.data)
            cursor = page.nextCursor
            // страховка от зацикливания при битом курсоре
            if all.count > 2000 { break }
        } while cursor != nil

        return all
    }

    func fetchFlock(_ id: UUID) async throws -> (flock: FlockDTO, version: Int) {
        let response = try await client.send(
            APIRequest(path: "flocks/\(id.uuidString)"),
            as: FlockDTO.self
        )
        return (response.value, response.etag ?? response.value.version)
    }

    /// `id` задаёт клиент: стадо появляется в списке сразу, ещё до ответа
    /// сервера, и идентификатор потом не приходится переклеивать.
    func createFlock(
        id: UUID,
        title: String,
        species: Species,
        count: Int,
        priority: Priority
    ) async throws -> (flock: FlockDTO, version: Int) {
        struct Body: Encodable {
            let id: UUID
            let title: String
            let species: Species
            let count: Int
            let priority: Priority
        }

        let body = Body(id: id, title: title, species: species, count: count, priority: priority)

        let response = try await client.send(
            APIRequest(
                method: "POST",
                path: "flocks",
                body: try APICoding.encoder.encode(body),
                // повтор при обрыве сети не создаст второе стадо
                idempotencyKey: id.uuidString
            ),
            as: FlockDTO.self
        )
        return (response.value, response.etag ?? response.value.version)
    }

    func updateFlockCore(
        _ id: UUID,
        payload: FlockCorePayload,
        version: Int?
    ) async throws -> (flock: FlockDTO, version: Int) {
        let response = try await client.send(
            APIRequest(
                method: "PATCH",
                path: "flocks/\(id.uuidString)",
                body: try APICoding.encoder.encode(payload),
                ifMatch: version
            ),
            as: FlockDTO.self
        )
        return (response.value, response.etag ?? response.value.version)
    }

    func deleteFlock(_ id: UUID) async throws {
        try await client.sendVoid(APIRequest(method: "DELETE", path: "flocks/\(id.uuidString)"))
    }

    func duplicateFlock(_ id: UUID) async throws -> (flock: FlockDTO, version: Int) {
        let response = try await client.send(
            APIRequest(
                method: "POST",
                path: "flocks/\(id.uuidString)/duplicate",
                idempotencyKey: UUID().uuidString
            ),
            as: FlockDTO.self
        )
        return (response.value, response.etag ?? response.value.version)
    }

    // MARK: - Секции

    /// PUT одной секции. Возвращает новую версию стада для последующих записей.
    @discardableResult
    func updateSection<T: Encodable>(
        _ section: FlockSection,
        of flockID: UUID,
        payload: T,
        version: Int?
    ) async throws -> Int? {
        let response = try await client.send(
            APIRequest(
                method: "PUT",
                path: "flocks/\(flockID.uuidString)/\(section.rawValue)",
                body: try APICoding.encoder.encode(payload),
                ifMatch: version
            ),
            // тело ответа — сама секция; здесь важен только ETag
            as: AnyDecodable.self
        )
        return response.etag
    }

    // MARK: - Записи о птицах

    func createBirdRecord(_ record: BirdRecord, in flockID: UUID) async throws -> BirdRecord {
        try await client.send(
            APIRequest(
                method: "POST",
                path: "flocks/\(flockID.uuidString)/birds",
                body: try APICoding.encoder.encode(BirdRecordPayload(record)),
                idempotencyKey: record.id.uuidString
            ),
            as: BirdRecord.self
        ).value
    }

    func updateBirdRecord(_ record: BirdRecord, in flockID: UUID) async throws -> BirdRecord {
        try await client.send(
            APIRequest(
                method: "PATCH",
                path: "flocks/\(flockID.uuidString)/birds/\(record.id.uuidString)",
                body: try APICoding.encoder.encode(BirdRecordPayload(record))
            ),
            as: BirdRecord.self
        ).value
    }

    func deleteBirdRecord(_ recordID: UUID, in flockID: UUID) async throws {
        try await client.sendVoid(
            APIRequest(method: "DELETE", path: "flocks/\(flockID.uuidString)/birds/\(recordID.uuidString)")
        )
    }

    /// Динамика веса по каждой птице — основа для графиков роста.
    func growth(for flockID: UUID) async throws -> [GrowthPointDTO] {
        try await client.send(
            APIRequest(path: "flocks/\(flockID.uuidString)/growth"),
            as: ListEnvelope<GrowthPointDTO>.self
        ).value.data
    }

    // MARK: - Напоминания

    func createReminder(_ reminder: FlockReminder, in flockID: UUID) async throws -> FlockReminder {
        try await client.send(
            APIRequest(
                method: "POST",
                path: "flocks/\(flockID.uuidString)/reminders",
                body: try APICoding.encoder.encode(ReminderPayload(reminder)),
                idempotencyKey: reminder.id.uuidString
            ),
            as: FlockReminder.self
        ).value
    }

    func updateReminder(_ reminder: FlockReminder, in flockID: UUID) async throws -> FlockReminder {
        try await client.send(
            APIRequest(
                method: "PATCH",
                path: "flocks/\(flockID.uuidString)/reminders/\(reminder.id.uuidString)",
                body: try APICoding.encoder.encode(ReminderPayload(reminder))
            ),
            as: FlockReminder.self
        ).value
    }

    func deleteReminder(_ reminderID: UUID, in flockID: UUID) async throws {
        try await client.sendVoid(
            APIRequest(method: "DELETE", path: "flocks/\(flockID.uuidString)/reminders/\(reminderID.uuidString)")
        )
    }

    // MARK: - План загона

    /// Доска заменяется целиком: перетаскивание объектов не должно порождать
    /// отдельный запрос на каждый кадр.
    func replaceLayout(_ items: [LayoutItem], in flockID: UUID) async throws -> [LayoutItem] {
        try await client.send(
            APIRequest(
                method: "PUT",
                path: "flocks/\(flockID.uuidString)/layout",
                body: try APICoding.encoder.encode(LayoutBoardPayload(items))
            ),
            as: ListEnvelope<LayoutItem>.self
        ).value.data
    }

    // MARK: - Фото

    func uploadPhoto(_ data: Data, for flockID: UUID) async throws {
        let boundary = "ratiterun-\(UUID().uuidString)"
        var body = Data()

        func append(_ string: String) {
            if let encoded = string.data(using: .utf8) { body.append(encoded) }
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"photo\"; filename=\"flock.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        _ = try await client.sendRaw(
            APIRequest(
                method: "POST",
                path: "flocks/\(flockID.uuidString)/photo",
                body: body,
                contentType: "multipart/form-data; boundary=\(boundary)",
                timeout: APIConfig.uploadTimeout
            )
        )
    }

    func fetchPhoto(for flockID: UUID) async throws -> Data {
        try await client.sendRaw(APIRequest(path: "flocks/\(flockID.uuidString)/photo"))
    }

    func deletePhoto(for flockID: UUID) async throws {
        try await client.sendVoid(APIRequest(method: "DELETE", path: "flocks/\(flockID.uuidString)/photo"))
    }

    // MARK: - Отчёты

    func createReport(
        for flockID: UUID,
        sections: [String],
        notes: String,
        currency: String,
        shareable: Bool
    ) async throws -> ReportDTO {
        try await client.send(
            APIRequest(
                method: "POST",
                path: "flocks/\(flockID.uuidString)/reports",
                body: try APICoding.encoder.encode(
                    ReportPayload(sections: sections, notes: notes, currency: currency, shareable: shareable)
                ),
                idempotencyKey: UUID().uuidString
            ),
            as: ReportDTO.self
        ).value
    }

    /// Скачивает PDF во временный файл — дальше его подхватывает ShareSheet.
    func downloadReportPDF(_ reportID: UUID) async throws -> URL {
        let data = try await client.sendRaw(APIRequest(path: "reports/\(reportID.uuidString)/pdf"))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RatiteRun-report-\(reportID.uuidString).pdf")
        try data.write(to: url, options: .atomic)

        return url
    }

    // MARK: - Справочники

    func speciesPresets(locale: String = "en") async throws -> [SpeciesPresetDTO] {
        try await client.send(
            APIRequest(path: "species-presets", query: ["locale": locale], requiresAuth: false),
            as: SpeciesPresetListDTO.self
        ).value.data
    }

    func contentBlock(_ slug: String, locale: String = "en") async throws -> String {
        try await client.send(
            APIRequest(path: "content/\(slug)", query: ["locale": locale], requiresAuth: false),
            as: ContentBlockDTO.self
        ).value.body
    }

    // MARK: - Поддержка

    struct SupportReceipt: Decodable {
        let id: UUID
        let createdAt: Date
        let message: String
    }

    /// Обращение в поддержку прямо из приложения — без выхода в браузер.
    func submitSupportRequest(
        name: String,
        email: String,
        subject: String,
        message: String,
        appVersion: String,
        deviceInfo: String
    ) async throws -> SupportReceipt {
        struct Body: Encodable {
            let name: String
            let email: String
            let subject: String
            let message: String
            let appVersion: String
            let deviceInfo: String
        }

        let body = Body(
            name: name,
            email: email,
            subject: subject,
            message: message,
            appVersion: appVersion,
            deviceInfo: deviceInfo
        )

        return try await client.send(
            APIRequest(
                method: "POST",
                path: "support",
                body: try APICoding.encoder.encode(body),
                idempotencyKey: UUID().uuidString
            ),
            as: SupportReceipt.self
        ).value
    }

    // MARK: - Оценка без сохранения

    /// Прогон движков по черновику — «что если» без записи в базу.
    func evaluateDraft(_ flock: Flock) async throws -> [String: AnyDecodable] {
        try await client.send(
            APIRequest(
                method: "POST",
                path: "evaluate",
                body: try APICoding.encoder.encode(EvaluateDraftPayload(flock)),
                requiresAuth: false
            ),
            as: [String: AnyDecodable].self
        ).value
    }
}

// MARK: - Вспомогательные типы

private struct EvaluateDraftPayload: Encodable {
    let species: Species
    let count: Int
    let housing: Housing
    let fencing: Fencing
    let feed: Feed
    let waterGrit: WaterGrit
    let handling: HandlingSafety
    let breeding: Breeding
    let rearing: ChickRearing
    let health: HealthLegs
    let predator: PredatorCheck
    let terrain: Terrain

    init(_ flock: Flock) {
        species = flock.species
        count = flock.count
        housing = flock.housing
        fencing = flock.fencing
        feed = flock.feed
        waterGrit = flock.waterGrit
        handling = flock.handling
        breeding = flock.breeding
        rearing = flock.rearing
        health = flock.health
        predator = flock.predator
        terrain = flock.terrain
    }
}

/// Заглушка, когда тело ответа не нужно, а важен только статус или ETag.
struct AnyDecodable: Decodable {
    let value: Any?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = nil
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyDecodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyDecodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = nil
        }
    }
}

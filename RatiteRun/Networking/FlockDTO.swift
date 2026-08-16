//
//  FlockDTO.swift
//  RatiteRun
//
//  Перевод между JSON сервера и доменной моделью Flock.
//
//  Модель Models.swift намеренно не тронута — иначе пришлось бы править все 18
//  экранов. Расхождения только в двух местах: фото приходит ссылкой, а не
//  Data-блобом, и разметка на сервере лежит одним объектом.
//

import Foundation

// MARK: - Сводка (список стад)

/// То, что отдаёт GET /flocks. Полные агрегаты в списке не гоняются.
struct FlockSummaryDTO: Decodable, Identifiable {
    let id: UUID
    let title: String
    let species: Species
    let count: Int
    let age: String
    let priority: Priority
    let status: FlockStatus
    let readinessPercent: Int
    let photoUrl: String?
    let version: Int
    let createdDate: Date
    let updatedAt: Date
}

struct FlockListDTO: Decodable {
    let data: [FlockSummaryDTO]
    let nextCursor: String?
}

// MARK: - Полный агрегат

struct FlockDTO: Decodable {
    let id: UUID
    let title: String
    let species: Species
    let count: Int
    let age: String
    let notes: String
    let priority: Priority
    let status: FlockStatus
    let createdDate: Date
    let version: Int
    let photoUrl: String?

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
    let kit: MaterialKit
    let signoff: Signoff
    let markup: MarkupDTO

    let birds: [BirdRecord]
    let reminders: [FlockReminder]
    let layout: [LayoutItem]

    struct MarkupDTO: Decodable {
        let strokes: [[CGPointCodable]]
        let caption: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            strokes = try container.decodeIfPresent([[CGPointCodable]].self, forKey: .strokes) ?? []
            caption = try container.decodeIfPresent(String.self, forKey: .caption) ?? ""
        }

        private enum CodingKeys: String, CodingKey { case strokes, caption }
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, species, count, age, notes, priority, status
        case createdDate, version, photoUrl
        case housing, fencing, feed, waterGrit, handling, breeding, rearing
        case health, predator, terrain, kit, signoff, markup
        case birds, reminders, layout
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id       = try c.decode(UUID.self, forKey: .id)
        title    = try c.decode(String.self, forKey: .title)
        species  = try c.decode(Species.self, forKey: .species)
        count    = try c.decode(Int.self, forKey: .count)
        age      = try c.decodeIfPresent(String.self, forKey: .age) ?? "Adult"
        notes    = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        priority = try c.decode(Priority.self, forKey: .priority)
        status   = try c.decode(FlockStatus.self, forKey: .status)

        createdDate = try c.decode(Date.self, forKey: .createdDate)
        version     = try c.decode(Int.self, forKey: .version)
        photoUrl    = try c.decodeIfPresent(String.self, forKey: .photoUrl)

        housing   = try c.decode(Housing.self, forKey: .housing)
        fencing   = try c.decode(Fencing.self, forKey: .fencing)
        feed      = try c.decode(Feed.self, forKey: .feed)
        waterGrit = try c.decode(WaterGrit.self, forKey: .waterGrit)
        handling  = try c.decode(HandlingSafety.self, forKey: .handling)
        breeding  = try c.decode(Breeding.self, forKey: .breeding)
        rearing   = try c.decode(ChickRearing.self, forKey: .rearing)
        health    = try c.decode(HealthLegs.self, forKey: .health)
        predator  = try c.decode(PredatorCheck.self, forKey: .predator)
        terrain   = try c.decode(Terrain.self, forKey: .terrain)
        kit       = try c.decode(MaterialKit.self, forKey: .kit)
        signoff   = try c.decode(Signoff.self, forKey: .signoff)
        markup    = try c.decode(MarkupDTO.self, forKey: .markup)

        birds     = try c.decodeIfPresent([BirdRecord].self, forKey: .birds) ?? []
        reminders = try c.decodeIfPresent([FlockReminder].self, forKey: .reminders) ?? []
        layout    = try c.decodeIfPresent([LayoutItem].self, forKey: .layout) ?? []
    }

    /// Фото передаётся отдельно: оно тянется своим запросом и кэшируется на диске.
    func toFlock(photo: Data? = nil) -> Flock {
        var flock = Flock()
        flock.id = id
        flock.title = title
        flock.species = species
        flock.count = count
        flock.age = age
        flock.notes = notes
        flock.photo = photo
        flock.priority = priority
        flock.status = status
        flock.createdDate = createdDate

        flock.housing = housing
        flock.fencing = fencing
        flock.feed = feed
        flock.waterGrit = waterGrit
        flock.handling = handling
        flock.breeding = breeding
        flock.rearing = rearing
        flock.health = health
        flock.predator = predator
        flock.terrain = terrain
        flock.kit = kit
        flock.signoff = signoff

        flock.birds = birds
        flock.reminders = reminders
        flock.layout = layout

        flock.markupStrokes = markup.strokes
        flock.markupCaption = markup.caption

        return flock
    }
}

// MARK: - Тела запросов

/// Верхнеуровневые поля стада: PATCH /flocks/{id}.
struct FlockCorePayload: Encodable {
    var title: String?
    var species: Species?
    var count: Int?
    var age: String?
    var notes: String?
    var priority: Priority?
    var status: FlockStatus?

    var isEmpty: Bool {
        title == nil && species == nil && count == nil && age == nil
            && notes == nil && priority == nil && status == nil
    }

    /// Разница между двумя стадами — только изменившиеся поля уезжают на сервер.
    static func diff(from old: Flock, to new: Flock) -> FlockCorePayload {
        var payload = FlockCorePayload()
        if old.title != new.title       { payload.title = new.title }
        if old.species != new.species   { payload.species = new.species }
        if old.count != new.count       { payload.count = new.count }
        if old.age != new.age           { payload.age = new.age }
        if old.notes != new.notes       { payload.notes = new.notes }
        if old.priority != new.priority { payload.priority = new.priority }
        if old.status != new.status     { payload.status = new.status }
        return payload
    }
}

/// Разметка фото — на сервере это одна секция.
struct MarkupPayload: Encodable {
    let strokes: [[CGPointCodable]]
    let caption: String
}

struct BirdRecordPayload: Encodable {
    let birdId: String
    let weightKg: Double
    let heightCm: Double
    let note: String
    let recordedAt: Date

    init(_ record: BirdRecord) {
        birdId = record.birdID
        weightKg = record.weightKg
        heightCm = record.heightCm
        note = record.note
        recordedAt = record.date
    }
}

struct ReminderPayload: Encodable {
    let kind: ReminderKind
    let title: String
    let hour: Int
    let minute: Int
    let enabled: Bool

    init(_ reminder: FlockReminder) {
        kind = reminder.kind
        title = reminder.title
        hour = reminder.hour
        minute = reminder.minute
        enabled = reminder.enabled
    }
}

struct LayoutBoardPayload: Encodable {
    let items: [Item]

    struct Item: Encodable {
        let kind: LayoutKind
        let x: Double
        let y: Double
    }

    init(_ items: [LayoutItem]) {
        self.items = items.map { Item(kind: $0.kind, x: $0.x, y: $0.y) }
    }
}

struct ReportPayload: Encodable {
    let sections: [String]
    let notes: String
    let currency: String
    let shareable: Bool
}

// MARK: - Ответы производных ресурсов

struct ReadinessDTO: Decodable {
    let percent: Int
    let band: String
    let parts: [String: Double]
}

struct ReportDTO: Decodable {
    let id: UUID
    let flockId: UUID
    let status: String
    let pdfUrl: String
    let shareUrl: String?
    let createdAt: Date
    let expiresAt: Date?
}

struct GrowthPointDTO: Decodable {
    let birdId: String
    let points: Int
    let firstAt: Date
    let lastAt: Date
    let minWeightKg: Double
    let maxWeightKg: Double
    let gainKg: Double
}

struct SpeciesPresetDTO: Decodable {
    let species: Species
    let label: String
    let adultMassKg: Double
    let spacePerBirdM2: Double
    let minSpacePerBirdM2: Double
    let recFenceHeightM: Double
    let minFenceHeightM: Double
    let recFenceStrength: Int
    let incubationDays: Int
    let eggMassG: Double
    let kickRiskLevel: Int
    let kickRiskLabel: String
    let targetProteinPct: Double
    let gritImportance: Int
    let legIssueRisk: Int
    let hatchWindowDays: Int
}

struct SpeciesPresetListDTO: Decodable {
    let data: [SpeciesPresetDTO]
    let locale: String
    let version: String
}

struct ContentBlockDTO: Decodable {
    let slug: String
    let locale: String
    let body: String
}

/// Обёртка для эндпоинтов вида { "data": [...] }.
struct ListEnvelope<T: Decodable>: Decodable {
    let data: [T]
}

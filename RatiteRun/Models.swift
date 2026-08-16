//
//  Models.swift
//  RatiteRun
//
//  All Codable data models for the app.
//

import Foundation
import SwiftUI

// MARK: - Enums

enum Species: String, Codable, CaseIterable, Identifiable {
    case ostrich, emu, rhea
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ostrich: return "Ostrich"
        case .emu:     return "Emu"
        case .rhea:    return "Rhea"
        }
    }
    var glyph: String {
        // valid iOS-14 SF Symbols only
        switch self {
        case .ostrich: return "bird.fill"
        case .emu:     return "bird.fill"
        case .rhea:    return "hare.fill"
        }
    }
    /// Relative visual size factor for onboarding/hero art.
    var sizeFactor: CGFloat {
        switch self {
        case .ostrich: return 1.0
        case .emu:     return 0.72
        case .rhea:    return 0.58
        }
    }
}

enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var label: String { self == .metric ? "Metric (m, m²)" : "Imperial (ft, ft²)" }
    var lengthUnit: String { self == .metric ? "m" : "ft" }
    var areaUnit: String { self == .metric ? "m²" : "ft²" }
    /// factor to convert stored metric value → display
    var lengthFactor: Double { self == .metric ? 1 : 3.28084 }
    var areaFactor: Double { self == .metric ? 1 : 10.7639 }
}

enum Priority: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .low:    return Palette.savanna
        case .medium: return Palette.primary
        case .high:   return Palette.danger
        }
    }
}

enum FlockStatus: String, Codable, CaseIterable, Identifiable {
    case setup, active, attention, danger
    var id: String { rawValue }
    var label: String {
        switch self {
        case .setup:     return "In setup"
        case .active:    return "Active"
        case .attention: return "Needs attention"
        case .danger:    return "Alert"
        }
    }
    var color: Color {
        switch self {
        case .setup:     return Palette.working
        case .active:    return Palette.norm
        case .attention: return Palette.attention
        case .danger:    return Palette.danger
        }
    }
}

enum DietType: String, Codable, CaseIterable, Identifiable {
    case grazing, formulated, mixed
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum UseFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, seasonal
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum GroupSize: String, Codable, CaseIterable, Identifiable {
    case pair, smallGroup, herd
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pair: return "Pair"
        case .smallGroup: return "Small Group"
        case .herd: return "Herd"
        }
    }
    var defaultCount: Int {
        switch self {
        case .pair: return 2
        case .smallGroup: return 5
        case .herd: return 12
        }
    }
}

enum TerrainType: String, Codable, CaseIterable, Identifiable {
    case flat, sloped, sandy, grassland, mixed
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Verdict: String, Codable {
    case good, watch, alert
    var color: Color {
        switch self {
        case .good:  return Palette.norm
        case .watch: return Palette.attention
        case .alert: return Palette.danger
        }
    }
    var symbol: String {
        switch self {
        case .good:  return "checkmark.seal.fill"
        case .watch: return "exclamationmark.triangle.fill"
        case .alert: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Nested value models

struct Housing: Codable, Hashable {
    var spacePerBird: Double = 0     // stored metric m²
    var shelterArea: Double = 0      // m²
    var paddockSize: Double = 0      // m²
    var terrain: TerrainType = .grassland
    var hasShelter: Bool = false
}

struct Fencing: Codable, Hashable {
    var height: Double = 0           // stored metric m
    var strength: Int = 3            // 1...5
    var escapeRiskNote: String = ""
    var perimeterSecured: Bool = false
}

struct Feed: Codable, Hashable {
    var dietType: DietType = .mixed
    var grazingRatio: Double = 40    // % of diet from grazing
    var proteinPct: Double = 16
    var scheduleNote: String = "Twice daily"
}

struct WaterGrit: Codable, Hashable {
    var waterProvided: Bool = true
    var gritProvided: Bool = false
    var gritGramsPerBird: Double = 0
    var mineralsProvided: Bool = false
    var notes: String = ""
}

struct HandlingSafety: Codable, Hashable {
    var neverCorner: Bool = true
    var approachFromSide: Bool = true
    var useHood: Bool = false
    var trainedHandlersOnly: Bool = false
    var restraintPlan: String = ""
}

struct Breeding: Codable, Hashable {
    var pairs: Int = 0
    var largeEggs: Int = 0
    var incubationNote: String = ""
    var season: String = "Spring"
    var startDate: Date = Date()
}

struct ChickRearing: Codable, Hashable {
    var chicks: Int = 0
    var brooderReady: Bool = false
    var legIssuesFlagged: Bool = false
    var chickDietNote: String = ""
}

struct HealthLegs: Codable, Hashable {
    var legJointScore: Int = 4       // 1...5 (5 = best)
    var ailmentsNote: String = ""
    var vetContact: String = ""
    var lastCheck: Date = Date()
}

struct PredatorCheck: Codable, Hashable {
    var fenceIntegrity: Int = 4      // 1...5
    var predatorsSeen: String = ""
    var securityNote: String = ""
    var lastChecked: Date = Date()
}

struct Terrain: Codable, Hashable {
    var dustBathing: Bool = false
    var roomToRun: Bool = true
    var terrainNote: String = ""
}

struct BirdRecord: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var birdID: String = ""
    var weightKg: Double = 0
    var heightCm: Double = 0
    var note: String = ""
    var date: Date = Date()
}

struct MaterialKit: Codable, Hashable {
    var fenceMeters: Double = 0
    var feeders: Int = 0
    var waterers: Int = 0
    var gritKg: Double = 0
    var shelterM2: Double = 0
    var safetyKitNote: String = "Hood, panel board, gloves"
}

struct LayoutItem: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: LayoutKind
    var x: Double   // normalized 0...1
    var y: Double
}

enum LayoutKind: String, Codable, CaseIterable, Identifiable {
    case paddock, shelter, feeder, waterer, gate, dustBath
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dustBath: return "Dust Bath"
        default: return rawValue.capitalized
        }
    }
    var symbol: String {
        switch self {
        case .paddock:  return "square.dashed"
        case .shelter:  return "house.fill"
        case .feeder:   return "tray.fill"
        case .waterer:  return "drop.fill"
        case .gate:     return "door.left.hand.open"
        case .dustBath: return "circle.grid.cross.fill"
        }
    }
    var color: Color {
        switch self {
        case .paddock:  return Palette.savanna
        case .shelter:  return Palette.primary
        case .feeder:   return Palette.action
        case .waterer:  return Color(hex: "#4DA3F0")
        case .gate:     return Palette.primaryActive
        case .dustBath: return Palette.attention
        }
    }
}

struct FlockReminder: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var kind: ReminderKind
    var hour: Int = 8
    var minute: Int = 0
    var enabled: Bool = true
}

enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case feedGrit, water, fenceCheck, legHealth
    var id: String { rawValue }
    var label: String {
        switch self {
        case .feedGrit:  return "Feed & Grit"
        case .water:     return "Water"
        case .fenceCheck: return "Fence Check"
        case .legHealth: return "Leg / Health Inspection"
        }
    }
    var symbol: String {
        switch self {
        case .feedGrit:  return "leaf.fill"
        case .water:     return "drop.fill"
        case .fenceCheck: return "shield.fill"
        case .legHealth: return "cross.case.fill"
        }
    }
}

struct Signoff: Codable, Hashable {
    var reviewer: String = ""
    var signatureStrokes: [[CGPointCodable]] = []
    var date: Date = Date()
    var approved: Bool = false
}

func mediumDate(_ date: Date) -> String {
    let f = DateFormatter(); f.dateStyle = .medium
    return f.string(from: date)
}

struct CGPointCodable: Codable, Hashable {
    var x: CGFloat
    var y: CGFloat
    var point: CGPoint { CGPoint(x: x, y: y) }
    init(_ p: CGPoint) { x = p.x; y = p.y }
}

// MARK: - Flock

struct Flock: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String = "New Flock"
    var species: Species = .emu
    var count: Int = 2
    var age: String = "Adult"
    var notes: String = ""
    var photo: Data? = nil
    var priority: Priority = .medium
    var status: FlockStatus = .setup
    var createdDate: Date = Date()

    var housing = Housing()
    var fencing = Fencing()
    var feed = Feed()
    var waterGrit = WaterGrit()
    var handling = HandlingSafety()
    var breeding = Breeding()
    var rearing = ChickRearing()
    var health = HealthLegs()
    var predator = PredatorCheck()
    var terrain = Terrain()
    var birds: [BirdRecord] = []
    var kit = MaterialKit()
    var layout: [LayoutItem] = []
    var reminders: [FlockReminder] = []
    var signoff = Signoff()

    // photo markup
    var markupStrokes: [[CGPointCodable]] = []
    var markupCaption: String = ""
}

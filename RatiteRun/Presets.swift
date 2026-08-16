//
//  Presets.swift
//  RatiteRun
//
//  Per-species reference data. Educational approximations — a specialist
//  vet / keeper should confirm figures for a specific holding.
//

import Foundation

struct SpeciesPreset {
    let species: Species
    let adultMassKg: Double
    let spacePerBirdM2: Double      // recommended area per bird
    let minSpacePerBirdM2: Double   // absolute floor
    let recFenceHeightM: Double     // recommended fence height
    let minFenceHeightM: Double
    let recFenceStrength: Int       // 1...5
    let incubationDays: Int
    let eggMassG: Double
    let kickRiskLevel: Int          // 1(low)...5(extreme)
    let targetProteinPct: Double
    let gritImportance: Int         // 1...5
    let legIssueRisk: Int           // 1...5
    let hatchWindowDays: Int        // spread of hatch

    var kickRiskLabel: String {
        switch kickRiskLevel {
        case 5: return "Extreme"
        case 4: return "High"
        case 3: return "Moderate"
        default: return "Low"
        }
    }
}

enum Presets {
    static let all: [Species: SpeciesPreset] = [
        .ostrich: SpeciesPreset(
            species: .ostrich, adultMassKg: 115,
            spacePerBirdM2: 300, minSpacePerBirdM2: 250,
            recFenceHeightM: 2.0, minFenceHeightM: 1.8, recFenceStrength: 5,
            incubationDays: 42, eggMassG: 1500, kickRiskLevel: 5,
            targetProteinPct: 16, gritImportance: 5, legIssueRisk: 5,
            hatchWindowDays: 4),
        .emu: SpeciesPreset(
            species: .emu, adultMassKg: 40,
            spacePerBirdM2: 200, minSpacePerBirdM2: 150,
            recFenceHeightM: 1.8, minFenceHeightM: 1.5, recFenceStrength: 4,
            incubationDays: 52, eggMassG: 600, kickRiskLevel: 4,
            targetProteinPct: 17, gritImportance: 4, legIssueRisk: 3,
            hatchWindowDays: 6),
        .rhea: SpeciesPreset(
            species: .rhea, adultMassKg: 25,
            spacePerBirdM2: 130, minSpacePerBirdM2: 100,
            recFenceHeightM: 1.5, minFenceHeightM: 1.2, recFenceStrength: 3,
            incubationDays: 38, eggMassG: 600, kickRiskLevel: 4,
            targetProteinPct: 18, gritImportance: 4, legIssueRisk: 3,
            hatchWindowDays: 5)
    ]

    static func preset(for species: Species) -> SpeciesPreset {
        all[species] ?? all[.emu]!
    }
}

let ratiteDisclaimer = "Ratites are large, powerful birds and can be dangerous — a forward kick can cause serious injury. Follow safe handling and never corner a bird. Figures are estimates for planning only; consult a specialist ratite vet for health decisions."

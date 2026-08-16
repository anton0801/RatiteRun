//
//  Engines.swift
//  RatiteRun
//
//  Pure calculation core: space, fencing, diet, grit/water, handling safety,
//  breeding, health, materials, cost, and overall readiness.
//  All static & side-effect-free so they can be unit-checked in isolation.
//

import Foundation
import SwiftUI

// MARK: - Result types

struct EngineResult {
    var verdict: Verdict
    var headline: String
    var detail: String
    var score: Double        // 0...1 for readiness weighting
}

// MARK: - Space

enum SpaceEngine {
    /// Returns per-bird area, ratio vs recommended, and a verdict.
    static func evaluate(_ flock: Flock) -> (perBird: Double, requiredTotal: Double, ratio: Double, result: EngineResult) {
        let p = Presets.preset(for: flock.species)
        let count = max(1, flock.count)
        let paddock = flock.housing.paddockSize
        let requiredTotal = p.spacePerBirdM2 * Double(count)
        let perBird = paddock / Double(count)
        let ratio = requiredTotal > 0 ? paddock / requiredTotal : 0

        let verdict: Verdict
        let headline: String
        if perBird >= p.spacePerBirdM2 {
            verdict = .good
            headline = "Ample space"
        } else if perBird >= p.minSpacePerBirdM2 {
            verdict = .watch
            headline = "Adequate — near minimum"
        } else {
            verdict = .alert
            headline = "Cramped for ratites"
        }
        let detail = String(format: "%.0f m²/bird provided vs %.0f m² recommended (%.0f m² floor). Ratites run — big space matters.",
                            perBird, p.spacePerBirdM2, p.minSpacePerBirdM2)
        let score = min(1, max(0, perBird / p.spacePerBirdM2))
        return (perBird, requiredTotal, ratio,
                EngineResult(verdict: verdict, headline: headline, detail: detail, score: score))
    }
}

// MARK: - Fencing

enum FencingEngine {
    static func evaluate(_ flock: Flock) -> EngineResult {
        let p = Presets.preset(for: flock.species)
        let h = flock.fencing.height
        let strength = flock.fencing.strength

        var verdict: Verdict = .good
        var issues: [String] = []

        if h < p.minFenceHeightM {
            verdict = .alert
            issues.append(String(format: "Too low — needs ≥ %.1f m", p.recFenceHeightM))
        } else if h < p.recFenceHeightM {
            verdict = .watch
            issues.append(String(format: "Below recommended %.1f m", p.recFenceHeightM))
        }
        if strength < p.recFenceStrength - 1 {
            verdict = (verdict == .alert) ? .alert : .watch
            issues.append("Strengthen posts/mesh for this species")
        }
        if !flock.fencing.perimeterSecured {
            issues.append("Perimeter not confirmed secured")
            if verdict == .good { verdict = .watch }
        }

        let headline: String
        switch verdict {
        case .good:  headline = "Fence fit for species"
        case .watch: headline = "Fence needs attention"
        case .alert: headline = "Escape / injury risk"
        }
        let detail = issues.isEmpty
            ? String(format: "%.1f m high, strength %d/5 — meets %@ guidance.", h, strength, p.species.label)
            : issues.joined(separator: " · ")
        // score: height ratio blended with strength ratio
        let hScore = p.recFenceHeightM > 0 ? min(1, h / p.recFenceHeightM) : 0
        let sScore = Double(strength) / 5.0
        let score = (hScore * 0.65 + sScore * 0.35)
        return EngineResult(verdict: verdict, headline: headline, detail: detail, score: score)
    }
}

// MARK: - Diet

enum DietEngine {
    static func evaluate(_ flock: Flock) -> EngineResult {
        let p = Presets.preset(for: flock.species)
        let protein = flock.feed.proteinPct
        let type = flock.feed.dietType

        var verdict: Verdict = .good
        var notes: [String] = []

        // protein window: target ± band
        let lower = p.targetProteinPct - 4
        let upper = p.targetProteinPct + 6
        if protein < lower {
            verdict = .alert
            notes.append(String(format: "Protein low (%.0f%% vs ~%.0f%% target)", protein, p.targetProteinPct))
        } else if protein > upper {
            verdict = .watch
            notes.append("Protein high — risk of leg/growth issues")
        }
        if type == .grazing && protein < p.targetProteinPct {
            verdict = (verdict == .alert ? .alert : .watch)
            notes.append("Grazing alone rarely meets ratite protein — supplement")
        }

        let headline: String
        switch verdict {
        case .good:  headline = "Ratite-appropriate diet"
        case .watch: headline = "Diet needs tuning"
        case .alert: headline = "Diet not meeting needs"
        }
        let detail = notes.isEmpty
            ? String(format: "%@ diet at %.0f%% protein, %.0f%% grazing — suited to %@.",
                     type.label, protein, flock.feed.grazingRatio, p.species.label)
            : notes.joined(separator: " · ")
        // score: closeness to target protein
        let diff = abs(protein - p.targetProteinPct)
        let score = max(0, 1 - diff / 12)
        return EngineResult(verdict: verdict, headline: headline, detail: detail, score: score)
    }
}

// MARK: - Grit & Water

enum GritWaterEngine {
    static func evaluate(_ flock: Flock) -> EngineResult {
        let p = Presets.preset(for: flock.species)
        let g = flock.waterGrit
        var verdict: Verdict = .good
        var notes: [String] = []
        var score = 1.0

        if !g.waterProvided {
            verdict = .alert
            notes.append("No clean water source set")
            score -= 0.5
        }
        if !g.gritProvided {
            verdict = (verdict == .alert ? .alert : .watch)
            notes.append("No grit — gizzard can't grind feed")
            score -= 0.35
        } else if g.gritGramsPerBird <= 0 {
            verdict = (verdict == .alert ? .alert : .watch)
            notes.append("Grit amount not logged")
            score -= 0.1
        }
        if !g.mineralsProvided {
            if verdict == .good { verdict = .watch }
            notes.append("Minerals not supplied")
            score -= 0.15
        }
        _ = p // species grit importance already reflected in presets
        let headline: String
        switch verdict {
        case .good:  headline = "Water, grit & minerals set"
        case .watch: headline = "Digestion support incomplete"
        case .alert: headline = "Missing water or grit"
        }
        let detail = notes.isEmpty
            ? String(format: "Grit %.0f g/bird provided — stones grind coarse feed in the gizzard.", g.gritGramsPerBird)
            : notes.joined(separator: " · ")
        return EngineResult(verdict: verdict, headline: headline, detail: detail, score: max(0, score))
    }
}

// MARK: - Handling Safety

enum HandlingSafetyEngine {
    static func evaluate(_ flock: Flock) -> (score: Int, result: EngineResult, rules: [String]) {
        let p = Presets.preset(for: flock.species)
        let h = flock.handling
        var score = 100

        // base risk from species kick level
        score -= (p.kickRiskLevel - 1) * 6   // ostrich starts lower

        if !h.neverCorner { score -= 30 }
        if !h.approachFromSide { score -= 15 }
        if !h.trainedHandlersOnly { score -= 12 }
        if p.kickRiskLevel >= 4 && !h.useHood { score -= 8 }
        if h.restraintPlan.trimmingCharacters(in: .whitespaces).isEmpty { score -= 8 }

        score = max(5, min(100, score))

        let verdict: Verdict = score >= 75 ? .good : (score >= 50 ? .watch : .alert)
        let headline: String
        switch verdict {
        case .good:  headline = "Handling protocols solid"
        case .watch: headline = "Tighten handling safety"
        case .alert: headline = "High handling risk"
        }
        var rules: [String] = [
            "Kick risk for \(p.species.label): \(p.kickRiskLabel) — the forward kick is the danger.",
            "Never corner the bird — always leave an escape route.",
            "Approach from the side, not head-on."
        ]
        if p.kickRiskLevel >= 4 { rules.append("Use a hood to calm before restraint.") }
        rules.append("Only trained handlers should restrain.")

        let detail = "Safety score \(score)/100 for \(p.species.label). \(verdict == .good ? "Protocols in place." : "Enable the safety rules below.")"
        return (score, EngineResult(verdict: verdict, headline: headline, detail: detail, score: Double(score) / 100), rules)
    }
}

// MARK: - Breeding

enum BreedingEngine {
    static func evaluate(_ flock: Flock) -> (hatchDate: Date, window: String, result: EngineResult) {
        let p = Presets.preset(for: flock.species)
        let start = flock.breeding.startDate
        let hatch = Calendar.current.date(byAdding: .day, value: p.incubationDays, to: start) ?? start
        let window = "±\(p.hatchWindowDays) days"

        let pairs = flock.breeding.pairs
        let verdict: Verdict = pairs > 0 ? .good : .watch
        let headline = pairs > 0 ? "Breeding tracked" : "No breeding pairs yet"
        let detail = String(format: "%@ eggs incubate ~%d days (egg ≈ %.0f g). %d pair(s), %d large egg(s) logged.",
                            p.species.label, p.incubationDays, p.eggMassG, pairs, flock.breeding.largeEggs)
        let score = pairs > 0 ? 1.0 : 0.5
        return (hatch, window, EngineResult(verdict: verdict, headline: headline, detail: detail, score: score))
    }
}

// MARK: - Health & Legs

enum HealthLegsEngine {
    static func evaluate(_ flock: Flock) -> EngineResult {
        let p = Presets.preset(for: flock.species)
        let s = flock.health.legJointScore    // 1...5
        var verdict: Verdict = s >= 4 ? .good : (s >= 3 ? .watch : .alert)
        var notes: [String] = []
        if p.legIssueRisk >= 4 {
            notes.append("\(p.species.label) chicks are prone to leg/joint problems — watch footing & protein.")
            if verdict == .good { verdict = .watch }
        }
        if !flock.health.ailmentsNote.isEmpty {
            notes.append("Logged: \(flock.health.ailmentsNote)")
        }
        let headline: String
        switch verdict {
        case .good:  headline = "Legs & joints healthy"
        case .watch: headline = "Monitor legs closely"
        case .alert: headline = "Leg/health concern — call vet"
        }
        let detail = notes.isEmpty
            ? "Leg/joint score \(s)/5. Keep footing firm and diet balanced."
            : notes.joined(separator: " · ")
        return EngineResult(verdict: verdict, headline: headline, detail: detail, score: Double(s) / 5.0)
    }
}

// MARK: - Materials

enum MaterialEngine {
    static func compute(_ flock: Flock) -> MaterialKit {
        let p = Presets.preset(for: flock.species)
        let count = max(1, flock.count)
        let area = max(flock.housing.paddockSize, p.spacePerBirdM2 * Double(count))
        let side = sqrt(area)
        let perimeter = 4 * side
        let feeders = max(1, Int(ceil(Double(count) / 4.0)))
        let waterers = max(1, Int(ceil(Double(count) / 5.0)))
        let gritKg = Double(count) * 0.5   // ~500 g/bird stock
        let shelter = flock.housing.shelterArea > 0
            ? flock.housing.shelterArea
            : Double(count) * (p.adultMassKg > 80 ? 4 : 2.5)
        return MaterialKit(
            fenceMeters: perimeter.rounded(),
            feeders: feeders,
            waterers: waterers,
            gritKg: (gritKg * 10).rounded() / 10,
            shelterM2: shelter.rounded(),
            safetyKitNote: p.kickRiskLevel >= 4 ? "Hood, panel board, gloves, first-aid" : "Panel board, gloves, first-aid")
    }
}

// MARK: - Cost

struct CostBreakdown {
    var fence: Double
    var shelter: Double
    var feeders: Double
    var grit: Double
    var labour: Double
    var total: Double { fence + shelter + feeders + grit + labour }
}

enum CostEngine {
    // simple unit-rate estimate (currency-agnostic)
    static func estimate(_ kit: MaterialKit, fenceRate: Double = 35, shelterRate: Double = 60,
                         feederRate: Double = 45, gritRate: Double = 3, labourRate: Double = 120) -> CostBreakdown {
        CostBreakdown(
            fence: kit.fenceMeters * fenceRate,
            shelter: kit.shelterM2 * shelterRate,
            feeders: Double(kit.feeders + kit.waterers) * feederRate,
            grit: kit.gritKg * gritRate,
            labour: labourRate * 2)
    }
}

// MARK: - Readiness (overall)

struct Readiness {
    var percent: Int
    var band: String
    var color: Color
    var parts: [(String, Double)]   // (label, 0...1)
}

enum ReadinessEngine {
    static func evaluate(_ flock: Flock) -> Readiness {
        let space = SpaceEngine.evaluate(flock).result.score
        let fence = FencingEngine.evaluate(flock).score
        let diet = DietEngine.evaluate(flock).score
        let gritWater = GritWaterEngine.evaluate(flock).score
        let safety = HandlingSafetyEngine.evaluate(flock).result.score
        let health = HealthLegsEngine.evaluate(flock).score

        let weighted = space * 0.25 + fence * 0.20 + diet * 0.20
                     + gritWater * 0.10 + safety * 0.15 + health * 0.10
        let pct = Int((weighted * 100).rounded())

        let band: String
        let color: Color
        switch pct {
        case 80...:   band = "Ready"; color = Palette.norm
        case 55..<80: band = "Getting there"; color = Palette.primary
        case 35..<55: band = "Needs work"; color = Palette.attention
        default:      band = "Not ready"; color = Palette.danger
        }
        return Readiness(percent: pct, band: band, color: color, parts: [
            ("Space", space), ("Fencing", fence), ("Diet", diet),
            ("Grit/Water", gritWater), ("Safety", safety), ("Health", health)
        ])
    }
}

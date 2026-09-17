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

@MainActor
final class Sprinter: ObservableObject {

    @Published private(set) var lap: Lap = .warmup
    @Published private(set) var offline = false

    private var bib = Bib()
    private var settled = false
    private var busy = false
    private var live = false
    private var clock: Task<Void, Never>?

    func ignite() {
        prime()
        clock = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.scratch()
        }
        run()
    }

    func feed(_ pour: [String: String]) {
        prime()
        bib.raw.merge(pour) { _, fresh in fresh }
        Locker.write(bib)
        run()
    }

    func pair(_ pour: [String: String]) {
        prime()
        for (key, value) in pour where bib.links[key] == nil { bib.links[key] = value }
        Locker.write(bib)
    }

    func go() {
        prime()
        Task { [weak self] in
            guard let self = self else { return }
            let granted = await Marshal.ready()
            self.bib.consentGrant = granted
            self.bib.consentDeny = !granted
            self.bib.consentAt = Date()
            Locker.write(self.bib)
            self.lap = .run
        }
    }

    func sit() {
        prime()
        bib.consentAt = Date()
        Locker.write(bib)
        lap = .run
    }

    func power(_ up: Bool) {
        if !up { offline = true }
    }

    private func run() {
        guard !settled, !busy else { return }

        if let hot = pending {
            place(hot)
            return
        }
        guard bib.rolling else { return }

        busy = true
        Task { [weak self] in
            guard let self = self else { return }

            if self.bib.needsWarmup {
                self.bib.refetched = true
                Locker.write(self.bib)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let fresh = await Starter.probe()
                if !fresh.isEmpty {
                    var pooled = fresh
                    for (key, value) in self.bib.links where pooled[key] == nil { pooled[key] = value }
                    self.bib.raw = pooled
                    Locker.write(self.bib)
                }
            }

            let finish = await Starter.race(self.bib.raw)
            self.busy = false
            switch finish {
            case .placed(let url): self.place(url)
            case .denied:
                if let saved = UserDefaults.standard.string(forKey: Lane.routeURL), saved.isEmpty == false {
                    self.resume()
                } else if let saved = self.bib.routeURL, saved.isEmpty == false {
                    UserDefaults.standard.set(saved, forKey: Lane.routeURL)
                    self.resume()
                } else {
                    self.scratch()
                }
            case .missed:
                if let saved = UserDefaults.standard.string(forKey: Lane.routeURL), saved.isEmpty == false {
                    self.resume()
                } else if let saved = self.bib.routeURL, saved.isEmpty == false {
                    UserDefaults.standard.set(saved, forKey: Lane.routeURL)
                    self.resume()
                } else {
                    self.scratch()
                }
            }
        }
    }

    private func place(_ url: String) {
        guard latch() else { return }
        let ask = bib.askable
        bib.routeURL = url
        bib.routeMode = "Active"
        bib.virgin = false
        Locker.write(bib)
        Locker.mark(url)
        Locker.flag()
        UserDefaults.standard.removeObject(forKey: Lane.pushURL)
        lap = ask ? .cue : .run
    }

    private func scratch() {
        guard latch() else { return }
        lap = .scratch
    }

    private func resume() {
        guard latch() else { return }
        lap = .run
    }

    private func latch() -> Bool {
        guard !settled else { return false }
        settled = true
        clock?.cancel()
        return true
    }

    private func prime() {
        guard !live else { return }
        live = true
        bib = Locker.read()
    }

    private var pending: String? {
        let value = UserDefaults.standard.string(forKey: Lane.pushURL) ?? ""
        return value.isEmpty ? nil : value
    }
}

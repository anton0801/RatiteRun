//
//  ReportGenerator.swift
//  RatiteRun
//
//  PDF report + JSON export, and a UIActivityViewController share sheet.
//

import SwiftUI
import UIKit

enum ReportSection: String, CaseIterable, Identifiable {
    case spaceFence = "Space & Fencing"
    case diet = "Diet & Grit"
    case safety = "Handling Safety"
    case health = "Health & Legs"
    case breeding = "Breeding & Eggs"
    var id: String { rawValue }
}

enum ReportGenerator {

    static func makePDF(flock: Flock, sections: Set<ReportSection>, currency: String, notes: String) -> URL? {
        let pageW: CGFloat = 612, pageH: CGFloat = 792
        let bounds = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RatiteRun-\(flock.title.replacingOccurrences(of: " ", with: "_")).pdf")

        let readiness = ReadinessEngine.evaluate(flock)
        let space = SpaceEngine.evaluate(flock)
        let fence = FencingEngine.evaluate(flock)
        let diet = DietEngine.evaluate(flock)
        let grit = GritWaterEngine.evaluate(flock)
        let safety = HandlingSafetyEngine.evaluate(flock)
        let health = HealthLegsEngine.evaluate(flock)
        let breeding = BreedingEngine.evaluate(flock)
        let cost = CostEngine.estimate(flock.kit)

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y: CGFloat = 48
                let margin: CGFloat = 48

                func text(_ s: String, size: CGFloat, weight: UIFont.Weight, color: UIColor = UIColor(Palette.textPrimary), indent: CGFloat = 0) {
                    let font = UIFont.systemFont(ofSize: size, weight: weight)
                    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                    let rect = CGRect(x: margin + indent, y: y, width: pageW - margin*2 - indent, height: 1000)
                    let bounding = (s as NSString).boundingRect(with: CGSize(width: rect.width, height: 1000),
                        options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
                    (s as NSString).draw(in: CGRect(x: rect.minX, y: y, width: rect.width, height: bounding.height + 4), withAttributes: attrs)
                    y += bounding.height + 8
                    if y > pageH - 80 { ctx.beginPage(); y = 48 }
                }
                func rule() {
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: margin, y: y))
                    path.addLine(to: CGPoint(x: pageW - margin, y: y))
                    UIColor(Palette.border).setStroke()
                    path.lineWidth = 1; path.stroke()
                    y += 14
                }

                text("Ratite Run — Flock Report", size: 24, weight: .bold, color: UIColor(Palette.primaryActive))
                text(flock.title, size: 16, weight: .semibold)
                let df = DateFormatter(); df.dateStyle = .medium
                text("\(flock.species.label) · \(flock.count) birds · \(flock.age) · \(df.string(from: Date()))",
                     size: 12, weight: .regular, color: UIColor(Palette.textSecondary))
                rule()

                text("Overall readiness: \(readiness.percent)% — \(readiness.band)", size: 15, weight: .bold,
                     color: UIColor(readiness.color))
                y += 4

                if sections.contains(.spaceFence) {
                    text("Space & Fencing", size: 16, weight: .bold, color: UIColor(Palette.primaryActive))
                    text("• Space: \(space.result.headline). " + space.result.detail, size: 12, weight: .regular)
                    text("• Fencing: \(fence.headline). " + fence.detail, size: 12, weight: .regular)
                    rule()
                }
                if sections.contains(.diet) {
                    text("Diet & Grit", size: 16, weight: .bold, color: UIColor(Palette.primaryActive))
                    text("• Diet: \(diet.headline). " + diet.detail, size: 12, weight: .regular)
                    text("• Grit/Water: \(grit.headline). " + grit.detail, size: 12, weight: .regular)
                    rule()
                }
                if sections.contains(.safety) {
                    text("Handling Safety", size: 16, weight: .bold, color: UIColor(Palette.primaryActive))
                    text("• \(safety.result.headline) — score \(safety.score)/100", size: 12, weight: .regular)
                    for r in safety.rules { text("• " + r, size: 11, weight: .regular, color: UIColor(Palette.textSecondary)) }
                    rule()
                }
                if sections.contains(.health) {
                    text("Health & Legs", size: 16, weight: .bold, color: UIColor(Palette.primaryActive))
                    text("• \(health.headline). " + health.detail, size: 12, weight: .regular)
                    rule()
                }
                if sections.contains(.breeding) {
                    text("Breeding & Eggs", size: 16, weight: .bold, color: UIColor(Palette.primaryActive))
                    text("• \(breeding.result.headline). " + breeding.result.detail, size: 12, weight: .regular)
                    text("• Expected hatch: \(df.string(from: breeding.hatchDate)) (\(breeding.window))", size: 12, weight: .regular)
                    rule()
                }

                text("Estimated kit cost", size: 16, weight: .bold, color: UIColor(Palette.primaryActive))
                text(String(format: "• Fence %.0f m · Shelter %.0f m² · %d feeders / %d waterers · Grit %.1f kg",
                            flock.kit.fenceMeters, flock.kit.shelterM2, flock.kit.feeders, flock.kit.waterers, flock.kit.gritKg),
                     size: 12, weight: .regular)
                text(String(format: "• Total ≈ %@%.0f", currency, cost.total), size: 13, weight: .semibold, color: UIColor(Palette.norm))

                if !notes.isEmpty {
                    rule()
                    text("Notes", size: 14, weight: .bold)
                    text(notes, size: 12, weight: .regular, color: UIColor(Palette.textSecondary))
                }
                rule()
                text(ratiteDisclaimer, size: 10, weight: .regular, color: UIColor(Palette.textDisabled))
            }
            return url
        } catch {
            return nil
        }
    }

    static func exportJSON(_ flocks: [Flock]) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(flocks) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RatiteRun-backup.json")
        try? data.write(to: url)
        return url
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

//
//  Components.swift
//  RatiteRun
//
//  Reusable themed UI kit — buttons, cards, chips, fields, gauges.
//

import SwiftUI

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var fill: Color = Palette.primary
    var textColor: Color = Palette.onPrimary
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .bold))
                }
                Text(title)
                    .font(AppFont.rounded(16, .semibold))
            }
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fill)
            )
            .shadow(color: fill.opacity(0.35), radius: pressed ? 3 : 8, x: 0, y: pressed ? 1 : 4)
            .scaleEffect(pressed ? 0.97 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pressed = true } }
                .onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pressed = false } }
        )
    }
}

struct SavannaButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void
    var body: some View {
        PrimaryButton(title: title, systemImage: systemImage,
                      fill: Palette.savanna, textColor: Palette.onSavanna, action: action)
    }
}

struct DangerButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void
    var body: some View {
        PrimaryButton(title: title, systemImage: systemImage,
                      fill: Palette.danger, textColor: Palette.onDanger, action: action)
    }
}

struct GhostButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Palette.primaryActive
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(AppFont.rounded(15, .semibold))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.5), lineWidth: 1.4)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(tint.opacity(0.08))
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    let content: Content
    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Palette.border, lineWidth: 1)
            )
            .shadow(color: Palette.shadow, radius: 10, x: 0, y: 5)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var accent: Color = Palette.primary
    var body: some View {
        HStack(spacing: 8) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(accent)
            }
            Text(title)
                .font(AppFont.rounded(15, .bold))
                .foregroundColor(Palette.textSecondary)
            Spacer()
        }
    }
}

// MARK: - Chip

struct Chip: View {
    let title: String
    var systemImage: String? = nil
    let selected: Bool
    var accent: Color = Palette.primary
    let action: () -> Void
    var body: some View {
        Button(action: {
            let gen = UISelectionFeedbackGenerator(); gen.selectionChanged()
            action()
        }) {
            HStack(spacing: 6) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(AppFont.rounded(14, .semibold))
            }
            .foregroundColor(selected ? Palette.onPrimary : Palette.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? accent : Palette.bgSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? accent : Palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Flow layout for chips (hand-rolled for iOS 14)

struct FlowChips<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let spacing: CGFloat
    let content: (Data.Element) -> Content
    init(_ data: Data, spacing: CGFloat = 8, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.spacing = spacing
        self.content = content
    }
    @State private var totalHeight: CGFloat = 0
    var body: some View {
        GeometryReader { geo in
            self.generate(in: geo.size.width)
        }
        .frame(height: totalHeight)
    }
    private func generate(in width: CGFloat) -> some View {
        var x: CGFloat = 0
        var y: CGFloat = 0
        return ZStack(alignment: .topLeading) {
            ForEach(Array(data), id: \.self) { item in
                content(item)
                    .alignmentGuide(.leading) { d in
                        if abs(x - d.width) > width {
                            x = 0
                            y -= d.height + spacing
                        }
                        let result = x
                        if item == Array(data).last {
                            x = 0
                        } else {
                            x -= d.width + spacing
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = y
                        if item == Array(data).last { y = 0 }
                        return result
                    }
            }
        }
        .background(heightReader)
    }
    private var heightReader: some View {
        GeometryReader { geo -> Color in
            let h = geo.frame(in: .local).size.height
            DispatchQueue.main.async { self.totalHeight = h }
            return Color.clear
        }
    }
}

// MARK: - Text field

struct AppTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var systemImage: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.caption).foregroundColor(Palette.textSecondary)
            HStack(spacing: 8) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14))
                        .foregroundColor(Palette.primary)
                }
                TextField(placeholder, text: $text)
                    .font(AppFont.body)
                    .foregroundColor(Palette.textPrimary)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.bgSoft))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
        }
    }
}

struct AppNumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String = ""
    var systemImage: String? = nil
    @State private var textValue: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.caption).foregroundColor(Palette.textSecondary)
            HStack(spacing: 8) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage).font(.system(size: 14)).foregroundColor(Palette.primary)
                }
                TextField("0", text: $textValue)
                    .keyboardType(.decimalPad)
                    .font(AppFont.mono)
                    .foregroundColor(Palette.textPrimary)
                    .onChange(of: textValue) { newVal in
                        let filtered = newVal.filter { "0123456789.".contains($0) }
                        if let d = Double(filtered) { value = d }
                        else if filtered.isEmpty { value = 0 }
                    }
                if !unit.isEmpty {
                    Text(unit).font(AppFont.caption).foregroundColor(Palette.textDisabled)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.bgSoft))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
        }
        .onAppear { textValue = value == 0 ? "" : trimmed(value) }
        .onChange(of: value) { newVal in
            // keep in sync on programmatic changes
            let shown = Double(textValue) ?? -1
            if abs(shown - newVal) > 0.0001 {
                textValue = newVal == 0 ? "" : trimmed(newVal)
            }
        }
    }
    private func trimmed(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }
}

struct AppStepper: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...999
    var body: some View {
        HStack {
            Text(title).font(AppFont.body).foregroundColor(Palette.textPrimary)
            Spacer()
            HStack(spacing: 0) {
                stepButton("minus") { if value > range.lowerBound { value -= 1 } }
                Text("\(value)")
                    .font(AppFont.mono)
                    .foregroundColor(Palette.textPrimary)
                    .frame(minWidth: 44)
                stepButton("plus") { if value < range.upperBound { value += 1 } }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.bgSoft))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1))
        }
    }
    private func stepButton(_ symbol: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Palette.primaryActive)
                .frame(width: 38, height: 36)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Stat pill

struct StatPill: View {
    let value: String
    let label: String
    var color: Color = Palette.primary
    var systemImage: String? = nil
    var body: some View {
        VStack(spacing: 4) {
            if let systemImage = systemImage {
                Image(systemName: systemImage).font(.system(size: 15, weight: .bold)).foregroundColor(color)
            }
            Text(value).font(AppFont.rounded(19, .bold)).foregroundColor(Palette.textPrimary)
            Text(label).font(AppFont.rounded(11, .medium)).foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Ring gauge

struct RingGauge: View {
    let progress: Double   // 0...1
    var size: CGFloat = 96
    var color: Color = Palette.primary
    var centerText: String? = nil
    var caption: String? = nil
    var body: some View {
        ZStack {
            Circle().stroke(Palette.bgDepth, lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.001, min(1, progress))))
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [color.opacity(0.6), color]),
                                    center: .center),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(centerText ?? "\(Int(progress * 100))%")
                    .font(AppFont.rounded(size * 0.24, .bold))
                    .foregroundColor(Palette.textPrimary)
                if let caption = caption {
                    Text(caption).font(AppFont.rounded(size * 0.11, .medium)).foregroundColor(Palette.textSecondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Segment bar

struct SegmentBar: View {
    let value: Double  // 0...1
    var color: Color = Palette.primary
    var height: CGFloat = 10
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.bgDepth)
                Capsule().fill(color)
                    .frame(width: max(6, geo.size.width * CGFloat(max(0, min(1, value)))))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Verdict badge

struct VerdictBadge: View {
    let text: String
    let color: Color
    var systemImage: String = "checkmark.seal.fill"
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 12, weight: .bold))
            Text(text).font(AppFont.rounded(13, .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String
    var systemImage: String = "checkmark.circle.fill"
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundColor(Palette.norm)
            Text(message).font(AppFont.rounded(14, .semibold)).foregroundColor(Palette.textPrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 1))
        .shadow(color: Palette.shadow, radius: 12, y: 6)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        ZStack {
            content
            if let message = message {
                VStack {
                    Spacer()
                    ToastView(message: message)
                        .padding(.bottom, 90)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation(.spring()) { self.message = nil }
                    }
                }
            }
        }
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
    func screenBackground() -> some View {
        self.background(Palette.bg.ignoresSafeArea())
    }
}

// MARK: - Disclaimer banner

struct DisclaimerBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Palette.danger)
                .font(.system(size: 14, weight: .bold))
            Text(text)
                .font(AppFont.rounded(12, .medium))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.danger.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.danger.opacity(0.25), lineWidth: 1))
    }
}

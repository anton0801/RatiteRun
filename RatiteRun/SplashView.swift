//
//  SplashView.swift
//  RatiteRun
//
//  Thematic splash: a big ratite strides across the run kicking up dust,
//  a tall fence rises, the space field glows. Standalone & self-cleaning.
//

import SwiftUI

struct SplashView: View {
    @Binding var isActive: Bool

    // animation state flags
    @State private var isVisible = true
    @State private var bgShift = false          // layer 1: background gradient drift
    @State private var stride = false           // layer 2: bird stride position
    @State private var dust = false             // dust puffs
    @State private var fenceRise: CGFloat = 0   // tall fence rising
    @State private var logoIn = false           // layer 3: logo entrance
    @State private var exiting = false          // designed exit

    @State private var timer: Timer? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Layer 1 — drifting beige background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Palette.bg, Palette.bgSoft, Palette.bgDepth]),
                    startPoint: bgShift ? .topLeading : .bottomLeading,
                    endPoint: bgShift ? .bottomTrailing : .topTrailing)
                    .ignoresSafeArea()

                // Highlighted space field (glowing ground the bird needs)
                Ellipse()
                    .fill(Palette.savanna.opacity(0.16))
                    .frame(width: w * 0.9, height: h * 0.28)
                    .position(x: w * 0.5, y: h * 0.68)
                    .blur(radius: 8)
                    .scaleEffect(bgShift ? 1.04 : 0.96)

                // Layer 2 — rising tall fence (behind the bird)
                FenceShape(posts: 7)
                    .trim(from: 0, to: fenceRise)
                    .stroke(Palette.primaryActive.opacity(0.55),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: w * 0.86, height: h * 0.30)
                    .position(x: w * 0.5, y: h * 0.55)

                // Dust puffs rising behind the stride
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(Palette.bgDepth.opacity(dust ? 0.0 : 0.7))
                        .frame(width: CGFloat(10 + i * 5), height: CGFloat(10 + i * 5))
                        .offset(x: dust ? CGFloat(-30 - i * 14) : CGFloat(-10),
                                y: dust ? CGFloat(-8 - i * 6) : 0)
                        .position(x: w * (stride ? 0.62 : 0.36), y: h * 0.66)
                        .animation(Animation.easeOut(duration: 1.1)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.12))
                }

                // Big striding bird
                StridingBird()
                    .fill(LinearGradient(gradient: Gradient(colors: [Palette.primary, Palette.primaryActive]),
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.24, height: h * 0.24)
                    .position(x: w * (stride ? 0.62 : 0.36), y: h * 0.60)
                    .shadow(color: Palette.amberGlow, radius: 12)

                // Layer 3 — logo + title
                VStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Palette.primary.opacity(0.14)).frame(width: 96, height: 96)
                        Image(systemName: "bird.fill")
                            .font(.system(size: 46, weight: .bold))
                            .foregroundColor(Palette.primaryActive)
                    }
                    .scaleEffect(exiting ? 2.6 : (logoIn ? 1 : 0.6))
                    .opacity(exiting ? 0 : (logoIn ? 1 : 0))

                    Text("Ratite Run")
                        .font(AppFont.rounded(34, .heavy))
                        .foregroundColor(Palette.textPrimary)
                        .opacity(logoIn ? 1 : 0)
                        .offset(y: logoIn ? 0 : 14)

                    Text("Big birds, big space, safe handling.")
                        .font(AppFont.rounded(14, .medium))
                        .foregroundColor(Palette.textSecondary)
                        .opacity(logoIn ? 1 : 0)
                }
                .opacity(exiting ? 0 : 1)
                .position(x: w * 0.5, y: h * 0.32)
            }
        }
        .onAppear(perform: start)
        .onDisappear(perform: cleanup)
    }

    private func start() {
        isVisible = true
        // phase 1 (0–0.6s) background builds in + loops
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { bgShift = true }
        // phase 2 (0.6–1.4s) thematic stride + dust + fence
        withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true).delay(0.5)) { stride = true }
        withAnimation(.easeInOut(duration: 1.0).delay(0.6)) { fenceRise = 1 }
        dust = true
        // phase 3 (1.4–2.2s) logo spring entrance
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(1.3)) { logoIn = true }

        // single coordinator timer → phase 4 designed exit at 2.5s
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
            withAnimation(.easeIn(duration: 0.5)) { exiting = true }
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                isActive = false
            }
        }
    }

    private func cleanup() {
        isVisible = false
        timer?.invalidate(); timer = nil
        bgShift = false; stride = false; dust = false
        fenceRise = 0; logoIn = false
    }
}

// MARK: - Shapes

/// A stylised big running-bird silhouette (body, neck, head, two long legs).
struct StridingBird: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // body (oval)
        p.addEllipse(in: CGRect(x: w*0.18, y: h*0.30, width: w*0.55, height: h*0.34))
        // neck + head
        p.move(to: CGPoint(x: w*0.62, y: h*0.36))
        p.addQuadCurve(to: CGPoint(x: w*0.86, y: h*0.06),
                       control: CGPoint(x: w*0.80, y: h*0.22))
        p.addEllipse(in: CGRect(x: w*0.80, y: h*0.02, width: w*0.16, height: h*0.13))
        // legs (striding)
        p.move(to: CGPoint(x: w*0.34, y: h*0.62))
        p.addLine(to: CGPoint(x: w*0.20, y: h*0.98))
        p.move(to: CGPoint(x: w*0.52, y: h*0.62))
        p.addLine(to: CGPoint(x: w*0.66, y: h*0.98))
        // tail
        p.move(to: CGPoint(x: w*0.18, y: h*0.42))
        p.addQuadCurve(to: CGPoint(x: w*0.02, y: h*0.50),
                       control: CGPoint(x: w*0.08, y: h*0.36))
        return p
    }
}

/// A run of fence posts with a top rail — drawn as one path for trim animation.
struct FenceShape: Shape {
    let posts: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let spacing = rect.width / CGFloat(posts - 1)
        // top rail
        p.move(to: CGPoint(x: 0, y: rect.height * 0.1))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.1))
        // mid rail
        p.move(to: CGPoint(x: 0, y: rect.height * 0.5))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.5))
        // posts
        for i in 0..<posts {
            let x = CGFloat(i) * spacing
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: rect.height))
        }
        return p
    }
}

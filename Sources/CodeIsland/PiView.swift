import SwiftUI
import CodeIslandCore

/// PiBot — Pi coding agent mascot, pixel-art robot with antenna and screen face.
/// Inspired by pi-mono's minimalist AI agent toolkit branding.
struct PiView: View {
    let status: AgentStatus
    var size: CGFloat = 27
    @State private var alive = false
    @Environment(\.mascotSpeed) private var speed

    // Robot palette — cool grays with cyan accent
    private static let bodyC    = Color(red: 0.35, green: 0.37, blue: 0.42) // steel body
    private static let screenC  = Color(red: 0.12, green: 0.13, blue: 0.16) // dark screen
    private static let eyeC     = Color(red: 0.30, green: 0.85, blue: 0.95) // cyan glow
    private static let dimEyeC  = Color(red: 0.15, green: 0.35, blue: 0.40) // dim cyan
    private static let antennaC = Color(red: 0.55, green: 0.57, blue: 0.62) // silver
    private static let alertC   = Color(red: 1.0, green: 0.55, blue: 0.0)   // amber
    private static let legC     = Color(red: 0.28, green: 0.30, blue: 0.34)
    private static let kbBase   = Color(red: 0.12, green: 0.12, blue: 0.14)
    private static let kbKey    = Color(red: 0.30, green: 0.30, blue: 0.32)
    private static let kbHi     = Color.white

    var body: some View {
        ZStack {
            switch status {
            case .idle:                 sleepScene
            case .processing, .running: workScene
            case .waitingApproval, .waitingQuestion: alertScene
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .onAppear { alive = true }
        .onChange(of: status) {
            alive = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { alive = true }
        }
    }

    private struct V {
        let ox: CGFloat, oy: CGFloat, s: CGFloat
        let y0: CGFloat
        init(_ sz: CGSize, svgW: CGFloat = 15, svgH: CGFloat = 10, svgY0: CGFloat = 6) {
            s = min(sz.width / svgW, sz.height / svgH)
            ox = (sz.width - svgW * s) / 2
            oy = (sz.height - svgH * s) / 2
            y0 = svgY0
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, dy: CGFloat = 0) -> CGRect {
            CGRect(x: ox + x * s, y: oy + (y - y0 + dy) * s, width: w * s, height: h * s)
        }
    }

    private func lerp(_ keyframes: [(CGFloat, CGFloat)], at pct: CGFloat) -> CGFloat {
        guard let first = keyframes.first else { return 0 }
        if pct <= first.0 { return first.1 }
        for i in 1..<keyframes.count {
            if pct <= keyframes[i].0 {
                let t = (pct - keyframes[i-1].0) / (keyframes[i].0 - keyframes[i-1].0)
                return keyframes[i-1].1 + (keyframes[i].1 - keyframes[i-1].1) * t
            }
        }
        return keyframes.last?.1 ?? 0
    }

    // ── Draw robot body — square with rounded top corners ──
    private func drawBody(_ c: GraphicsContext, v: V, dy: CGFloat,
                          squashX: CGFloat = 1, squashY: CGFloat = 1) {
        let cx: CGFloat = 7.5
        func sx(_ x: CGFloat, w: CGFloat) -> (CGFloat, CGFloat) {
            let nx = cx + (x - cx) * squashX
            return (nx, w * squashX)
        }

        // Main body rows
        let bodyRows: [(y: CGFloat, x: CGFloat, w: CGFloat)] = [
            (9,  3, 9),    // top
            (10, 2, 11),
            (11, 2, 11),
            (12, 2, 11),
            (13, 2, 11),
            (14, 3, 9),    // bottom
        ]
        for row in bodyRows {
            let (adjX, adjW) = sx(row.x, w: row.w)
            let adjH: CGFloat = 1 * squashY
            c.fill(Path(v.r(adjX, row.y * squashY + (1 - squashY) * 11, adjW, adjH, dy: dy)),
                   with: .color(Self.bodyC))
        }

        // Screen inset (dark face area)
        let screenRows: [(y: CGFloat, x: CGFloat, w: CGFloat)] = [
            (10, 3, 9),
            (11, 3, 9),
            (12, 3, 9),
        ]
        for row in screenRows {
            let (adjX, adjW) = sx(row.x, w: row.w)
            let adjH: CGFloat = 1 * squashY
            c.fill(Path(v.r(adjX, row.y * squashY + (1 - squashY) * 11, adjW, adjH, dy: dy)),
                   with: .color(Self.screenC))
        }

        // Ear/shoulder details
        let (lx, _) = sx(1.5, w: 1)
        c.fill(Path(v.r(lx, 10 * squashY + (1 - squashY) * 11, 1 * squashX, 2 * squashY, dy: dy)),
               with: .color(Self.bodyC.opacity(0.7)))
        let (rx, _) = sx(12.5, w: 1)
        c.fill(Path(v.r(rx, 10 * squashY + (1 - squashY) * 11, 1 * squashX, 2 * squashY, dy: dy)),
               with: .color(Self.bodyC.opacity(0.7)))
    }

    // ── Draw antenna ──
    private func drawAntenna(_ c: GraphicsContext, v: V, dy: CGFloat,
                             glowing: Bool = false) {
        // Antenna stalk
        c.fill(Path(v.r(7, 7.5, 1, 1.5, dy: dy)), with: .color(Self.antennaC))
        // Antenna tip
        let tipColor = glowing ? Self.eyeC : Self.antennaC
        c.fill(Path(v.r(6.5, 7, 2, 1, dy: dy)), with: .color(tipColor))
        if glowing {
            c.fill(Path(v.r(6, 6.5, 3, 1.5, dy: dy)),
                   with: .color(Self.eyeC.opacity(0.3)))
        }
    }

    // ── Draw face — pixel eyes ──
    private func drawFace(_ c: GraphicsContext, v: V, dy: CGFloat,
                          eyeColor: Color = Self.eyeC, eyeScale: CGFloat = 1.0,
                          mouthOn: Bool = true) {
        let eyeH: CGFloat = 1.5 * eyeScale
        let eyeY: CGFloat = 10.5 + (1.5 - eyeH) / 2

        // Left eye
        c.fill(Path(v.r(4, eyeY, 1.5, max(0.3, eyeH), dy: dy)), with: .color(eyeColor))
        // Right eye
        c.fill(Path(v.r(9.5, eyeY, 1.5, max(0.3, eyeH), dy: dy)), with: .color(eyeColor))

        // Mouth — small pixel line
        if mouthOn {
            c.fill(Path(v.r(6, 12.3, 3, 0.5, dy: dy)), with: .color(eyeColor.opacity(0.5)))
        }
    }

    private func drawShadow(_ c: GraphicsContext, v: V, width: CGFloat = 9, opacity: Double = 0.3) {
        c.fill(Path(v.r(7.5 - width / 2, 15, width, 1)),
               with: .color(.black.opacity(opacity)))
    }

    private func drawLegs(_ c: GraphicsContext, v: V) {
        c.fill(Path(v.r(4.5, 14, 1.5, 1.5)), with: .color(Self.legC))
        c.fill(Path(v.r(9, 14, 1.5, 1.5)), with: .color(Self.legC))
    }

    // ━━━━━━ SLEEP ━━━━━━
    private var sleepScene: some View {
        ZStack {
            TimelineView(.periodic(from: .now, by: 0.06)) { ctx in
                sleepCanvas(t: ctx.date.timeIntervalSinceReferenceDate * speed)
            }
            TimelineView(.periodic(from: .now, by: 0.05)) { ctx in
                floatingZs(t: ctx.date.timeIntervalSinceReferenceDate * speed)
            }
        }
    }

    private func floatingZs(t: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let ci = Double(i)
                let cycle = 2.8 + ci * 0.3
                let delay = ci * 0.9
                let phase = max(0, ((t - delay).truncatingRemainder(dividingBy: cycle)) / cycle)
                let fontSize = max(6, size * CGFloat(0.18 + phase * 0.10))
                let baseOp = 0.7 - ci * 0.1
                let opacity = phase < 0.8 ? baseOp : (1.0 - phase) * 3.5 * baseOp
                Text("z")
                    .font(.system(size: fontSize, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(opacity))
                    .offset(x: size * CGFloat(0.15 + ci * 0.08),
                            y: -size * CGFloat(0.15 + phase * 0.38))
            }
        }
    }

    private func sleepCanvas(t: Double) -> some View {
        let phase = t.truncatingRemainder(dividingBy: 4.0) / 4.0
        let float = sin(phase * .pi * 2) * 0.6
        let blinkPhase = t.truncatingRemainder(dividingBy: 2.0)
        let eyeOpen = blinkPhase < 1.2

        return Canvas { c, sz in
            let v = V(sz, svgW: 15, svgH: 12, svgY0: 4)
            drawShadow(c, v: v, width: 7 + abs(float) * 0.3, opacity: 0.2)
            drawLegs(c, v: v)
            drawBody(c, v: v, dy: float)
            drawAntenna(c, v: v, dy: float, glowing: false)
            if eyeOpen {
                drawFace(c, v: v, dy: float, eyeColor: Self.dimEyeC, eyeScale: 0.5, mouthOn: false)
            }
        }
    }

    // ━━━━━━ WORK ━━━━━━
    private var workScene: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { ctx in
            workCanvas(t: ctx.date.timeIntervalSinceReferenceDate * speed)
        }
    }

    private func workCanvas(t: Double) -> some View {
        let bounce = sin(t * 2 * .pi / 0.4) * 1.0
        let blinkCycle = t.truncatingRemainder(dividingBy: 3.0)
        let blink: CGFloat = (blinkCycle > 2.6 && blinkCycle < 2.75) ? 0.1 : 1.0
        let keyPhase = Int(t / 0.1) % 6
        let antennaGlow = blinkCycle < 1.5

        return Canvas { c, sz in
            let v = V(sz, svgW: 16, svgH: 14, svgY0: 3)

            let shadowW: CGFloat = 8 - abs(bounce) * 0.3
            c.fill(Path(v.r(4 + (8 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(max(0.1, 0.35 - abs(bounce) * 0.03))))

            drawLegs(c, v: v)

            // Keyboard
            c.fill(Path(v.r(0, 13, 15, 3)), with: .color(Self.kbBase))
            for row in 0..<2 {
                let ky = 13.5 + CGFloat(row) * 1.2
                for col in 0..<6 {
                    let kx = 0.5 + CGFloat(col) * 2.4
                    c.fill(Path(v.r(kx, ky, 1.8, 0.7)), with: .color(Self.kbKey))
                }
            }
            let fCol = keyPhase % 6
            let fRow = keyPhase / 3
            c.fill(Path(v.r(0.5 + CGFloat(fCol) * 2.4, 13.5 + CGFloat(fRow) * 1.2, 1.8, 0.7)),
                   with: .color(Self.kbHi.opacity(0.9)))

            drawBody(c, v: v, dy: bounce)
            drawAntenna(c, v: v, dy: bounce, glowing: antennaGlow)
            drawFace(c, v: v, dy: bounce, eyeScale: blink, mouthOn: true)
        }
    }

    // ━━━━━━ ALERT ━━━━━━
    private var alertScene: some View {
        ZStack {
            Circle()
                .fill(Self.alertC.opacity(alive ? 0.12 : 0))
                .frame(width: size * 0.8)
                .blur(radius: size * 0.05)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: alive)

            TimelineView(.periodic(from: .now, by: 0.03)) { ctx in
                alertCanvas(t: ctx.date.timeIntervalSinceReferenceDate * speed)
            }
        }
    }

    private func alertCanvas(t: Double) -> some View {
        let cycle = t.truncatingRemainder(dividingBy: 3.5)
        let pct = cycle / 3.5

        let jumpY = lerp([
            (0, 0), (0.03, 0), (0.10, -1), (0.15, 1.5),
            (0.175, -8), (0.20, -8), (0.25, 1.5),
            (0.275, -6), (0.30, -6), (0.35, 1.0),
            (0.375, -4), (0.40, -4), (0.45, 0.8),
            (0.475, -2), (0.50, -2), (0.55, 0.3),
            (0.62, 0), (1.0, 0),
        ], at: pct)

        let squashX: CGFloat = jumpY > 0.5 ? 1.0 + jumpY * 0.03 : 1.0
        let squashY: CGFloat = jumpY > 0.5 ? 1.0 - jumpY * 0.02 : 1.0
        let shakeX: CGFloat = (pct > 0.15 && pct < 0.55) ? sin(pct * 80) * 0.6 : 0

        // Eyes flash between cyan and amber
        let flash = (pct > 0.03 && pct < 0.55) ? sin(pct * 25) * 0.5 + 0.5 : 0.0
        let eyeColor = flash > 0.5 ? Self.alertC : Self.eyeC

        let bangOp = lerp([
            (0, 0), (0.03, 1), (0.10, 1), (0.55, 1), (0.62, 0), (1.0, 0),
        ], at: pct)
        let bangScale = lerp([
            (0, 0.3), (0.03, 1.3), (0.10, 1.0), (0.55, 1.0), (0.62, 0.6), (1.0, 0.6),
        ], at: pct)

        return Canvas { c, sz in
            let v = V(sz, svgW: 16, svgH: 14, svgY0: 3)

            let shadowW: CGFloat = 8 * (1.0 - abs(min(0, jumpY)) * 0.04)
            c.fill(Path(v.r(4 + (8 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(max(0.08, 0.4 - abs(min(0, jumpY)) * 0.04))))

            drawLegs(c, v: v)

            c.translateBy(x: shakeX * v.s, y: 0)
            drawBody(c, v: v, dy: jumpY, squashX: squashX, squashY: squashY)
            drawAntenna(c, v: v, dy: jumpY, glowing: true)
            drawFace(c, v: v, dy: jumpY, eyeColor: eyeColor,
                     eyeScale: pct > 0.03 && pct < 0.15 ? 1.3 : 1.0, mouthOn: true)
            c.translateBy(x: -shakeX * v.s, y: 0)

            if bangOp > 0.01 {
                let bw: CGFloat = 2 * bangScale
                let bx: CGFloat = 13
                let by: CGFloat = 4 + jumpY * 0.15
                c.fill(Path(v.r(bx, by, bw, 3.5 * bangScale, dy: 0)),
                       with: .color(Self.alertC.opacity(bangOp)))
                c.fill(Path(v.r(bx, by + 4.0 * bangScale, bw, 1.5 * bangScale, dy: 0)),
                       with: .color(Self.alertC.opacity(bangOp)))
            }
        }
    }
}

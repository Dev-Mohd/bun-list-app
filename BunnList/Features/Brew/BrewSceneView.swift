import BunnListCore
import SwiftUI

/// The brewer drawn live while you brew: water, bloom, drips, the plunger, the
/// shot, the dalla on its flame. Driven by `BrewSceneState` (what the recipe says
/// is happening) plus the clock for the small motions. Drawn in a 600×640 space
/// and scaled to fit; no images, so it follows the recipe's real timing exactly.
struct BrewSceneView: View {
    let kind: BrewSceneKind
    let state: BrewSceneState
    /// Seconds since the scene appeared; only for wiggles and loops.
    let clock: Double

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 600, size.height / 640)
            context.translateBy(x: (size.width - 600 * scale) / 2, y: (size.height - 640 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            switch kind {
            case let .pourOver(iced): PourOverPainter(state: state, t: clock, iced: iced).draw(&context)
            case .aeropress: AeroPressPainter(state: state, t: clock).draw(&context)
            case .arabic: DallaPainter(state: state, t: clock).draw(&context)
            case .espresso, .ring: break
            }
        }
        .accessibilityHidden(true)
    }
}

/// Espresso has its own clock (start/stop by hand), so it takes the shot's numbers.
struct EspressoSceneView: View {
    /// 0 before the shot, then seconds pulled.
    let elapsed: Double
    let running: Bool
    let target: ClosedRange<Int>
    let clock: Double

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 600, size.height / 640)
            context.translateBy(x: (size.width - 600 * scale) / 2, y: (size.height - 640 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            EspressoPainter(elapsed: elapsed, running: running, target: target, t: clock).draw(&context)
        }
        .accessibilityHidden(true)
    }
}

// MARK: Shared bits

private enum Ink {
    static let gold = Color(red: 0.78, green: 0.60, blue: 0.24)
    static let cream = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let paper = Color(red: 0.94, green: 0.89, blue: 0.81)
    static let groundsDry = Color(red: 0.48, green: 0.32, blue: 0.21)
    static let groundsWet = Color(red: 0.31, green: 0.20, blue: 0.13)
    static let coffeeTop = Color(red: 0.48, green: 0.29, blue: 0.13)
    static let coffee = Color(red: 0.16, green: 0.09, blue: 0.05)
    static let water = Color(red: 0.62, green: 0.42, blue: 0.22)
    static let stream = Color(red: 0.92, green: 0.88, blue: 0.80)
    static let ice = Color(red: 0.88, green: 0.93, blue: 0.96)
    static let glass = Color.white.opacity(0.5)
}

private func clamp(_ v: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b, max(a, v)) }
private func lerp(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }
private func easeOut(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
private func easeInOut(_ p: Double) -> Double { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }

/// A fixed pseudo-random sequence, so particles sit still between frames.
private func noise(_ i: Int, _ salt: Int = 0) -> Double {
    let x = sin(Double(i * 127 + salt * 311) * 12.9898) * 43758.5453
    return x - floor(x)
}

private func circle(_ c: CGPoint, _ r: Double) -> Path {
    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}

private func steam(_ context: inout GraphicsContext, xs: [Double], baseY: Double, t: Double, alpha: Double) {
    for (n, x) in xs.enumerated() {
        let q = (t * 0.6 + Double(n) * 0.33).truncatingRemainder(dividingBy: 1)
        let y0 = baseY - q * 110
        var p = Path()
        p.move(to: CGPoint(x: x, y: y0))
        p.addQuadCurve(to: CGPoint(x: x, y: y0 - 60), control: CGPoint(x: x + 18, y: y0 - 30))
        p.addQuadCurve(to: CGPoint(x: x, y: y0 - 120), control: CGPoint(x: x - 18, y: y0 - 90))
        context.stroke(p, with: .color(Ink.cream.opacity(0.5 * alpha * sin(q * .pi))),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round))
    }
}

/// The gooseneck kettle, tilted by `tilt` (0…1); returns the spout tip.
@discardableResult
private func kettle(_ context: inout GraphicsContext, tilt: Double, show: Double) -> CGPoint {
    let pivot = CGPoint(x: 560, y: 60)
    let angle = -14 * tilt * .pi / 180
    let shift = CGSize(width: (1 - show) * 260, height: (1 - show) * -120)
    var k = context
    k.translateBy(x: shift.width, y: shift.height)
    k.translateBy(x: pivot.x, y: pivot.y)
    k.rotate(by: .radians(angle))
    k.translateBy(x: -pivot.x, y: -pivot.y)
    var body = Path()
    body.move(to: CGPoint(x: 520, y: -10))
    body.addCurve(to: CGPoint(x: 640, y: 110), control1: CGPoint(x: 600, y: -10), control2: CGPoint(x: 640, y: 40))
    body.addLine(to: CGPoint(x: 640, y: 140)); body.addLine(to: CGPoint(x: 480, y: 140)); body.addLine(to: CGPoint(x: 480, y: 60))
    body.addCurve(to: CGPoint(x: 520, y: -10), control1: CGPoint(x: 480, y: 20), control2: CGPoint(x: 495, y: -10))
    k.fill(body, with: .color(Color(red: 0.17, green: 0.15, blue: 0.13)))
    k.stroke(body, with: .color(Ink.cream.opacity(0.5)), lineWidth: 4)
    var spout = Path()
    spout.move(to: CGPoint(x: 486, y: 110))
    spout.addCurve(to: CGPoint(x: 366, y: 50), control1: CGPoint(x: 430, y: 110), control2: CGPoint(x: 420, y: 60))
    k.stroke(spout, with: .color(Ink.cream.opacity(0.6)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
    // Tip in the unrotated space.
    let tx = 366 - pivot.x, ty = 50 - pivot.y
    return CGPoint(x: pivot.x + tx * cos(angle) - ty * sin(angle) + shift.width,
                   y: pivot.y + tx * sin(angle) + ty * cos(angle) + shift.height)
}

private func pourStream(_ context: inout GraphicsContext, from tip: CGPoint, to hit: CGPoint, width: Double, t: Double) {
    var s = Path()
    s.move(to: tip)
    s.addQuadCurve(to: hit, control: CGPoint(x: tip.x - 30, y: tip.y + 50))
    context.stroke(s, with: .color(Ink.stream.opacity(0.85)), style: StrokeStyle(lineWidth: width, lineCap: .round))
    for n in 0..<3 {
        let q = (t * 2 + Double(n) / 3).truncatingRemainder(dividingBy: 1)
        let r = CGRect(x: hit.x - (8 + q * 46), y: hit.y + 3 - (3 + q * 10), width: (8 + q * 46) * 2, height: (3 + q * 10) * 2)
        context.stroke(Path(ellipseIn: r), with: .color(Color(red: 1, green: 0.94, blue: 0.82).opacity(0.6 * (1 - q))), lineWidth: 3)
    }
}

// MARK: V60 (hot and iced)

private struct PourOverPainter {
    let state: BrewSceneState
    let t: Double
    let iced: Bool

    private var cone: Path {
        var p = Path()
        p.move(to: CGPoint(x: 168, y: 168)); p.addLine(to: CGPoint(x: 432, y: 168))
        p.addLine(to: CGPoint(x: 312, y: 392)); p.addLine(to: CGPoint(x: 288, y: 392)); p.closeSubpath()
        return p
    }

    private var server: Path {
        var p = Path()
        p.move(to: CGPoint(x: 196, y: 438))
        p.addCurve(to: CGPoint(x: 222, y: 618), control1: CGPoint(x: 186, y: 520), control2: CGPoint(x: 190, y: 590))
        p.addLine(to: CGPoint(x: 378, y: 618))
        p.addCurve(to: CGPoint(x: 404, y: 438), control1: CGPoint(x: 410, y: 590), control2: CGPoint(x: 414, y: 520))
        p.closeSubpath()
        return p
    }

    func draw(_ context: inout GraphicsContext) {
        let stage = state.stage
        let done = stage == .done
        let lift = done ? easeInOut(clamp(state.progress)) : 0

        // Server: ice, coffee, glass.
        let fill = state.drained * 0.86
        let surface = 618 - 172 * fill
        context.drawLayer { layer in
            layer.clip(to: server)
            layer.fill(Path(CGRect(x: 180, y: 420, width: 240, height: 210)), with: .color(.white.opacity(0.06)))
            if iced { drawIce(&layer, surface: surface, front: false) }
            layer.fill(Path(CGRect(x: 180, y: surface, width: 240, height: 618 - surface)),
                       with: .linearGradient(Gradient(colors: [Ink.coffeeTop, Ink.coffee]),
                                             startPoint: CGPoint(x: 300, y: surface), endPoint: CGPoint(x: 300, y: 618)))
            if iced { drawIce(&layer, surface: surface, front: true) }
        }
        let rim = Path { p in
            p.move(to: CGPoint(x: 196, y: 438))
            p.addCurve(to: CGPoint(x: 222, y: 618), control1: CGPoint(x: 186, y: 520), control2: CGPoint(x: 190, y: 590))
            p.addLine(to: CGPoint(x: 378, y: 618))
            p.addCurve(to: CGPoint(x: 404, y: 438), control1: CGPoint(x: 410, y: 590), control2: CGPoint(x: 414, y: 520))
        }
        context.stroke(rim, with: .color(Ink.cream.opacity(0.55)), lineWidth: 5)
        var handle = Path()
        handle.move(to: CGPoint(x: 404, y: 470))
        handle.addCurve(to: CGPoint(x: 400, y: 566), control1: CGPoint(x: 450, y: 470), control2: CGPoint(x: 456, y: 560))
        context.stroke(handle, with: .color(Ink.cream.opacity(0.4)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        context.fill(Path(roundedRect: CGRect(x: 186, y: 426, width: 228, height: 14), cornerRadius: 7), with: .color(Ink.cream.opacity(0.5)))
        if iced && (done || state.drained > 0.7) { drawBeads(&context, alpha: done ? 1 : (state.drained - 0.7) / 0.3) }

        // Drips from the cone into the server.
        let dripping = !done && state.poured > 0.05 && state.standing > 0.01
        if dripping {
            for n in 0..<3 {
                let q = (t / 0.45 + Double(n) / 3).truncatingRemainder(dividingBy: 1)
                let y = lerp(420, surface, q * q)
                context.fill(Path(ellipseIn: CGRect(x: 295, y: y - 8, width: 10, height: 16)), with: .color(Ink.coffeeTop))
            }
        }

        // Dripper (swirls gently on a swirl step, lifts away when done).
        var d = context
        d.opacity = 1 - lift
        d.translateBy(x: 0, y: -lift * 420)
        if stage == .swirl {
            d.translateBy(x: 300, y: 300)
            d.rotate(by: .degrees(sin(t * 7) * 4))
            d.translateBy(x: -300, y: -300)
        }
        drawDripper(&d)

        // Kettle and stream.
        let pouring = (stage == .bloom && state.progress < 0.4) || (stage == .pour && state.progress < 0.85)
        let tilt: Double = {
            switch stage {
            case .bloom: return sin(clamp(state.progress / 0.4) * .pi)
            case .pour: return min(1, sin(clamp(state.progress / 0.85) * .pi) * 3)
            default: return 0
            }
        }()
        let show: Double = [.bloom, .pour].contains(stage) ? 1 : 0
        if show > 0 {
            let tip = kettle(&context, tilt: tilt, show: show)
            if pouring && tilt > 0.3 {
                let radius = stage == .pour ? 20 + 26 * abs(sin(t * 1.3)) : 6
                let hit = CGPoint(x: 300 + radius * sin(t * 7), y: waterTop - 2)
                pourStream(&context, from: tip, to: hit, width: stage == .bloom ? 5 : 8, t: t)
            }
        }

        if done && !iced { steam(&context, xs: [260, 300, 340], baseY: 420, t: t, alpha: clamp(state.progress / 0.4)) }
    }

    private var bedTop: Double { state.poured > 0 ? 324 : 328 }
    private var dome: Double {
        guard state.stage == .bloom else { return 0 }
        return easeOut(clamp((state.progress - 0.15) / 0.5)) * 16
    }
    private var waterTop: Double {
        let standing = clamp(state.standing / 0.5)
        return bedTop - dome - standing * (bedTop - 206)
    }

    private func drawDripper(_ d: inout GraphicsContext) {
        d.drawLayer { c in
            c.clip(to: cone)
            c.fill(Path(CGRect(x: 150, y: 160, width: 300, height: 240)), with: .color(Ink.paper))
            var bed = Path()
            bed.move(to: CGPoint(x: 140, y: bedTop + 8))
            bed.addQuadCurve(to: CGPoint(x: 460, y: bedTop + 8), control: CGPoint(x: 300, y: bedTop - dome * 2.2))
            bed.addLine(to: CGPoint(x: 460, y: 420)); bed.addLine(to: CGPoint(x: 140, y: 420)); bed.closeSubpath()
            c.fill(bed, with: .color(state.poured > 0 ? Ink.groundsWet : Ink.groundsDry))
            for i in 0..<36 {
                let p = CGPoint(x: 180 + noise(i) * 240, y: bedTop + 10 + noise(i, 1) * (392 - bedTop))
                c.fill(circle(p, 1.5 + noise(i, 2) * 2), with: .color(.black.opacity(0.3)))
            }
            if waterTop < bedTop - 1 {
                c.fill(Path(CGRect(x: 140, y: waterTop, width: 320, height: bedTop + 12 - waterTop)),
                       with: .linearGradient(Gradient(colors: [Ink.water.opacity(0.8), Ink.coffeeTop.opacity(0.9)]),
                                             startPoint: CGPoint(x: 300, y: waterTop), endPoint: CGPoint(x: 300, y: bedTop)))
            }
            // Bloom bubbles.
            if state.stage == .bloom && state.progress > 0.2 {
                for i in 0..<18 {
                    let q = (t * 0.8 + noise(i, 3)).truncatingRemainder(dividingBy: 1)
                    let p = CGPoint(x: 236 + noise(i, 4) * 128, y: bedTop - dome * 1.6 + 4)
                    c.stroke(circle(p, (3 + noise(i, 5) * 6) * sin(q * .pi)), with: .color(Color(red: 0.94, green: 0.86, blue: 0.7).opacity(0.7)), lineWidth: 2)
                }
            }
        }
        var outline = Path()
        outline.move(to: CGPoint(x: 150, y: 160)); outline.addLine(to: CGPoint(x: 450, y: 160)); outline.addLine(to: CGPoint(x: 452, y: 172))
        outline.addLine(to: CGPoint(x: 322, y: 404)); outline.addLine(to: CGPoint(x: 278, y: 404)); outline.addLine(to: CGPoint(x: 148, y: 172))
        outline.closeSubpath()
        d.stroke(outline, with: .color(Ink.gold), style: StrokeStyle(lineWidth: 7, lineJoin: .round))
        for (a, b) in [(200.0, 290.0), (400, 310), (250, 296), (350, 304)] {
            var rib = Path(); rib.move(to: CGPoint(x: a, y: 180)); rib.addLine(to: CGPoint(x: b, y: 380))
            d.stroke(rib, with: .color(Ink.gold.opacity(0.35)), lineWidth: 3)
        }
        d.fill(Path(roundedRect: CGRect(x: 236, y: 404, width: 128, height: 16), cornerRadius: 8), with: .color(Ink.gold))
    }

    private func drawIce(_ c: inout GraphicsContext, surface: Double, front: Bool) {
        let melt = clamp(state.drained) * 0.22
        let cubes: [(Double, Double)] = [(214, 12), (262, -8), (312, 15), (356, -14), (236, 4), (330, -4)]
        for (n, cube) in cubes.enumerated() where (n % 2 == 1) == front {
            let size = 44 * (1 - melt)
            let floor = 600 - (n > 3 ? 40 : 0) - size / 2
            let float = state.drained > 0.5 ? (state.drained - 0.5) * 70 : 0
            var g = c
            g.translateBy(x: cube.0 + 22, y: floor - float + sin(t * 2 + Double(n)) * (state.drained > 0.3 ? 2 : 0))
            g.rotate(by: .degrees(cube.1 + sin(t + Double(n)) * 3))
            let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
            g.fill(Path(roundedRect: rect, cornerRadius: 9), with: .color(Ink.ice.opacity(0.8)))
            g.stroke(Path(roundedRect: rect, cornerRadius: 9), with: .color(.white), lineWidth: 2)
            g.fill(Path(roundedRect: CGRect(x: -size / 2 + 7, y: -size / 2 + 6, width: size * 0.3, height: size * 0.18), cornerRadius: 4),
                   with: .color(.white.opacity(0.8)))
        }
    }

    private func drawBeads(_ c: inout GraphicsContext, alpha: Double) {
        for i in 0..<26 {
            let slide = state.stage == .done ? clamp((state.progress - noise(i, 6)) / 0.6) * 20 : 0
            let r = 2 + noise(i, 7) * 4
            let p = CGPoint(x: 200 + noise(i, 8) * 200, y: 450 + noise(i, 9) * 160 + (r > 4.5 ? slide : 0))
            c.fill(circle(p, r), with: .color(.white.opacity(0.45 * clamp(alpha))))
        }
    }
}

// MARK: AeroPress

private struct AeroPressPainter {
    let state: BrewSceneState
    let t: Double

    func draw(_ context: inout GraphicsContext) {
        let stage = state.stage
        let pressing = stage == .serve || stage == .press
        let done = stage == .done
        let press = done ? 1 : pressing ? easeInOut(state.progress) : 0

        // Cup.
        let cup = Path(roundedRect: CGRect(x: 205, y: 470, width: 190, height: 150), cornerRadius: 26)
        let cupFill = done ? 0.8 : pressing ? press * 0.8 : state.drained * 0.08
        context.drawLayer { c in
            c.clip(to: cup)
            let top = 620 - 150 * cupFill
            c.fill(Path(CGRect(x: 200, y: top, width: 200, height: 160)),
                   with: .linearGradient(Gradient(colors: [Ink.coffeeTop, Ink.coffee]),
                                         startPoint: CGPoint(x: 300, y: top), endPoint: CGPoint(x: 300, y: 620)))
        }
        context.stroke(cup, with: .color(Ink.cream.opacity(0.55)), lineWidth: 5)
        var handle = Path()
        handle.move(to: CGPoint(x: 395, y: 500))
        handle.addCurve(to: CGPoint(x: 395, y: 590), control1: CGPoint(x: 450, y: 500), control2: CGPoint(x: 450, y: 590))
        context.stroke(handle, with: .color(Ink.cream.opacity(0.4)), style: StrokeStyle(lineWidth: 10, lineCap: .round))

        // Chamber (wobbles on swirl, rises away when done).
        var d = context
        let lift = done ? easeInOut(clamp(state.progress / 0.5)) : 0
        d.opacity = 1 - lift
        d.translateBy(x: 0, y: -lift * 420)
        if stage == .swirl {
            d.translateBy(x: 300, y: 460)
            d.rotate(by: .degrees(sin(t * 8) * 5))
            d.translateBy(x: -300, y: -460)
        }
        let tube = CGRect(x: 225, y: 180, width: 150, height: 270)
        let bottom = Double(tube.maxY)
        let waterLevel = clamp(state.poured) * (1 - press)
        let surface = bottom - 30 - waterLevel * 200
        d.drawLayer { c in
            c.clip(to: Path(roundedRect: tube, cornerRadius: 10))
            c.fill(Path(tube), with: .color(.white.opacity(0.06)))
            // Grounds slurry, settling to a puck as the plunger comes down.
            let slurryTop = max(surface, bottom - 30 - 30 * (1 - press))
            c.fill(Path(CGRect(x: tube.minX, y: bottom - 30, width: tube.width, height: 30)), with: .color(Ink.groundsWet))
            if waterLevel > 0.01 {
                c.fill(Path(CGRect(x: tube.minX, y: surface, width: tube.width, height: bottom - 30 - surface)),
                       with: .linearGradient(Gradient(colors: [Ink.water.opacity(0.85), Ink.coffee.opacity(0.95)]),
                                             startPoint: CGPoint(x: 300, y: surface), endPoint: CGPoint(x: 300, y: bottom)))
                for i in 0..<14 {
                    let p = CGPoint(x: tube.minX + 10 + noise(i) * (tube.width - 20),
                                    y: slurryTop + 8 + noise(i, 1) * max(bottom - 40 - slurryTop, 1))
                    c.fill(circle(p, 2 + noise(i, 2) * 2), with: .color(Ink.groundsDry.opacity(0.7)))
                }
            }
            // Paddle on a stir.
            if stage == .stir || (stage == .bloom && state.progress > 0.45) {
                let x = 300 + sin(t * 6) * 45
                var paddle = Path()
                paddle.move(to: CGPoint(x: x, y: 150)); paddle.addLine(to: CGPoint(x: x + sin(t * 6) * 10, y: bottom - 50))
                c.stroke(paddle, with: .color(Ink.cream.opacity(0.8)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
            }
        }
        d.stroke(Path(roundedRect: tube, cornerRadius: 10), with: .color(Ink.cream.opacity(0.6)), lineWidth: 5)
        for n in 1...4 {
            var mark = Path(); let y = bottom - 30 - Double(n) * 50
            mark.move(to: CGPoint(x: tube.minX + 6, y: y)); mark.addLine(to: CGPoint(x: tube.minX + 34, y: y))
            d.stroke(mark, with: .color(Ink.cream.opacity(0.35)), lineWidth: 3)
        }
        // Cap and flange.
        d.fill(Path(roundedRect: CGRect(x: 205, y: bottom - 4, width: 190, height: 22), cornerRadius: 8), with: .color(Ink.gold))
        d.fill(Path(roundedRect: CGRect(x: 238, y: bottom + 18, width: 124, height: 12), cornerRadius: 4), with: .color(Ink.gold.opacity(0.8)))

        // Plunger: sits on top during the steep, then goes down.
        let seated = [.wait, .swirl, .serve, .press, .done].contains(stage)
        if seated {
            let travel = press * 190
            let top = 120 + travel
            var p = d
            p.fill(Path(roundedRect: CGRect(x: 236, y: top + 40, width: 128, height: 260), cornerRadius: 8),
                   with: .color(Color(red: 0.2, green: 0.18, blue: 0.16).opacity(0.9)))
            p.stroke(Path(roundedRect: CGRect(x: 236, y: top + 40, width: 128, height: 260), cornerRadius: 8),
                     with: .color(Ink.cream.opacity(0.45)), lineWidth: 4)
            p.fill(Path(roundedRect: CGRect(x: 214, y: top + 20, width: 172, height: 26), cornerRadius: 10), with: .color(Ink.gold))
            if pressing {
                // Hands pressing: two soft arrows.
                for n in 0..<2 {
                    let q = (t * 1.5 + Double(n) * 0.5).truncatingRemainder(dividingBy: 1)
                    var a = Path(); let y = top - 10 + q * 20
                    a.move(to: CGPoint(x: 280, y: y)); a.addLine(to: CGPoint(x: 300, y: y + 16)); a.addLine(to: CGPoint(x: 320, y: y))
                    p.stroke(a, with: .color(Ink.gold.opacity(1 - q)), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
            }
        }
        // Coffee streaming into the cup while pressing; the hiss puffs at the end.
        if pressing {
            var s = Path(); s.move(to: CGPoint(x: 300, y: bottom + 30)); s.addLine(to: CGPoint(x: 300, y: 620 - 150 * cupFill))
            context.stroke(s, with: .color(Ink.coffeeTop), style: StrokeStyle(lineWidth: 8 * (1 - state.progress * 0.6), lineCap: .round))
            if state.progress > 0.85 {
                for n in 0..<5 {
                    let q = (t * 2 + Double(n) * 0.2).truncatingRemainder(dividingBy: 1)
                    let p = CGPoint(x: 300 + cos(Double(n) * 1.3) * (30 + q * 60), y: bottom + 30 - q * 30)
                    context.fill(circle(p, 4 + q * 8), with: .color(Ink.cream.opacity(0.4 * (1 - q))))
                }
            }
        }

        // Kettle for the pours.
        if stage == .bloom || stage == .pour {
            let span = stage == .bloom ? 0.4 : 0.85
            let tilt = sin(clamp(state.progress / span) * .pi)
            let tip = kettle(&context, tilt: tilt, show: 1)
            if state.progress < span && tilt > 0.3 {
                pourStream(&context, from: tip, to: CGPoint(x: 300 + sin(t * 5) * 20, y: surface), width: 7, t: t)
            }
        }
        if done { steam(&context, xs: [270, 300, 330], baseY: 460, t: t, alpha: clamp(state.progress / 0.4)) }
    }
}

// MARK: Espresso

private struct EspressoPainter {
    let elapsed: Double
    let running: Bool
    let target: ClosedRange<Int>
    let t: Double

    func draw(_ context: inout GraphicsContext) {
        let goal = Double(target.lowerBound + target.upperBound) / 2
        let p = clamp(elapsed / goal, 0, 1.25)
        let flowing = running && elapsed > 4 // first drops after pre-infusion

        // Group head and portafilter.
        context.fill(Path(roundedRect: CGRect(x: 170, y: 40, width: 260, height: 70), cornerRadius: 14),
                     with: .color(Color(red: 0.22, green: 0.2, blue: 0.18)))
        context.stroke(Path(roundedRect: CGRect(x: 170, y: 40, width: 260, height: 70), cornerRadius: 14),
                       with: .color(Ink.cream.opacity(0.4)), lineWidth: 4)
        var basket = Path()
        basket.move(to: CGPoint(x: 190, y: 110)); basket.addLine(to: CGPoint(x: 410, y: 110))
        basket.addCurve(to: CGPoint(x: 190, y: 110), control1: CGPoint(x: 400, y: 190), control2: CGPoint(x: 200, y: 190))
        context.fill(basket, with: .color(Ink.gold))
        var arm = Path(); arm.move(to: CGPoint(x: 410, y: 130)); arm.addLine(to: CGPoint(x: 560, y: 150))
        context.stroke(arm, with: .color(Color(red: 0.24, green: 0.16, blue: 0.1)), style: StrokeStyle(lineWidth: 28, lineCap: .round))
        for x in [276.0, 324] {
            context.fill(Path(roundedRect: CGRect(x: x - 10, y: 168, width: 20, height: 34), cornerRadius: 6), with: .color(Ink.gold.opacity(0.85)))
        }

        // Cup and the shot in it.
        let cup = Path { c in
            c.move(to: CGPoint(x: 210, y: 420))
            c.addLine(to: CGPoint(x: 390, y: 420))
            c.addCurve(to: CGPoint(x: 210, y: 420), control1: CGPoint(x: 385, y: 600), control2: CGPoint(x: 215, y: 600))
        }
        let level = min(p, 1)
        let surface = 560 - 125 * level
        context.drawLayer { c in
            c.clip(to: cup)
            c.fill(Path(CGRect(x: 200, y: surface, width: 200, height: 200)), with: .color(Ink.coffee))
            if level > 0.05 {
                let crema = 6 + 14 * level
                c.fill(Path(CGRect(x: 200, y: surface, width: 200, height: crema)),
                       with: .linearGradient(Gradient(colors: [Color(red: 0.82, green: 0.56, blue: 0.28), Color(red: 0.55, green: 0.33, blue: 0.15)]),
                                             startPoint: CGPoint(x: 300, y: surface), endPoint: CGPoint(x: 300, y: surface + crema)))
                for i in 0..<10 {
                    let q = CGPoint(x: 230 + noise(i) * 140, y: surface + 3 + noise(i, 1) * crema * 0.6)
                    c.fill(circle(q, 2 + noise(i, 2) * 3), with: .color(Color(red: 0.95, green: 0.78, blue: 0.5).opacity(0.5)))
                }
            }
        }
        context.stroke(cup, with: .color(Ink.cream.opacity(0.6)), lineWidth: 5)
        var handle = Path()
        handle.move(to: CGPoint(x: 382, y: 450))
        handle.addCurve(to: CGPoint(x: 360, y: 530), control1: CGPoint(x: 440, y: 450), control2: CGPoint(x: 430, y: 530))
        context.stroke(handle, with: .color(Ink.cream.opacity(0.4)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: 160, y: 590, width: 280, height: 30)), with: .color(Ink.cream.opacity(0.15)))

        // Two streams: dark at first, honey in the middle, blonde past the target.
        if flowing {
            let color: Color = p < 0.25 ? Color(red: 0.24, green: 0.12, blue: 0.05)
                : p < 0.9 ? Color(red: 0.62, green: 0.36, blue: 0.14) : Color(red: 0.86, green: 0.66, blue: 0.38)
            for (n, x) in [276.0, 324].enumerated() {
                var s = Path()
                let wobble = sin(t * 9 + Double(n)) * 2
                s.move(to: CGPoint(x: x, y: 202))
                s.addQuadCurve(to: CGPoint(x: 300 + (x - 300) * 0.4 + wobble, y: surface),
                               control: CGPoint(x: x + wobble, y: (202 + surface) / 2))
                context.stroke(s, with: .color(color), style: StrokeStyle(lineWidth: p > 0.9 ? 4 : 6, lineCap: .round))
            }
        } else if running {
            // Pre-infusion: a bead forming on each spout.
            for x in [276.0, 324] {
                let r = 3 + clamp(elapsed / 4) * 5
                context.fill(circle(CGPoint(x: x, y: 206 + r / 2), r), with: .color(Color(red: 0.3, green: 0.16, blue: 0.07)))
            }
        }
        if !running && elapsed > 0 { steam(&context, xs: [270, 300, 330], baseY: 400, t: t, alpha: 1) }
    }
}

// MARK: Arabic coffee (the dalla)

private struct DallaPainter {
    let state: BrewSceneState
    let t: Double

    func draw(_ context: inout GraphicsContext) {
        let stage = state.stage
        let serving = stage == .serve
        let done = stage == .done
        let pourTilt = serving ? easeInOut(clamp(state.progress / 0.3)) * (1 - easeInOut(clamp((state.progress - 0.85) / 0.15))) : 0
        let heat: Double = {
            switch stage {
            case .heat, .addCoffee: return 1
            case .simmer, .addCardamom: return 0.45
            default: return 0
            }
        }()

        // Stove ring and flame.
        context.fill(Path(roundedRect: CGRect(x: 170, y: 560, width: 260, height: 18), cornerRadius: 9), with: .color(Color(red: 0.25, green: 0.22, blue: 0.2)))
        if heat > 0 && !serving { flame(&context, strength: heat) }

        // Finjan and dates, front left, when serving or done.
        if serving || done {
            let fill = done ? 1 : clamp((state.progress - 0.3) / 0.55)
            finjan(&context, fill: fill)
        }

        // The dalla, tilting to pour.
        var d = context
        let pivot = CGPoint(x: 330, y: 420)
        d.translateBy(x: pivot.x, y: pivot.y)
        d.rotate(by: .degrees(-38 * pourTilt))
        d.translateBy(x: -pivot.x, y: -pivot.y)
        if done { d.opacity = 0.9 }
        dalla(&d)

        if pourTilt > 0.6 {
            let angle = -38 * pourTilt * .pi / 180
            let tip = CGPoint(x: 112, y: 214)
            let rx = tip.x - pivot.x, ry = tip.y - pivot.y
            let start = CGPoint(x: pivot.x + rx * cos(angle) - ry * sin(angle), y: pivot.y + rx * sin(angle) + ry * cos(angle))
            var s = Path()
            s.move(to: start)
            s.addQuadCurve(to: CGPoint(x: 150, y: 520), control: CGPoint(x: start.x - 20, y: (start.y + 520) / 2))
            context.stroke(s, with: .color(Color(red: 0.76, green: 0.58, blue: 0.3)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }

        // What goes in: coffee or cardamom falling into the mouth.
        if stage == .addCoffee || stage == .addCardamom {
            let cardamom = stage == .addCardamom
            for i in 0..<(cardamom ? 9 : 26) {
                let q = clamp((state.progress - noise(i, 1) * 0.5) / 0.4)
                guard q > 0 && q < 1 else { continue }
                let p = CGPoint(x: 300 + (noise(i) - 0.5) * 40, y: lerp(90, 250, q * q))
                if cardamom {
                    var pod = context
                    pod.translateBy(x: p.x, y: p.y)
                    pod.rotate(by: .degrees(noise(i, 2) * 180 + q * 200))
                    pod.fill(Path(ellipseIn: CGRect(x: -9, y: -5, width: 18, height: 10)), with: .color(Color(red: 0.55, green: 0.66, blue: 0.36)))
                } else {
                    context.fill(circle(p, 2.5 + noise(i, 2) * 2), with: .color(Ink.groundsDry))
                }
            }
        }

        // Rising foam and bubbles at the mouth while it boils; steam when resting.
        if [.heat, .addCoffee, .simmer, .addCardamom].contains(stage) {
            let boil = stage == .heat ? clamp((state.progress - 0.5) / 0.5) : 1
            for i in 0..<10 {
                let q = (t * (0.9 + heat) + noise(i, 3)).truncatingRemainder(dividingBy: 1)
                let p = CGPoint(x: 284 + noise(i, 4) * 32, y: 252 - q * 26)
                context.stroke(circle(p, (2 + noise(i, 5) * 4) * sin(q * .pi) * boil), with: .color(Ink.cream.opacity(0.6)), lineWidth: 2)
            }
            if stage == .simmer {
                // The froth rises and is calmed, again and again.
                let rise = max(0, sin(state.progress * .pi * 6)) * 14
                context.fill(Path(ellipseIn: CGRect(x: 276, y: 246 - rise, width: 48, height: 14 + rise)),
                             with: .color(Color(red: 0.78, green: 0.62, blue: 0.4).opacity(0.85)))
            }
        }
        if stage == .settle || done {
            steam(&context, xs: done ? [130, 160] : [290, 320], baseY: done ? 470 : 250, t: t, alpha: 0.8)
        }
    }

    private func flame(_ c: inout GraphicsContext, strength: Double) {
        for i in 0..<7 {
            let x = 200 + Double(i) * 33
            let flick = 0.75 + 0.25 * sin(t * 11 + Double(i) * 1.7)
            let h = (26 + 34 * strength) * flick
            var f = Path()
            f.move(to: CGPoint(x: x - 10, y: 560))
            f.addQuadCurve(to: CGPoint(x: x, y: 560 - h), control: CGPoint(x: x - 12, y: 560 - h * 0.5))
            f.addQuadCurve(to: CGPoint(x: x + 10, y: 560), control: CGPoint(x: x + 12, y: 560 - h * 0.5))
            c.fill(f, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.78, blue: 0.3), Color(red: 0.95, green: 0.42, blue: 0.12), Color(red: 0.3, green: 0.45, blue: 0.95)]),
                                            startPoint: CGPoint(x: x, y: 560 - h), endPoint: CGPoint(x: x, y: 560)))
        }
    }

    private func dalla(_ c: inout GraphicsContext) {
        let brass = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Color(red: 0.93, green: 0.78, blue: 0.45), Ink.gold, Color(red: 0.5, green: 0.36, blue: 0.14)]),
            startPoint: CGPoint(x: 200, y: 300), endPoint: CGPoint(x: 420, y: 520))
        // Body.
        var body = Path()
        body.move(to: CGPoint(x: 270, y: 300))
        body.addCurve(to: CGPoint(x: 220, y: 540), control1: CGPoint(x: 200, y: 360), control2: CGPoint(x: 190, y: 500))
        body.addLine(to: CGPoint(x: 380, y: 540))
        body.addCurve(to: CGPoint(x: 330, y: 300), control1: CGPoint(x: 410, y: 500), control2: CGPoint(x: 400, y: 360))
        body.closeSubpath()
        c.fill(body, with: brass)
        // Neck.
        var neck = Path()
        neck.move(to: CGPoint(x: 270, y: 300)); neck.addLine(to: CGPoint(x: 282, y: 250))
        neck.addLine(to: CGPoint(x: 318, y: 250)); neck.addLine(to: CGPoint(x: 330, y: 300)); neck.closeSubpath()
        c.fill(neck, with: brass)
        // Lid with its finial (lifted while adding things).
        let open = state.stage == .addCoffee || state.stage == .addCardamom
        var lid = c
        if open { lid.translateBy(x: 70, y: -70); lid.opacity = 0.9 }
        var cap = Path()
        cap.move(to: CGPoint(x: 276, y: 252)); cap.addLine(to: CGPoint(x: 300, y: 190)); cap.addLine(to: CGPoint(x: 324, y: 252)); cap.closeSubpath()
        lid.fill(cap, with: brass)
        lid.fill(circle(CGPoint(x: 300, y: 182), 10), with: brass)
        // Long beak spout.
        var beak = Path()
        beak.move(to: CGPoint(x: 236, y: 360))
        beak.addCurve(to: CGPoint(x: 112, y: 214), control1: CGPoint(x: 180, y: 330), control2: CGPoint(x: 140, y: 260))
        beak.addLine(to: CGPoint(x: 128, y: 210))
        beak.addCurve(to: CGPoint(x: 252, y: 330), control1: CGPoint(x: 160, y: 262), control2: CGPoint(x: 200, y: 300))
        beak.closeSubpath()
        c.fill(beak, with: brass)
        // Handle.
        var handle = Path()
        handle.move(to: CGPoint(x: 336, y: 300))
        handle.addCurve(to: CGPoint(x: 392, y: 470), control1: CGPoint(x: 430, y: 300), control2: CGPoint(x: 440, y: 420))
        c.stroke(handle, with: .color(Ink.gold), style: StrokeStyle(lineWidth: 12, lineCap: .round))
        // Bands.
        for y in [330.0, 500] {
            var band = Path(); band.move(to: CGPoint(x: 220, y: y)); band.addLine(to: CGPoint(x: 380, y: y))
            c.stroke(band, with: .color(Color(red: 0.4, green: 0.28, blue: 0.1).opacity(0.5)), lineWidth: 4)
        }
        c.stroke(body, with: .color(Color(red: 0.98, green: 0.88, blue: 0.6).opacity(0.5)), lineWidth: 2)
    }

    private func finjan(_ c: inout GraphicsContext, fill: Double) {
        let cup = Path { p in
            p.move(to: CGPoint(x: 110, y: 520))
            p.addLine(to: CGPoint(x: 190, y: 520))
            p.addCurve(to: CGPoint(x: 110, y: 520), control1: CGPoint(x: 186, y: 590), control2: CGPoint(x: 114, y: 590))
        }
        c.drawLayer { l in
            l.clip(to: cup)
            l.fill(Path(CGRect(x: 100, y: 520, width: 100, height: 80)), with: .color(Ink.cream))
            let top = 572 - 40 * fill
            l.fill(Path(CGRect(x: 100, y: top, width: 100, height: 80)), with: .color(Color(red: 0.76, green: 0.58, blue: 0.3)))
        }
        c.stroke(cup, with: .color(Ink.gold), lineWidth: 4)
        // Two dates on a small plate.
        c.fill(Path(ellipseIn: CGRect(x: 420, y: 585, width: 120, height: 22)), with: .color(Ink.cream.opacity(0.25)))
        for x in [450.0, 490] {
            c.fill(Path(ellipseIn: CGRect(x: x, y: 566, width: 34, height: 22)), with: .color(Color(red: 0.36, green: 0.18, blue: 0.08)))
        }
    }
}

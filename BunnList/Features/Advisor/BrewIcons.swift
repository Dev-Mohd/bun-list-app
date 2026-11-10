import BunnListCore
import SwiftUI

// Drawn pictures of the real tools and drinks, in place of emoji that only hinted at them:
// the V60 on its server, an espresso cup with crema, the Chemex with its wooden collar, the
// French press, a steaming cup, an iced glass, and each milk drink as a glass whose layers
// are the drink's own proportions (espresso, milk, foam).

private let inkColor = Color(red: 0.09, green: 0.078, blue: 0.067)
private let coffee = Color(red: 0.29, green: 0.2, blue: 0.16)
private let crema = Color(red: 0.78, green: 0.6, blue: 0.36)
private let milkColor = Color(red: 0.96, green: 0.93, blue: 0.87)
private let foamColor = Color(red: 1, green: 0.99, blue: 0.97)
private let glassColor = Color(red: 0.86, green: 0.9, blue: 0.9)
private let wood = Color(red: 0.6, green: 0.44, blue: 0.14)

/// A brewer or a serving, drawn on a 64-point grid and scaled to `size`.
struct BrewIcon: View {
    enum Kind { case v60, espresso, chemex, frenchPress, hot, iced, milk, black }
    let kind: Kind
    var size: CGFloat = 56

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 64
            ctx.scaleBy(x: s, y: s)
            let line = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            func stroke(_ p: Path) { ctx.stroke(p, with: .color(inkColor), style: line) }
            func fill(_ p: Path, _ c: Color) { ctx.fill(p, with: .color(c)) }
            func path(_ build: (inout Path) -> Void) -> Path { var p = Path(); build(&p); return p }
            func steam(_ x: CGFloat, _ y: CGFloat) {
                ctx.stroke(path { p in
                    p.move(to: CGPoint(x: x, y: y)); p.addCurve(to: CGPoint(x: x, y: y - 10), control1: CGPoint(x: x - 4, y: y - 3), control2: CGPoint(x: x + 4, y: y - 7))
                }, with: .color(inkColor.opacity(0.45)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }

            switch kind {
            case .v60:
                // Server with coffee, then the cone on top.
                let server = path { p in
                    p.move(to: CGPoint(x: 20, y: 38)); p.addLine(to: CGPoint(x: 44, y: 38))
                    p.addLine(to: CGPoint(x: 48, y: 58)); p.addLine(to: CGPoint(x: 16, y: 58)); p.closeSubpath()
                }
                fill(path { p in
                    p.move(to: CGPoint(x: 17.5, y: 50)); p.addLine(to: CGPoint(x: 46.5, y: 50))
                    p.addLine(to: CGPoint(x: 48, y: 58)); p.addLine(to: CGPoint(x: 16, y: 58)); p.closeSubpath()
                }, coffee)
                stroke(server)
                let cone = path { p in
                    p.move(to: CGPoint(x: 12, y: 10)); p.addLine(to: CGPoint(x: 52, y: 10))
                    p.addLine(to: CGPoint(x: 36, y: 32)); p.addLine(to: CGPoint(x: 28, y: 32)); p.closeSubpath()
                }
                fill(cone, foamColor)
                stroke(cone)
                // The spiral ribs.
                ctx.stroke(path { p in
                    p.move(to: CGPoint(x: 22, y: 12)); p.addLine(to: CGPoint(x: 30, y: 30))
                    p.move(to: CGPoint(x: 32, y: 12)); p.addLine(to: CGPoint(x: 32, y: 30))
                    p.move(to: CGPoint(x: 42, y: 12)); p.addLine(to: CGPoint(x: 34, y: 30))
                }, with: .color(inkColor.opacity(0.3)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                stroke(path { p in p.move(to: CGPoint(x: 22, y: 34)); p.addLine(to: CGPoint(x: 42, y: 34)) })
                stroke(path { p in p.addArc(center: CGPoint(x: 52, y: 17), radius: 5, startAngle: .degrees(-80), endAngle: .degrees(80), clockwise: false) })

            case .espresso, .black:
                // A demitasse with crema on a saucer.
                let cup = path { p in
                    p.move(to: CGPoint(x: 16, y: 28)); p.addLine(to: CGPoint(x: 44, y: 28))
                    p.addQuadCurve(to: CGPoint(x: 37, y: 48), control: CGPoint(x: 44, y: 44))
                    p.addLine(to: CGPoint(x: 23, y: 48)); p.addQuadCurve(to: CGPoint(x: 16, y: 28), control: CGPoint(x: 16, y: 44))
                }
                fill(cup, foamColor)
                fill(path { p in p.addEllipse(in: CGRect(x: 17, y: 25, width: 26, height: 6)) }, kind == .black ? coffee : crema)
                stroke(cup)
                stroke(path { p in p.addEllipse(in: CGRect(x: 17, y: 25, width: 26, height: 6)) })
                stroke(path { p in p.addArc(center: CGPoint(x: 45, y: 35), radius: 5, startAngle: .degrees(-70), endAngle: .degrees(90), clockwise: false) })
                stroke(path { p in p.move(to: CGPoint(x: 10, y: 53)); p.addQuadCurve(to: CGPoint(x: 50, y: 53), control: CGPoint(x: 30, y: 58)) })
                steam(25, 20); steam(34, 20)

            case .chemex:
                let body = path { p in
                    p.move(to: CGPoint(x: 18, y: 6)); p.addLine(to: CGPoint(x: 46, y: 6))
                    p.addLine(to: CGPoint(x: 35, y: 28)); p.addLine(to: CGPoint(x: 49, y: 54))
                    p.addQuadCurve(to: CGPoint(x: 15, y: 54), control: CGPoint(x: 32, y: 62))
                    p.addLine(to: CGPoint(x: 29, y: 28)); p.closeSubpath()
                }
                fill(body, foamColor)
                fill(path { p in
                    p.move(to: CGPoint(x: 21.5, y: 42)); p.addLine(to: CGPoint(x: 42.5, y: 42))
                    p.addLine(to: CGPoint(x: 49, y: 54)); p.addQuadCurve(to: CGPoint(x: 15, y: 54), control: CGPoint(x: 32, y: 62)); p.closeSubpath()
                }, coffee)
                stroke(body)
                // The wooden collar and its tie.
                fill(path { p in p.addRoundedRect(in: CGRect(x: 25, y: 23, width: 14, height: 9), cornerSize: CGSize(width: 2, height: 2)) }, wood)
                stroke(path { p in p.addRoundedRect(in: CGRect(x: 25, y: 23, width: 14, height: 9), cornerSize: CGSize(width: 2, height: 2)) })
                fill(path { p in p.addEllipse(in: CGRect(x: 39, y: 25.5, width: 4, height: 4)) }, wood)

            case .frenchPress:
                let jar = path { p in p.addRoundedRect(in: CGRect(x: 16, y: 18, width: 26, height: 38), cornerSize: CGSize(width: 3, height: 3)) }
                fill(jar, foamColor)
                fill(path { p in p.addRoundedRect(in: CGRect(x: 17, y: 34, width: 24, height: 21), cornerSize: CGSize(width: 2, height: 2)) }, coffee)
                stroke(jar)
                // Plunger: knob, rod, and the mesh sitting on the coffee.
                stroke(path { p in p.move(to: CGPoint(x: 29, y: 8)); p.addLine(to: CGPoint(x: 29, y: 33)) })
                fill(path { p in p.addEllipse(in: CGRect(x: 25, y: 4, width: 8, height: 6)) }, inkColor)
                stroke(path { p in p.move(to: CGPoint(x: 14, y: 18)); p.addLine(to: CGPoint(x: 44, y: 18)) })
                stroke(path { p in p.move(to: CGPoint(x: 18, y: 33.5)); p.addLine(to: CGPoint(x: 40, y: 33.5)) })
                stroke(path { p in
                    p.move(to: CGPoint(x: 42, y: 24)); p.addQuadCurve(to: CGPoint(x: 42, y: 48), control: CGPoint(x: 56, y: 36))
                })

            case .hot:
                let mug = path { p in
                    p.move(to: CGPoint(x: 14, y: 24)); p.addLine(to: CGPoint(x: 44, y: 24))
                    p.addLine(to: CGPoint(x: 41, y: 54)); p.addLine(to: CGPoint(x: 17, y: 54)); p.closeSubpath()
                }
                fill(mug, foamColor)
                fill(path { p in p.addEllipse(in: CGRect(x: 15, y: 21, width: 28, height: 6)) }, coffee)
                stroke(mug)
                stroke(path { p in p.addEllipse(in: CGRect(x: 15, y: 21, width: 28, height: 6)) })
                stroke(path { p in p.addArc(center: CGPoint(x: 45, y: 36), radius: 7, startAngle: .degrees(-75), endAngle: .degrees(85), clockwise: false) })
                steam(22, 16); steam(30, 14); steam(38, 16)

            case .iced:
                let glass = path { p in
                    p.move(to: CGPoint(x: 16, y: 10)); p.addLine(to: CGPoint(x: 48, y: 10))
                    p.addLine(to: CGPoint(x: 43, y: 58)); p.addLine(to: CGPoint(x: 21, y: 58)); p.closeSubpath()
                }
                fill(glass, glassColor.opacity(0.6))
                fill(path { p in
                    p.move(to: CGPoint(x: 17.5, y: 24)); p.addLine(to: CGPoint(x: 46.5, y: 24))
                    p.addLine(to: CGPoint(x: 43, y: 58)); p.addLine(to: CGPoint(x: 21, y: 58)); p.closeSubpath()
                }, coffee.opacity(0.85))
                for box in [CGRect(x: 22, y: 26, width: 10, height: 10), CGRect(x: 33, y: 31, width: 9, height: 9), CGRect(x: 25, y: 40, width: 9, height: 9)] {
                    let cube = path { p in p.addRoundedRect(in: box, cornerSize: CGSize(width: 2, height: 2)) }
                    fill(cube, foamColor.opacity(0.75))
                    ctx.stroke(cube, with: .color(inkColor.opacity(0.35)), lineWidth: 1.2)
                }
                stroke(glass)
                // Straw.
                stroke(path { p in p.move(to: CGPoint(x: 40, y: 4)); p.addLine(to: CGPoint(x: 34, y: 44)) })

            case .milk:
                // A pitcher of milk beside the cup's idea: the steaming jug.
                let jug = path { p in
                    p.move(to: CGPoint(x: 18, y: 16)); p.addLine(to: CGPoint(x: 42, y: 16)); p.addLine(to: CGPoint(x: 48, y: 11))
                    p.addLine(to: CGPoint(x: 44, y: 22)); p.addLine(to: CGPoint(x: 46, y: 56)); p.addLine(to: CGPoint(x: 16, y: 56)); p.closeSubpath()
                }
                fill(jug, glassColor)
                fill(path { p in
                    p.move(to: CGPoint(x: 17.3, y: 30)); p.addLine(to: CGPoint(x: 44.6, y: 30))
                    p.addLine(to: CGPoint(x: 46, y: 56)); p.addLine(to: CGPoint(x: 16, y: 56)); p.closeSubpath()
                }, milkColor)
                stroke(jug)
                stroke(path { p in p.move(to: CGPoint(x: 17.3, y: 30)); p.addLine(to: CGPoint(x: 44.6, y: 30)) })
                stroke(path { p in p.addArc(center: CGPoint(x: 15, y: 36), radius: 8, startAngle: .degrees(100), endAngle: .degrees(260), clockwise: false) })
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A milk drink as a glass: espresso at the bottom, milk, then foam, in the drink's own proportions,
/// and the glass as tall as the drink is big.
struct MilkDrinkGlass: View {
    let drink: MilkDrink
    var size: CGFloat = 56

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 64
            ctx.scaleBy(x: s, y: s)
            // Height follows the cup (120–300 ml → 30–50 pt).
            let h = 26 + CGFloat(min(max(drink.cupMl, 90), 300) - 90) / 210 * 26
            let top = 58 - h
            let left: CGFloat = 18, right: CGFloat = 46, inset: CGFloat = 3
            func x(_ y: CGFloat, _ leftSide: Bool) -> CGFloat {
                let t = (y - top) / h
                return leftSide ? left + inset * t : right - inset * t
            }
            func band(_ y0: CGFloat, _ y1: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: x(y0, true), y: y0)); p.addLine(to: CGPoint(x: x(y0, false), y: y0))
                p.addLine(to: CGPoint(x: x(y1, false), y: y1)); p.addLine(to: CGPoint(x: x(y1, true), y: y1)); p.closeSubpath()
                return p
            }
            let espresso: CGFloat = 36, milk = CGFloat(drink.typicalMilkGrams)
            let foam = milk * (drink == .cappuccino ? 0.45 : drink == .macchiato ? 0.8 : 0.18)
            let total = espresso + milk + foam
            let inner = h - 3
            let eH = inner * espresso / total, mH = inner * milk / total
            let bottom: CGFloat = 58
            ctx.fill(band(bottom - eH, bottom), with: .color(coffee))
            ctx.fill(band(bottom - eH - mH, bottom - eH), with: .color(Color(red: 0.8, green: 0.64, blue: 0.47)))
            ctx.fill(band(top + 3, bottom - eH - mH), with: .color(foamColor))
            ctx.stroke(band(top, bottom), with: .color(inkColor), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
            var lines = Path()
            for y in [bottom - eH, bottom - eH - mH] { lines.move(to: CGPoint(x: x(y, true), y: y)); lines.addLine(to: CGPoint(x: x(y, false), y: y)) }
            ctx.stroke(lines, with: .color(inkColor.opacity(0.25)), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A milk drink explained: its glass, the amounts, the foam, and how to steam the milk.
struct MilkGuideCard: View {
    let drink: MilkDrink
    var milkGrams: Double? = nil
    var onDark = false
    var showsSteps = true

    private var primary: Color { onDark ? .white : Brand.ink }
    private var secondary: Color { onDark ? .white.opacity(0.7) : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MilkDrinkGlass(drink: drink, size: 60)
                    .padding(6).background(Color(red: 0.97, green: 0.945, blue: 0.91), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(drink.nameAr).font(.title3.bold()).foregroundStyle(primary)
                    Text(drink.summaryAr).font(.footnote).foregroundStyle(secondary)
                }
            }
            HStack(spacing: 8) {
                amount("٣٦غ", "إسبريسو")
                amount("\(RecipeText.number(milkGrams ?? drink.typicalMilkGrams))غ", "حليب")
                amount("\(drink.cupMl) مل", "الكوب")
                amount("٥٥–٦٥°", "حرارة الحليب")
            }
            Label(drink.textureAr, systemImage: "bubbles.and.sparkles").font(.footnote.weight(.semibold))
                .foregroundStyle(onDark ? Color(red: 0.89, green: 0.72, blue: 0.36) : Brand.olive)
            if showsSteps {
                VStack(alignment: .leading, spacing: 8) {
                    Text("طريقة تبخير الحليب").font(.subheadline.bold()).foregroundStyle(primary)
                    ForEach(Array(drink.steamingAr.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text((i + 1).formatted()).font(.caption.bold()).foregroundStyle(onDark ? .black : .white)
                                .frame(width: 20, height: 20).background(onDark ? Color(red: 0.89, green: 0.72, blue: 0.36) : Brand.olive, in: Circle())
                            Text(step).font(.footnote).foregroundStyle(secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(onDark ? Color.white.opacity(0.08) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func amount(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold()).foregroundStyle(primary)
            Text(label).font(.caption2).foregroundStyle(secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(onDark ? Color.white.opacity(0.08) : Brand.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

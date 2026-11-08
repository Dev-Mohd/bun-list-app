import BunnListCore
import SwiftUI

// The recipe editor's step parts (approved mockup, same as Android): the basics (coffee, water, temperature),
// the simple editor (how many pours, bloom, a draggable timeline), the advanced editor (one row per step, details
// inline, drag ≡ to reorder, «＋ صبّة» and «＋ إضافة خطوة»), the water check, and «مراجعة الوصفة».

private func mmss(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
private func g(_ v: Double?) -> String { RecipeText.number(v) }

/// − value + in one row, left-to-right so minus stays on the left.
struct StepperPill: View {
    let value: String
    var size: CGFloat = 28
    let onMinus: () -> Void
    let onPlus: () -> Void
    var onTapValue: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            round("minus", onMinus).accessibilityLabel("أقل")
            Text(value).font(.subheadline.bold().monospacedDigit()).frame(minWidth: 52)
                .contentShape(Rectangle())
                .onTapGesture { onTapValue?() }
            round("plus", onPlus).accessibilityLabel("أكثر")
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func round(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button { action(); Haptics.tap() } label: {
            Image(systemName: symbol).font(.caption.bold())
                .frame(width: size, height: size)
                .background(Brand.background, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct EditorSection<Content: View>: View {
    let title: String?
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    if let trailing { Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: Basics

/// Coffee, water and water temperature side by side; the temperature may stay «غير محددة».
struct RecipeBasicsCard: View {
    @Binding var draft: RecipeDraft
    @State private var typing: Field?
    @State private var text = ""

    private enum Field: String, Identifiable { case dose, water, yield, temp; var id: String { rawValue } }

    var body: some View {
        let dose = draft.doseGrams ?? (draft.isEspresso ? 18 : 15)
        let step = draft.isEspresso ? 0.5 : 1
        EditorSection(title: nil) {
            HStack(alignment: .top, spacing: 6) {
                box("البن", "\(g(dose))غ", minus: { draft.setDose(max(dose - step, 1)) }, plus: { draft.setDose(min(dose + step, 1000)) }) { start(.dose, dose) }
                if draft.isEspresso {
                    let y = draft.yieldGrams ?? 36
                    box("الشوت", "\(g(y))غ", minus: { draft.yieldGrams = max(y - 1, 1) }, plus: { draft.yieldGrams = y + 1 }) { start(.yield, y) }
                } else {
                    let w = draft.hotWaterGrams ?? 0
                    box("الماء", "\(g(w))غ", minus: { draft.setHotWater(max(w - 10, 10)) }, plus: { draft.setHotWater(w + 10) }) { start(.water, w) }
                }
                VStack(spacing: 4) {
                    box("حرارة الماء", draft.waterTempC.map { "\(g($0))°" } ?? "غير محددة",
                        minus: { draft.waterTempC = max((draft.waterTempC ?? 93) - 1, 1) },
                        plus: { draft.waterTempC = min((draft.waterTempC ?? 91) + 1, 100) }) { start(.temp, draft.waterTempC) }
                    Button(draft.waterTempC == nil ? "حدّدها" : "غير محددة؟") {
                        draft.waterTempC = draft.waterTempC == nil ? 93 : nil
                    }
                    .font(.caption2.bold()).foregroundStyle(Brand.gold).buttonStyle(.plain)
                }
            }
            let ratio = draft.ratio.map { "النسبة \(RecipeText.ratio($0))" }
            Text([ratio, draft.waterTempC != nil && !draft.isEspresso ? "الحرارة لكل الصبّات" : nil].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.bold()).foregroundStyle(Brand.olive).frame(maxWidth: .infinity)
        }
        .alert(title(typing), isPresented: Binding(get: { typing != nil }, set: { if !$0 { typing = nil } })) {
            TextField("", text: $text).keyboardType(.decimalPad)
            Button("تم") { commit() }
            Button("إلغاء", role: .cancel) {}
        }
    }

    private func box(_ label: String, _ value: String, minus: @escaping () -> Void, plus: @escaping () -> Void, tap: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(value.count > 6 ? .footnote.bold() : .title3.bold()).monospacedDigit()
                .contentTransition(.numericText())
                .onTapGesture(perform: tap)
            HStack(spacing: 12) {
                mini("minus", minus); mini("plus", plus)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Brand.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private func mini(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button { action(); Haptics.tap() } label: {
            Image(systemName: symbol).font(.caption2.bold()).frame(width: 24, height: 24)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func start(_ field: Field, _ value: Double?) { text = value.map { g($0) } ?? ""; typing = field }

    private func title(_ field: Field?) -> String {
        switch field {
        case .dose: return "البن (غ)"
        case .water: return "الماء (غ)"
        case .yield: return "الشوت (غ)"
        case .temp: return "حرارة الماء (°م)"
        case nil: return ""
        }
    }

    private func commit() {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")), v > 0 else { return }
        switch typing {
        case .dose: draft.setDose(v)
        case .water: draft.setHotWater(v)
        case .yield: draft.yieldGrams = v
        case .temp: draft.waterTempC = min(v, 100)
        case nil: break
        }
    }
}

// MARK: Simple

/// «كم صبّة؟», bloom, and the timeline: drag a pour to move its start, tap it to set its start and what it adds.
struct SimpleStepsEditor: View {
    @Binding var draft: RecipeDraft
    @State private var selected: Int?
    @AppStorage("timelineHintSeen") private var hintSeen = false

    var body: some View {
        let pours = draft.pourCount
        EditorSection(title: "كم صبّة؟", trailing: draft.hasBloom ? "\(pours.formatted()) \(pours == 1 ? "صبّة" : "صبّات") بعد التشريب" : "\(pours.formatted()) \(pours == 1 ? "صبّة" : "صبّات")") {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { n in
                    Button { selected = nil; draft.simplePours(n, bloom: draft.hasBloom); Haptics.tap() } label: {
                        Text(n.formatted()).font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(n == pours ? Brand.ink : Brand.background, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(n == pours ? Brand.background : Brand.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            Toggle(isOn: Binding(get: { draft.hasBloom }, set: { on in selected = nil; draft.simplePours(max(pours, 1), bloom: on) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("تشريب في البداية").font(.subheadline.bold())
                    if draft.hasBloom {
                        Text("\(g(draft.steps.first?.addedWaterGrams))غ · تعدّله من نقطة «تشريب»").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(Brand.olive)
        }
        EditorSection(title: "شكل وصفتك") {
            timeline
            if !hintSeen && selected == nil {
                Text("اسحب أي نقطة تغيّر وقتها، واضغطها تعدّل كميتها")
                    .font(.caption).foregroundStyle(.white)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.olive, in: RoundedRectangle(cornerRadius: 12))
            }
            if let i = selected, draft.steps.indices.contains(i) { editPanel(i) }
            HStack {
                Text("وقت الانتهاء المتوقع").font(.caption)
                Spacer()
                let lastStart = draft.startTimes.last ?? 0
                StepperPill(value: mmss(draft.totalSeconds), onMinus: { draft.setFinish(max(draft.totalSeconds - 5, lastStart)) },
                            onPlus: { draft.setFinish(min(draft.totalSeconds + 5, 3600)) })
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Brand.background, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var timeline: some View {
        GeometryReader { geo in
            let total = Double(max(draft.totalSeconds, 1))
            let pad: CGFloat = 26
            let usable = geo.size.width - pad * 2
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.secondary.opacity(0.18)).frame(height: 6)
                    .position(x: geo.size.width / 2, y: 50)
                    .padding(.horizontal, 8)
                ForEach(draft.waterIndices, id: \.self) { i in
                    let step = draft.steps[i]
                    // Right-to-left: 0:00 on the right edge.
                    let x = geo.size.width - pad - CGFloat(Double(draft.startTimes[i]) / total) * usable
                    let isOn = selected == i
                    let bloom = step.kind == .bloom
                    let number = draft.steps[...i].filter { $0.kind == .pour }.count
                    if isOn {
                        Text("أضف \(g(step.addedWaterGrams))غ · حتى يصل الميزان \(g(draft.cumulativeWater[i]))غ")
                            .font(.caption2).foregroundStyle(Brand.background)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Brand.ink, in: Capsule())
                            .fixedSize()
                            .position(x: min(max(x, 90), geo.size.width - 90), y: 12)
                    }
                    VStack(spacing: 3) {
                        Text(bloom ? "تشريب" : number.formatted())
                            .font(bloom ? .caption2.bold() : .caption.bold()).foregroundStyle(.white)
                            .frame(width: bloom ? 50 : (isOn ? 34 : 28), height: isOn ? 34 : 28)
                            .background(bloom ? Brand.gold : Brand.olive, in: Capsule())
                            .overlay(Capsule().stroke(Brand.olive.opacity(isOn ? 0.35 : 0), lineWidth: 4))
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                        Text(mmss(draft.startTimes[i])).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .position(x: x, y: 58)
                    .onTapGesture { selected = i; hintSeen = true }
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("timeline")).onChanged { value in
                        selected = i; hintSeen = true
                        guard i > 0 else { return }
                        let t = Double(geo.size.width - pad - value.location.x) / Double(usable) * total
                        draft.setStart(i, to: Int(t.rounded()))
                    })
                }
            }
            .coordinateSpace(name: "timeline")
        }
        .frame(height: 96)
        .environment(\.layoutDirection, .leftToRight)
        .animation(.snappy, value: draft.startTimes)
    }

    private func editPanel(_ i: Int) -> some View {
        let step = draft.steps[i]
        let number = draft.steps[...i].filter { $0.kind == .pour }.count
        let title = step.kind == .bloom ? "التشريب" : "صبّة \(number.formatted())"
        return VStack(spacing: 6) {
            if i > 0 {
                HStack {
                    Text("\(title) · يبدأ").font(.footnote.bold())
                    Spacer()
                    StepperPill(value: mmss(draft.startTimes[i]), onMinus: { draft.setStart(i, to: draft.startTimes[i] - 5) },
                                onPlus: { draft.setStart(i, to: draft.startTimes[i] + 5) })
                }
            } else {
                Text(title).font(.footnote.bold()).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("أضف").font(.footnote.bold())
                Spacer()
                StepperPill(value: "\(g(step.addedWaterGrams))غ", onMinus: { draft.setAdded(i, grams: (step.addedWaterGrams ?? 0) - 5) },
                            onPlus: { draft.setAdded(i, grams: (step.addedWaterGrams ?? 0) + 5) })
            }
        }
        .padding(10)
        .background(Brand.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: Advanced

/// One row per step: start, what it adds and the scale reading, its temperature; tap for details; drag ≡ to reorder.
struct AdvancedStepsEditor: View {
    @Binding var draft: RecipeDraft
    @State private var expanded: Int?
    @State private var undo: RecipeDraft?
    @State private var dragging: Int?
    @State private var dragOffset: CGFloat = 0
    @State private var consumed: CGFloat = 0
    @State private var typingStart: Int?
    @State private var startText = ""
    private let rowHeight: CGFloat = 66

    var body: some View {
        EditorSection(title: "الخطوات", trailing: "ينتهي \(mmss(draft.totalSeconds))") {
            VStack(spacing: 0) {
                ForEach(Array(draft.steps.enumerated()), id: \.offset) { i, step in
                    row(i, step)
                        .offset(y: dragging == i ? dragOffset : 0)
                        .zIndex(dragging == i ? 1 : 0)
                    if i < draft.steps.count - 1 { Divider() }
                }
            }
            if let before = undo {
                HStack {
                    Text("انتقلت الخطوة، والأوقات انحسبت من جديد").font(.caption).foregroundStyle(Brand.background)
                    Spacer()
                    Button("تراجع") { draft = before; undo = nil }.font(.caption.bold()).foregroundStyle(Brand.gold)
                }
                .padding(10)
                .background(Brand.ink, in: RoundedRectangle(cornerRadius: 12))
                .task(id: before.steps) { try? await Task.sleep(for: .seconds(5)); undo = nil }
            }
            HStack(spacing: 8) {
                Button { draft.addPour(); Haptics.tap() } label: {
                    Text("＋ صبّة").font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
                        .background(Brand.olive, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                }
                Menu {
                    ForEach(ExtraStep.allCases, id: \.self) { kind in
                        Button { draft.addStep(kind); expanded = draft.steps.count - 1 } label: {
                            Text(kind.titleAr); Text(kind.hintAr)
                        }
                    }
                } label: {
                    Text("＋ إضافة خطوة").font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
                        .background(Brand.background, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(Brand.ink)
                }
            }
            .buttonStyle(.plain)
        }
        .alert("يبدأ عند", isPresented: Binding(get: { typingStart != nil }, set: { if !$0 { typingStart = nil } })) {
            TextField("0:50", text: $startText)
            Button("تم") {
                if let i = typingStart {
                    let parts = startText.split(separator: ":").map { Int($0) ?? 0 }
                    let secs = parts.count == 2 ? parts[0] * 60 + parts[1] : (parts.first ?? 0)
                    draft.setStart(i, to: secs)
                }
            }
            Button("إلغاء", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func row(_ i: Int, _ step: RemoteRecipeStep) -> some View {
        let number = draft.steps[...i].filter { $0.kind == .pour }.count
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                    .frame(width: 24, height: 44).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 4).onChanged { value in drag(i, value.translation.height) }
                        .onEnded { _ in dragging = nil; dragOffset = 0; consumed = 0 })
                    .accessibilityLabel("انقل الخطوة")
                dot(step, number)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(step.titleAr).font(.subheadline.bold())
                        Spacer()
                        amount(i, step)
                    }
                    HStack(spacing: 4) {
                        Text("يبدأ").font(.caption2).foregroundStyle(.secondary)
                        Text(mmss(draft.startTimes[i])).font(.caption2.bold().monospacedDigit())
                            .padding(.horizontal, 4)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                            .onTapGesture { if i > 0 { startText = mmss(draft.startTimes[i]); typingStart = i } }
                        Text(subline(i, step)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { expanded = expanded == i ? nil : i } }
            if expanded == i { details(i, step) }
        }
        .padding(.vertical, 8)
        .background(dragging == i ? Color(.secondarySystemGroupedBackground) : .clear)
        .shadow(color: .black.opacity(dragging == i ? 0.15 : 0), radius: 8)
    }

    private func drag(_ i: Int, _ translation: CGFloat) {
        if dragging == nil { dragging = i; consumed = 0; expanded = nil }
        guard let from = dragging else { return }
        dragOffset = translation - consumed
        var to = from
        if dragOffset > rowHeight * 0.6 { to = from + 1 } else if dragOffset < -rowHeight * 0.6 { to = from - 1 }
        if to != from, draft.steps.indices.contains(to) {
            if undo == nil { undo = draft }
            draft.moveStep(from: from, to: to)
            consumed += CGFloat(to - from) * rowHeight
            dragOffset = translation - consumed
            dragging = to
            Haptics.tap()
        }
    }

    private func subline(_ i: Int, _ step: RemoteRecipeStep) -> String {
        if step.isAddition {
            return "بعد التحضير" + (step.addition == "dilute" ? " · \(AdditionTemp.nameAr(step.additionTemp))" : "")
        }
        if step.kind.addsWater {
            return "أضف \(g(step.addedWaterGrams))غ · حتى \(g(draft.cumulativeWater[i]))غ" + (draft.stepTemp(i).map { " · \(g($0))°" } ?? "")
        }
        return "المدة \((step.seconds ?? 0).formatted()) ث"
    }

    @ViewBuilder
    private func amount(_ i: Int, _ step: RemoteRecipeStep) -> some View {
        if step.kind.addsWater {
            StepperPill(value: "\(g(step.addedWaterGrams))غ", size: 26, onMinus: { draft.setAdded(i, grams: (step.addedWaterGrams ?? 0) - 5) },
                        onPlus: { draft.setAdded(i, grams: (step.addedWaterGrams ?? 0) + 5) })
        } else if step.isAddition {
            StepperPill(value: "\(g(step.addedWaterGrams))غ", size: 26, onMinus: { draft.steps[i].addedWaterGrams = max((step.addedWaterGrams ?? 0) - 5, 0) },
                        onPlus: { draft.steps[i].addedWaterGrams = (step.addedWaterGrams ?? 0) + 5 })
        } else {
            StepperPill(value: "\((step.seconds ?? 0).formatted()) ث", size: 26, onMinus: { draft.steps[i].seconds = max((step.seconds ?? 0) - 5, 0) },
                        onPlus: { draft.steps[i].seconds = (step.seconds ?? 0) + 5 })
        }
    }

    private func dot(_ step: RemoteRecipeStep, _ number: Int) -> some View {
        let symbol: String
        if step.kind == .bloom { symbol = "ت" }
        else if step.kind == .pour { symbol = number.formatted() }
        else if step.addition == "ice" { symbol = "🧊" }
        else if step.addition == "dilute" { symbol = "💧" }
        else if step.kind == .wait { symbol = "⏳" }
        else if step.kind == .press { symbol = "⬇" }
        else if step.kind == .serve { symbol = "☕" }
        else { symbol = "⟳" }
        let water = step.kind.addsWater
        return Text(symbol).font(.caption.bold())
            .foregroundStyle(water ? .white : Brand.ink)
            .frame(width: 28, height: 28)
            .background(step.kind == .bloom ? Brand.gold : (water ? Brand.olive : Brand.background), in: Circle())
    }

    @ViewBuilder
    private func details(_ i: Int, _ step: RemoteRecipeStep) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if step.kind.addsWater {
                Text("حرارة هالصبّة").font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    chip(draft.waterTempC.map { "حرارة الوصفة \(g($0))°" } ?? "حرارة الوصفة (غير محددة)", on: step.tempC == nil) { draft.steps[i].tempC = nil }
                    chip(step.tempC.map { "مخصصة: \(g($0))°" } ?? "مخصصة", on: step.tempC != nil) { draft.steps[i].tempC = step.tempC ?? draft.waterTempC ?? 90 }
                    if let t = step.tempC {
                        StepperPill(value: "\(g(t))°", size: 24, onMinus: { draft.steps[i].tempC = max(t - 1, 1) }, onPlus: { draft.steps[i].tempC = min(t + 1, 100) })
                    }
                }
                Text("أسلوب الصب").font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach([PourStyle.center, .circular, .spiral], id: \.self) { p in
                        chip(p.nameAr, on: step.pourStyle == p) { draft.steps[i].pourStyle = step.pourStyle == p ? nil : p }
                    }
                }
                Text("السرعة").font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach([PourSpeed.slow, .medium, .fast], id: \.self) { p in
                        chip(p.nameAr, on: step.pourSpeed == p) { draft.steps[i].pourSpeed = step.pourSpeed == p ? nil : p }
                    }
                }
            }
            if step.addition == "dilute" {
                Text("حرارة ماء التخفيف").font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(AdditionTemp.all, id: \.code) { item in
                        chip(item.nameAr, on: (step.additionTemp ?? "room") == item.code) { draft.steps[i].additionTemp = item.code }
                    }
                }
            }
            Text("ملاحظة").font(.caption2).foregroundStyle(.secondary)
            TextField("مثال: صب من النص للخارج ببطء", text: Binding(get: { draft.steps.indices.contains(i) ? draft.steps[i].note : "" },
                                                                   set: { if draft.steps.indices.contains(i) { draft.steps[i].note = String($0.prefix(300)) } }))
                .textFieldStyle(.roundedBorder)
            Button("حذف الخطوة", role: .destructive) { expanded = nil; draft.removeStep(i) }.font(.footnote)
        }
        .padding(10)
        .background(Brand.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(on ? Brand.olive : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(on ? .white : Brand.ink)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Water check

/// «ماء الخطوات 240غ، والمستهدف 250غ · متبقّي 10غ», with a fix either way. Never blocks a draft.
struct WaterCheckCard: View {
    @Binding var draft: RecipeDraft

    var body: some View {
        if draft.waterMismatch {
            let diff = draft.waterShortfall
            VStack(alignment: .leading, spacing: 6) {
                Text("ماء الخطوات \(g(draft.pouredGrams))غ، والمستهدف \(g(draft.hotWaterGrams))غ").font(.footnote.bold()).foregroundStyle(Brand.gold)
                Text(diff > 0 ? "متبقّي \(g(diff))غ" : "زايد \(g(-diff))غ").font(.caption)
                HStack(spacing: 6) {
                    Button(diff > 0 ? "أضف \(g(diff))غ لآخر صبّة" : "انقص \(g(-diff))غ من آخر صبّة") { draft.giveShortfallToLastPour() }
                        .font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Brand.gold, in: Capsule()).foregroundStyle(.white)
                    Button("اعتمد إجمالي \(g(draft.pouredGrams))غ") { draft.adoptPouredTotal() }
                        .font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule()).foregroundStyle(Brand.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 1, green: 0.965, blue: 0.9), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.gold.opacity(0.45), lineWidth: 1.5))
        }
    }
}

// MARK: Review

/// «مراجعة الوصفة»: what to prepare, the numbers, the three waters, and the steps as they'll show while brewing.
struct RecipeReviewCard: View {
    let draft: RecipeDraft

    var body: some View {
        VStack(spacing: 10) {
            if let line = draft.prepLineAr {
                HStack(spacing: 10) {
                    Image(systemName: "thermometer.medium").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line).font(.headline)
                        Text(draft.customTempsAr.map { "\($0)، والباقي على \(g(draft.waterTempC))°" } ?? "نفس الحرارة لكل الصبّات")
                            .font(.caption).opacity(0.75)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .foregroundStyle(Brand.background)
                .background(Brand.ink, in: RoundedRectangle(cornerRadius: 16))
            }
            HStack(spacing: 6) {
                fact("\(g(draft.doseGrams))غ", "بن")
                fact(RecipeText.ratio(draft.ratio), "النسبة")
                fact(draft.totalSeconds > 0 ? mmss(draft.totalSeconds) : "—", "المدة المتوقعة")
            }
            if !draft.isEspresso {
                VStack(spacing: 0) {
                    line("ماء التحضير", "\(g(draft.pouredGrams > 0 ? draft.pouredGrams : draft.hotWaterGrams))غ")
                    let ice = (draft.temperature == .iced ? draft.iceGrams ?? 0 : 0) + draft.iceAddedGrams
                    line("ثلج", ice > 0 ? "\(g(ice))غ" : nil)
                    let dilute = draft.steps.first { $0.addition == "dilute" }
                    line("ماء للتخفيف", draft.dilutionGrams > 0 ? "\(g(draft.dilutionGrams))غ · \(AdditionTemp.nameAr(dilute?.additionTemp))" : nil)
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            if !draft.steps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(draft.steps.enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 8) {
                            Text(mmss(draft.startTimes[i])).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 40)
                            Text(s.titleAr).font(.footnote.bold())
                            Spacer()
                            Text(right(i, s)).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        if i < draft.steps.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func right(_ i: Int, _ s: RemoteRecipeStep) -> String {
        if s.addition == "ice" { return "\(g(s.addedWaterGrams))غ ثلج" }
        if s.addition == "dilute" { return "\(g(s.addedWaterGrams))غ ماء \(AdditionTemp.nameAr(s.additionTemp))" }
        if s.kind.addsWater {
            let temp = s.tempC.flatMap { $0 != draft.waterTempC ? " · \(g($0))°" : nil } ?? ""
            return "أضف \(g(s.addedWaterGrams))غ · حتى \(g(draft.cumulativeWater[i]))غ" + temp
        }
        return "\((s.seconds ?? 0).formatted()) ث"
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).environment(\.layoutDirection, .leftToRight)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func line(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).font(.footnote)
            Spacer()
            Text(value ?? "بدون").font(value == nil ? .footnote : .footnote.bold()).foregroundStyle(value == nil ? .secondary : .primary)
        }
        .padding(.vertical, 6)
    }
}

/// A dashed «＋ سوّ وصفة جديدة» card (your profile, and «وصفاتي» in «حضّر» when empty).
struct CreateRecipeCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text("＋ سوّ وصفة جديدة").font(.subheadline.bold()).foregroundStyle(Brand.olive)
                Text("تقدر تبدأ من وصفة بطل أو وصفة المحمصة").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18).stroke(Brand.olive.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }
}

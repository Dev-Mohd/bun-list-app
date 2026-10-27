import BunnListCore
import SwiftUI

/// Converts a grind setting between hand grinders using their published microns
/// per click. Approximate: a starting point to adjust by taste.
struct GrindConverterView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("myGrinderID") private var myGrinderID = ""
    @State private var grinderID = ""
    @State private var clicks: Double = 24

    private var grinder: Grinder? { Grinder.find(grinderID) }
    private var microns: Int? { grinder?.microns(forClicks: clicks) }

    var body: some View {
        NavigationStack {
            Form {
                Section("مطحنتك") {
                    Picker("المطحنة", selection: $grinderID) {
                        ForEach(Grinder.convertible) { Text($0.name).tag($0.id) }
                    }
                    Stepper(value: $clicks, in: 1...120, step: 1) {
                        LabeledContent("الإعداد", value: "\(Int(clicks).formatted()) كليك").monospacedDigit()
                    }
                }
                if let microns {
                    Section {
                        LabeledContent("بالميكرون (تقريبي)", value: "≈ \(microns.formatted())")
                        let level = GrindLevel.level(forMicrons: microns)
                        LabeledContent("الدرجة", value: level.nameAr)
                        Text("تناسب عادة: \(level.usedForAr)").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("نفس الطحنة على مطاحن ثانية") {
                        let equivalents = grinder?.equivalents(ofClicks: clicks) ?? []
                        ForEach(Array(equivalents.enumerated()), id: \.offset) { _, item in
                            LabeledContent(item.grinder.name, value: "≈ \(item.clicks.formatted()) كليك").monospacedDigit()
                        }
                    }
                }
                Section {
                    Text("تحويل تقريبي محسوب من الصفر (التصاق الشفرات) وما ينشره كل مصنّع. ابدأ منه واضبط بالتذوق.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .brandScreen()
            .navigationTitle("محوّل الطحن")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
            .onAppear {
                if grinderID.isEmpty {
                    grinderID = Grinder.find(myGrinderID)?.micronsPerClick != nil ? myGrinderID : (Grinder.convertible.first?.id ?? "")
                }
            }
            .onChange(of: grinderID) { _, id in myGrinderID = id }
        }
    }
}

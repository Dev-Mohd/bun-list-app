import BunnListCore
import SwiftUI

struct ProductDetailView: View {
    @EnvironmentObject private var model: AppModel
    let productID: ProductID
    @State private var pendingBag: PendingBag?
    @State private var assignment: SeasonAssignmentRequest?

    var body: some View {
        if let catalog = model.catalog, let product = catalog.product(productID) {
            let lots = catalog.lots(of: productID)
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(product.nameAr).font(.title2.bold()).foregroundStyle(Brand.ink)
                        if let english = product.nameEn { Text(english).font(.subheadline).foregroundStyle(.secondary) }
                        Text(LotText.roaster(product, in: catalog)).font(.headline).foregroundStyle(Brand.brown)
                    }
                    .accessibilityElement(children: .combine)
                    LabeledContent("المنشأ", value: LotText.origin(product.origin))
                    if let process = product.processCode.flatMap(ReferenceCodes.process) {
                        LabeledContent("المعالجة", value: process.nameAr)
                    }
                    if !product.flavorCodes.isEmpty {
                        LabeledContent("النكهات", value: product.flavorCodes.compactMap { ReferenceCodes.flavor($0)?.nameAr }
                            .joined(separator: "، "))
                    }
                    if !product.recommendedBrewMethods.isEmpty {
                        LabeledContent("طرق مقترحة", value: product.recommendedBrewMethods
                            .compactMap { ReferenceCodes.brewMethod($0)?.nameAr }.joined(separator: "، "))
                    }
                    SampleBadge(text: "\(catalog.label) — البيانات توضيحية ولا تقييمات لها")
                }
                Section {
                    ForEach(lots) { lot in
                        LotControls(lot: lot, hasKnownSeasons: lots.contains { !$0.season.isUnknown },
                                    pendingBag: $pendingBag) {
                            assignment = SeasonAssignmentRequest(source: lot.id)
                        }
                    }
                } header: {
                    Text("المحاصيل")
                } footer: {
                    Text("كل موسم محصول مستقل. اختر «الموسم غير معروف» إذا لم يذكر الكيس الموسم؛ لن نخمّنه.")
                }
            }
            .navigationTitle(product.nameAr)
            .navigationBarTitleDisplayMode(.inline)
            .bagDecisionDialog($pendingBag)
            .sheet(item: $assignment) { request in
                SeasonAssignmentSheet(source: request.source, catalog: catalog)
            }
        } else {
            ContentUnavailableView("المحصول غير موجود", systemImage: "questionmark.folder")
        }
    }
}

struct SeasonAssignmentRequest: Identifiable {
    let id = UUID()
    let source: LotID
}

/// Collection controls for one lot. States are independent: «لديّ», «مفضل», «ودي أجرب», «جربته».
struct LotControls: View {
    @EnvironmentObject private var model: AppModel
    let lot: CoffeeLot
    let hasKnownSeasons: Bool
    @Binding var pendingBag: PendingBag?
    var onAssignSeason: () -> Void

    var body: some View {
        let entry = model.entry(for: lot.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(LotText.season(lot)).font(.headline).foregroundStyle(Brand.ink)
                Spacer(minLength: 8)
                if lot.approval != .approved {
                    Text("قيد المراجعة").font(.caption).foregroundStyle(.secondary)
                }
            }
            if lot.season.isUnknown {
                Text("سجل مشترك لمن لا يعرف موسم كيسه، وقد تخص تجاربه مواسم مختلفة.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                if entry?.isOwned == true {
                    model.removeFromOwned(lot.id)
                } else {
                    collect()
                }
            } label: {
                Label(entry?.isOwned == true ? "في مجموعتي" : "أضف إلى مجموعتي",
                      systemImage: entry?.isOwned == true ? "checkmark.circle.fill" : "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("collect-\(lot.id.rawValue)")
            .accessibilityHint(entry?.isOwned == true ? "يزيل المحصول من «لديّ» دون حذف بقية حالاته" : "")

            Toggle("مفضل", isOn: Binding(get: { entry?.isFavorite ?? false }, set: { model.setFavorite($0, lot: lot.id) }))
            Toggle("ودي أجرب", isOn: Binding(get: { entry?.wantsToTry ?? false }, set: { model.setWantsToTry($0, lot: lot.id) }))
            Toggle("جربته", isOn: Binding(get: { entry?.isTried ?? false }, set: { model.setTried($0, lot: lot.id) }))

            if lot.season.isUnknown, hasKnownSeasons, entry?.isActive == true {
                Button("حدّد موسم سجلي", systemImage: "calendar.badge.checkmark", action: onAssignSeason)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("assign-season-\(lot.id.rawValue)")
            }
        }
        .padding(.vertical, 6)
    }

    private func collect() {
        let operationID = ClientID()
        if case let .needsDecision(conflict) = model.collect(lot.id, operationID: operationID) {
            pendingBag = PendingBag(lot: lot.id, conflict: conflict, operationID: operationID)
        }
    }
}

/// «تحديد موسم سجلي»: moves only the current user's records from UNKNOWN to a known season.
struct SeasonAssignmentSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let source: LotID
    let catalog: Catalog
    @State private var target: LotID?
    @State private var operationID = ClientID()

    var body: some View {
        let seasons = catalog.lot(source).map { catalog.lots(of: $0.productID).filter { !$0.season.isUnknown } } ?? []
        NavigationStack {
            Form {
                Section {
                    Text("ينقل سجلك أنت فقط من «الموسم غير معروف» إلى الموسم الذي تختاره. سجلات الآخرين لا تتغير، ولا يُعد النقل إضافة جديدة.")
                        .font(.callout)
                }
                Section("الموسم") {
                    Picker("الموسم", selection: $target) {
                        Text("اختر موسمًا").tag(LotID?.none)
                        ForEach(seasons) { Text(LotText.season($0)).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("حدّد موسم سجلي")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("نقل") {
                        if let target, model.assignSeason(from: source, to: target, operationID: operationID) { dismiss() }
                    }
                    .disabled(target == nil)
                }
            }
        }
    }
}

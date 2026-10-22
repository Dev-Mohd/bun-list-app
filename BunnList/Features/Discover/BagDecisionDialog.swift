import BunnListCore
import SwiftUI

/// A collect or rate waiting for the same-bag answer. The operation ID is reused for the answer.
struct PendingBag: Identifiable {
    enum Kind: Equatable {
        case collect
        case rate(stars: Int)
    }

    let id = UUID()
    let lot: LotID
    let conflict: BagConflict
    let operationID: ClientID
    var kind: Kind = .collect
}

/// «هل هو نفس الكيس؟» — shown when the user holds the UNKNOWN lot and picks a known season, or the reverse.
/// Cancelling creates nothing.
private struct BagDecisionDialog: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Binding var pending: PendingBag?
    let onDone: (CollectOutcome) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                                   titleVisibility: .visible, presenting: pending) { request in
            Button("نعم، نفس الكيس") { answer(request, .sameBag) }
            Button("لا، كيس مختلف") { answer(request, .distinctBag) }
            Button("إلغاء", role: .cancel) { pending = nil }
        } message: { request in
            Text(message(for: request))
        }
    }

    private var title: String {
        switch pending?.conflict.direction {
        case .knownToUnknown: return "هل هو نفس الكيس الذي سجلته بموسم محدد؟"
        default: return "هل هو نفس الكيس الذي سجلته بدون موسم؟"
        }
    }

    private func message(for request: PendingBag) -> String {
        guard let catalog = model.catalog, let lot = catalog.lot(request.lot) else { return "" }
        let existing = request.conflict.existingLots.compactMap(catalog.lot).map(LotText.season).joined(separator: "، ")
        switch request.conflict.direction {
        case .unknownToKnown:
            return "سجّلت هذا المنتج سابقًا («\(existing)»). «نعم» ينقل سجلك إلى «\(LotText.season(lot))» دون إضافة جديدة. «لا» يضيفه كيسًا مستقلًا."
        case .knownToUnknown:
            return "لديك هذا المنتج بموسم «\(existing)». «نعم» يُبقي الموسم المعلوم ولا يضيف شيئًا. «لا» يضيف كيسًا مختلفًا بدون موسم."
        }
    }

    private func answer(_ request: PendingBag, _ decision: BagDecision) {
        pending = nil
        switch request.kind {
        case .collect:
            if case let .done(outcome) = model.collect(request.lot, decision: decision, operationID: request.operationID) {
                onDone(outcome)
            }
        case let .rate(stars):
            _ = model.rate(request.lot, stars: stars, decision: decision, operationID: request.operationID)
        }
    }
}

extension View {
    func bagDecisionDialog(_ pending: Binding<PendingBag?>, onDone: @escaping (CollectOutcome) -> Void = { _ in }) -> some View {
        modifier(BagDecisionDialog(pending: pending, onDone: onDone))
    }
}

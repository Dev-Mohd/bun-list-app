import BunnListCore
import SwiftUI

/// Display text for catalog values. Codes are resolved through Core's bilingual reference data.
enum LotText {
    static func season(_ lot: CoffeeLot) -> String {
        switch lot.season {
        case .unknown: return "الموسم غير معروف"
        case let .known(label, year):
            if let label, !label.isEmpty { return label }
            return year.map { "حصاد \($0.formatted(.number.grouping(.never)))" } ?? "موسم محدد"
        }
    }

    static func origin(_ origin: Origin) -> String {
        let names = origin.countryCodes.compactMap { ReferenceCodes.country($0)?.nameAr }
        switch origin.type {
        case .singleCountry: return names.first ?? "—"
        case .multiCountry: return "خلطة: " + names.joined(separator: "، ")
        case .unknown: return "المنشأ غير محدد"
        }
    }

    static func roaster(_ product: CoffeeProduct, in catalog: Catalog) -> String {
        catalog.roaster(product.roasterID)?.nameAr ?? "—"
    }

    static func title(_ lot: CoffeeLot, in catalog: Catalog) -> String {
        "\(catalog.product(lot.productID)?.nameAr ?? "محصول") · \(season(lot))"
    }
}

struct ProductRow: View {
    let product: CoffeeProduct
    let catalog: Catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(product.nameAr).font(.headline).foregroundStyle(Brand.ink)
            Text(LotText.roaster(product, in: catalog)).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Label(LotText.origin(product.origin), systemImage: "globe.europe.africa")
                if let process = product.processCode.flatMap(ReferenceCodes.process) {
                    Label(process.nameAr, systemImage: "drop")
                }
            }
            .font(.caption).foregroundStyle(Brand.brown)
            Text("لا توجد تقييمات في الدليل التجريبي").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

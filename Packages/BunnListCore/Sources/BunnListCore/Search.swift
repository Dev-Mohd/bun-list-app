import Foundation

/// Search normalization that behaves identically on Linux and iOS (Foundation's diacritic folding
/// does not strip Arabic marks on Linux, so Arabic is normalized explicitly).
public enum TextNormalizer {
    public static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            switch scalar.value {
            case 0x064B...0x065F, 0x0670, 0x0640: continue // tashkeel, superscript alef, tatweel
            case 0x0622, 0x0623, 0x0625, 0x0671: scalars.append("\u{0627}") // آ أ إ ٱ → ا
            case 0x0649: scalars.append("\u{064A}") // ى → ي
            case 0x0629: scalars.append("\u{0647}") // ة → ه
            case 0x0624: scalars.append("\u{0648}") // ؤ → و
            case 0x0626: scalars.append("\u{064A}") // ئ → ي
            case 0x0660...0x0669: scalars.append(Unicode.Scalar(scalar.value - 0x0660 + 0x30)!)
            case 0x06F0...0x06F9: scalars.append(Unicode.Scalar(scalar.value - 0x06F0 + 0x30)!)
            default: scalars.append(scalar)
            }
        }
        let folded = String(scalars).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return folded.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).joined(separator: " ")
    }

    public static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    /// Index words for matching: each word, plus the word without the Arabic definite article «ال».
    static func indexWords(_ text: String) -> Set<String> {
        var words = Set<String>()
        for word in tokens(text) {
            words.insert(word)
            if word.hasPrefix("ال"), word.count > 3 { words.insert(String(word.dropFirst(2))) }
        }
        return words
    }

    /// A query token matches a word exactly, or as a prefix when it has at least two characters.
    static func matches(_ token: String, in words: Set<String>) -> Bool {
        let bare = token.hasPrefix("ال") && token.count > 3 ? String(token.dropFirst(2)) : token
        if words.contains(token) || words.contains(bare) { return true }
        guard bare.count >= 2 else { return false }
        return words.contains { $0.hasPrefix(bare) }
    }
}

public struct CatalogFilters: Equatable, Sendable {
    public var roasterID: RoasterID?
    public var countryCode: String?
    public var processCode: String?
    public var flavorCode: String?
    public var brewMethodCode: String?

    public init(roasterID: RoasterID? = nil, countryCode: String? = nil, processCode: String? = nil,
                flavorCode: String? = nil, brewMethodCode: String? = nil) {
        self.roasterID = roasterID
        self.countryCode = countryCode
        self.processCode = processCode
        self.flavorCode = flavorCode
        self.brewMethodCode = brewMethodCode
    }

    public var isEmpty: Bool { self == CatalogFilters() }
}

public enum CatalogSearch {
    /// Approved products whose text (name, roaster, origin, process, flavors, methods in Arabic or
    /// English, plus aliases) contains every query token, narrowed by filters, sorted by Arabic name.
    public static func products(in catalog: Catalog, query: String, filters: CatalogFilters = CatalogFilters()) -> [CoffeeProduct] {
        let queryTokens = TextNormalizer.tokens(query)
        return catalog.products
            .filter { $0.approval == .approved }
            .filter { matches($0, filters: filters) }
            .filter { product in
                guard !queryTokens.isEmpty else { return true }
                let words = TextNormalizer.indexWords(searchableText(for: product, in: catalog))
                return queryTokens.allSatisfy { TextNormalizer.matches($0, in: words) }
            }
            .sorted { ($0.nameAr, $0.id) < ($1.nameAr, $1.id) }
    }

    static func matches(_ product: CoffeeProduct, filters: CatalogFilters) -> Bool {
        if let roaster = filters.roasterID, product.roasterID != roaster { return false }
        if let country = filters.countryCode, !product.origin.countryCodes.contains(country) { return false }
        if let process = filters.processCode, product.processCode != process { return false }
        if let flavor = filters.flavorCode, !product.flavorCodes.contains(flavor) { return false }
        if let method = filters.brewMethodCode, !product.recommendedBrewMethods.contains(method) { return false }
        return true
    }

    static func searchableText(for product: CoffeeProduct, in catalog: Catalog) -> String {
        var parts = [product.nameAr, product.nameEn ?? ""]
        if let roaster = catalog.roaster(product.roasterID) { parts += [roaster.nameAr, roaster.nameEn ?? ""] }
        let entries = product.origin.countryCodes.compactMap(ReferenceCodes.country)
            + [product.processCode].compactMap { $0 }.compactMap(ReferenceCodes.process)
            + product.flavorCodes.compactMap(ReferenceCodes.flavor)
            + product.recommendedBrewMethods.compactMap(ReferenceCodes.brewMethod)
        for entry in entries { parts += [entry.nameAr, entry.nameEn ?? ""] + entry.aliases }
        return parts.joined(separator: " ")
    }
}

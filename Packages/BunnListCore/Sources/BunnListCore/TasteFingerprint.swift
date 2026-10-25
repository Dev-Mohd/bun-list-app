import Foundation

/// The color family of a free-text flavor note ("خوخ", "Dark chocolate", ...), for
/// the taste-fingerprint card. Matching is by keyword in Arabic or English; the
/// first family that matches wins, so specific fruits come before broad words.
public enum FlavorFamily: String, CaseIterable, Sendable {
    case berry, citrus, stoneFruit, tropical, driedFruit, floral, chocolate, caramel, nutty, spice, tea, honey, other

    /// sRGB components 0...1.
    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .berry: return (0.72, 0.20, 0.27)
        case .citrus: return (0.95, 0.74, 0.20)
        case .stoneFruit: return (0.93, 0.58, 0.36)
        case .tropical: return (0.98, 0.62, 0.15)
        case .driedFruit: return (0.55, 0.27, 0.30)
        case .floral: return (0.76, 0.56, 0.86)
        case .chocolate: return (0.36, 0.22, 0.15)
        case .caramel: return (0.78, 0.52, 0.24)
        case .nutty: return (0.64, 0.47, 0.30)
        case .spice: return (0.66, 0.30, 0.16)
        case .tea: return (0.52, 0.66, 0.33)
        case .honey: return (0.89, 0.69, 0.25)
        case .other: return (0.55, 0.53, 0.40)
        }
    }

    private var keywords: [String] {
        switch self {
        case .berry: return ["توت", "فراول", "كرز", "عنب", "رمان", "berry", "strawberr", "cherr", "grape", "pomegranate", "cassis", "currant"]
        case .citrus: return ["ليمون", "برتقال", "حمضي", "جريب", "يوسفي", "ليم", "lemon", "orange", "citrus", "grapefruit", "lime", "bergamot", "tangerine"]
        case .stoneFruit: return ["خوخ", "مشمش", "دراق", "نكتارين", "برقوق", "peach", "apricot", "nectarine", "plum", "stone fruit"]
        case .tropical: return ["مانجو", "أناناس", "اناناس", "استوائ", "باشن", "بابايا", "جوافة", "ليتشي", "mango", "pineapple", "tropical", "passion", "papaya", "guava", "lychee"]
        case .driedFruit: return ["زبيب", "تمر", "تين", "مجفف", "raisin", "date", "fig", "dried", "prune"]
        case .floral: return ["زهر", "ياسمين", "ورد", "لافند", "بنفسج", "floral", "jasmine", "rose", "lavender", "violet", "hibiscus", "blossom"]
        case .chocolate: return ["شوكولا", "كاكاو", "chocolate", "cocoa", "cacao"]
        case .caramel: return ["كراميل", "سكر", "توفي", "فانيل", "caramel", "sugar", "toffee", "vanilla", "molasses", "butterscotch"]
        case .nutty: return ["مكسرات", "لوز", "بندق", "جوز", "فستق", "nut", "almond", "hazelnut", "walnut", "pistachio", "peanut"]
        case .spice: return ["بهار", "قرفة", "هيل", "قرنفل", "زنجبيل", "فلفل", "spice", "cinnamon", "cardamom", "clove", "ginger", "pepper"]
        case .tea: return ["شاي", "شمام", "بطيخ", "تفاح", "كمثرى", "عشب", "نعناع", "tea", "melon", "apple", "pear", "herb", "mint", "green"]
        case .honey: return ["عسل", "honey"]
        case .other: return []
        }
    }

    public static func of(_ note: String) -> FlavorFamily {
        let text = note.lowercased()
        return allCases.first { family in family.keywords.contains { text.contains($0) } } ?? .other
    }
}

public enum LotCommunityStats {
    /// Whole-number percentages that add up to exactly 100 (largest remainder).
    public static func percentages(_ counts: [Int]) -> [Int] {
        let total = counts.reduce(0, +)
        guard total > 0 else { return counts.map { _ in 0 } }
        let exact = counts.map { Double($0) * 100 / Double(total) }
        var result = exact.map { Int($0.rounded(.down)) }
        let order = exact.indices.sorted { (exact[$0] - Double(result[$0])) > (exact[$1] - Double(result[$1])) }
        for index in order.prefix(100 - result.reduce(0, +)) { result[index] += 1 }
        return result
    }
}

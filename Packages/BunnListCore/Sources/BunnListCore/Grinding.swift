import Foundation

// The recipe standard's vocabulary: grind levels, grinders (with approximate
// microns per click where the maker publishes one, so a grind can be converted
// between grinders), filters and roast levels. Codes match the server.

public enum GrindLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case extraFine, fine, mediumFine, medium, mediumCoarse, coarse, extraCoarse

    public var nameAr: String {
        switch self {
        case .extraFine: return "ناعم جدًا"
        case .fine: return "ناعم"
        case .mediumFine: return "متوسط ناعم"
        case .medium: return "متوسط"
        case .mediumCoarse: return "متوسط خشن"
        case .coarse: return "خشن"
        case .extraCoarse: return "خشن جدًا"
        }
    }

    /// What it usually suits, as a hint under the choice.
    public var usedForAr: String {
        switch self {
        case .extraFine: return "إسبريسو"
        case .fine: return "موكا، إيروبرس سريعة"
        case .mediumFine: return "V60، أوريغامي"
        case .medium: return "كاليتا، كليفر، أداة مسطحة"
        case .mediumCoarse: return "كيمكس، باتشات كبيرة"
        case .coarse: return "فرنش برس، ٤:٦"
        case .extraCoarse: return "كولد برو"
        }
    }

    /// Lower bound of the level in microns (approximate).
    var lowerMicrons: Int {
        switch self {
        case .extraFine: return 0
        case .fine: return 400
        case .mediumFine: return 550
        case .medium: return 700
        case .mediumCoarse: return 850
        case .coarse: return 1000
        case .extraCoarse: return 1200
        }
    }

    public static func level(forMicrons microns: Int) -> GrindLevel {
        allCases.last { microns >= $0.lowerMicrons } ?? .extraFine
    }
}

public struct Grinder: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Approximate burr travel per click, when the maker publishes it. Nil = no conversion.
    public let micronsPerClick: Double?

    public static let all: [Grinder] = [
        Grinder(id: "comandante-c40", name: "Comandante C40", micronsPerClick: 30),
        Grinder(id: "1zpresso-k-ultra", name: "1Zpresso K-Ultra", micronsPerClick: 20),
        Grinder(id: "1zpresso-jmax", name: "1Zpresso J-Max", micronsPerClick: 8.8),
        Grinder(id: "1zpresso-zp6", name: "1Zpresso ZP6", micronsPerClick: 12),
        Grinder(id: "1zpresso-jx-pro", name: "1Zpresso JX-Pro", micronsPerClick: 12.5),
        Grinder(id: "kingrinder-k6", name: "Kingrinder K6", micronsPerClick: 16),
        Grinder(id: "timemore-c3", name: "Timemore C3", micronsPerClick: nil),
        Grinder(id: "fellow-ode-2", name: "Fellow Ode Gen 2", micronsPerClick: nil),
        Grinder(id: "baratza-encore", name: "Baratza Encore", micronsPerClick: nil),
        Grinder(id: "niche-zero", name: "Niche Zero", micronsPerClick: nil),
        Grinder(id: "df64", name: "DF64", micronsPerClick: nil),
        Grinder(id: "ek43", name: "Mahlkönig EK43", micronsPerClick: nil),
    ]

    public static func find(_ id: String?) -> Grinder? { all.first { $0.id == id } }

    /// Microns for a click count on this grinder (counted from burrs touching).
    public func microns(forClicks clicks: Double) -> Int? {
        guard let per = micronsPerClick, clicks > 0 else { return nil }
        return Int((clicks * per).rounded())
    }

    /// The click count on this grinder closest to `microns`.
    public func clicks(forMicrons microns: Int) -> Int? {
        guard let per = micronsPerClick, microns > 0 else { return nil }
        return Int((Double(microns) / per).rounded())
    }
}

public enum FilterType: String, Codable, CaseIterable, Hashable, Sendable {
    case paperWhite, paperBrown, abaca, cloth, metal

    public var nameAr: String {
        switch self {
        case .paperWhite: return "ورق أبيض"
        case .paperBrown: return "ورق بني"
        case .abaca: return "أباكا"
        case .cloth: return "قماش"
        case .metal: return "معدن"
        }
    }
}

public enum RoastLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case light, medium, dark

    public var nameAr: String {
        switch self {
        case .light: return "فاتح"
        case .medium: return "متوسط"
        case .dark: return "غامق"
        }
    }

    /// Typical water temperature for this roast, °C.
    public var suggestedTempC: Double {
        switch self {
        case .light: return 95
        case .medium: return 92
        case .dark: return 88
        }
    }
}

public enum PourStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case center, circular, spiral

    public var nameAr: String {
        switch self {
        case .center: return "مركزي"
        case .circular: return "دائري"
        case .spiral: return "حلزوني"
        }
    }
}

public enum PourSpeed: String, Codable, CaseIterable, Hashable, Sendable {
    case slow, medium, fast

    public var nameAr: String {
        switch self {
        case .slow: return "بطيء"
        case .medium: return "متوسط"
        case .fast: return "سريع"
        }
    }
}

/// Common brewers per method, offered as quick choices.
public enum Brewers {
    public static func suggestions(for methodCode: String) -> [String] {
        switch methodCode {
        case "V60": return ["V60 01", "V60 02", "Origami", "Kalita Wave 185", "Orea", "April"]
        case "CHEMEX": return ["Chemex 6 أكواب", "Chemex 3 أكواب"]
        case "AEROPRESS": return ["AeroPress", "AeroPress Go", "AeroPress XL"]
        case "FRENCH_PRESS": return ["Bodum", "Espro P7"]
        case "ESPRESSO": return ["سلة ١٨غ", "سلة ٢٠غ", "VST 18", "VST 20"]
        case "COLD_BREW": return ["Hario Mizudashi", "Toddy", "مرطبان"]
        case "ARABIC": return ["دلة", "دلة كهربائية"]
        default: return ["Clever", "Hario Switch", "موكا"]
        }
    }
}

public enum WaterType: String, Codable, CaseIterable, Hashable, Sendable {
    case bottled, filtered, mineralRecipe, tap

    public var nameAr: String {
        switch self {
        case .bottled: return "معبأ"
        case .filtered: return "مفلتر"
        case .mineralRecipe: return "وصفة معادن"
        case .tap: return "صنبور"
        }
    }
}

public enum MilkDrink: String, Codable, CaseIterable, Hashable, Sendable {
    case macchiato, cortado, flatWhite, cappuccino, latte

    public var nameAr: String {
        switch self {
        case .macchiato: return "ماكياتو"
        case .cortado: return "كورتادو"
        case .flatWhite: return "فلات وايت"
        case .cappuccino: return "كابتشينو"
        case .latte: return "لاتيه"
        }
    }

    /// A typical amount of steamed milk for a double shot, in grams.
    public var typicalMilkGrams: Double {
        switch self {
        case .macchiato: return 15
        case .cortado: return 40
        case .flatWhite: return 120
        case .cappuccino: return 150
        case .latte: return 220
        }
    }

    /// How the milk is textured, as a barista would say it.
    public var textureAr: String {
        switch self {
        case .macchiato: return "نقطة رغوة فوق الشوت"
        case .cortado: return "حليب مبخّر بقليل من الرغوة"
        case .flatWhite: return "رغوة ناعمة رقيقة (ميكروفوم) بسماكة ~١ سم"
        case .cappuccino: return "رغوة أكثف بسماكة ~١٫٥–٢ سم"
        case .latte: return "رغوة ناعمة رقيقة ~١ سم"
        }
    }
}

public enum MilkType: String, Codable, CaseIterable, Hashable, Sendable {
    case whole, skim, lactoseFree, oat, almond, soy

    public var nameAr: String {
        switch self {
        case .whole: return "كامل الدسم"
        case .skim: return "قليل الدسم"
        case .lactoseFree: return "خالٍ من اللاكتوز"
        case .oat: return "شوفان"
        case .almond: return "لوز"
        case .soy: return "صويا"
        }
    }
}

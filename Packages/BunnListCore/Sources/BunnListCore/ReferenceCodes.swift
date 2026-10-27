/// Bilingual reference data with stable codes. Relations use the code, never the Arabic text.
/// Process and brew-method codes match the enums in the existing server schema (bunnlist/prisma).
/// English names are labels for display, not claims of exact translation equivalence.
public struct ReferenceEntry: Hashable, Sendable {
    public let code: String
    public let nameAr: String
    public let nameEn: String?
    public let aliases: [String]

    init(_ code: String, _ nameAr: String, _ nameEn: String?, aliases: [String] = []) {
        self.code = code
        self.nameAr = nameAr
        self.nameEn = nameEn
        self.aliases = aliases
    }
}

public enum ReferenceCodes {
    public static let countries: [ReferenceEntry] = [
        .init("ET", "إثيوبيا", "Ethiopia", aliases: ["اثيوبيا", "الحبشة"]),
        .init("CO", "كولومبيا", "Colombia"),
        .init("KE", "كينيا", "Kenya"),
        .init("YE", "اليمن", "Yemen"),
        .init("BR", "البرازيل", "Brazil"),
        .init("PA", "بنما", "Panama"),
        .init("RW", "رواندا", "Rwanda"),
        .init("BI", "بوروندي", "Burundi"),
        .init("SV", "السلفادور", "El Salvador"),
        .init("GT", "غواتيمالا", "Guatemala"),
        .init("HN", "هندوراس", "Honduras"),
        .init("CR", "كوستاريكا", "Costa Rica"),
        .init("PE", "بيرو", "Peru"),
        .init("ID", "إندونيسيا", "Indonesia", aliases: ["اندونيسيا"]),
        .init("UG", "أوغندا", "Uganda", aliases: ["اوغندا"]),
        .init("TZ", "تنزانيا", "Tanzania"),
        .init("ZM", "زامبيا", "Zambia"),
        .init("MW", "مالاوي", "Malawi"),
        .init("CD", "الكونغو", "DR Congo", aliases: ["كونغو"]),
        .init("SA", "السعودية", "Saudi Arabia", aliases: ["المملكة العربية السعودية", "سعودي", "سعودية"]),
        .init("IN", "الهند", "India", aliases: ["هند"]),
        .init("NP", "نيبال", "Nepal"),
        .init("CN", "الصين", "China"),
        .init("VN", "فيتنام", "Vietnam"),
        .init("TH", "تايلاند", "Thailand"),
        .init("PG", "بابوا غينيا الجديدة", "Papua New Guinea"),
        .init("MX", "المكسيك", "Mexico"),
        .init("NI", "نيكاراغوا", "Nicaragua", aliases: ["نيكاراجوا"]),
        .init("EC", "الإكوادور", "Ecuador", aliases: ["الاكوادور", "إكوادور"]),
        .init("BO", "بوليفيا", "Bolivia"),
        .init("JM", "جامايكا", "Jamaica"),
        // Not a country: coffees blended from several origins ("مزيج"). XB is in
        // the ISO user-assigned range, so it never clashes with a real code.
        .init("XB", "مزيج", "Blend", aliases: ["خلطة", "بلند", "مزيج", "blend"]),
    ]

    public static let processes: [ReferenceEntry] = [
        .init("NATURAL", "مجففة", "Natural", aliases: ["طبيعية", "ناتشورال"]),
        .init("WASHED", "مغسولة", "Washed"),
        .init("HONEY", "عسلية", "Honey"),
        .init("ANAEROBIC", "لاهوائية", "Anaerobic"),
        .init("WET_HULLED", "مقشورة رطبة", "Wet-hulled"),
        .init("CARBONIC_MACERATION", "نقع كربوني", "Carbonic maceration"),
        .init("EXPERIMENTAL", "تجريبية", "Experimental"),
        .init("OTHER", "أخرى", "Other"),
    ]

    public static let brewMethods: [ReferenceEntry] = [
        .init("ESPRESSO", "إسبريسو", "Espresso"),
        .init("V60", "في ٦٠", "V60", aliases: ["V60", "في60"]),
        .init("CHEMEX", "كيمكس", "Chemex"),
        .init("AEROPRESS", "إيروبرس", "AeroPress", aliases: ["ايروبرس"]),
        .init("FRENCH_PRESS", "فرنش برس", "French press"),
        .init("COLD_BREW", "تقطير بارد", "Cold brew", aliases: ["كولد برو"]),
        .init("ARABIC", "قهوة عربية", "Arabic coffee", aliases: ["قهوة سعودية", "دلة"]),
        .init("OTHER", "أخرى", "Other"),
    ]

    /// Initial Arabic flavor taxonomy (documented in docs/DECISIONS.md). Arabic names are primary.
    public static let flavors: [ReferenceEntry] = [
        .init("FLORAL", "زهري", "Floral", aliases: ["ياسمين", "ورد"]),
        .init("CITRUS", "حمضيات", "Citrus", aliases: ["ليمون", "برتقال"]),
        .init("BERRY", "توت", "Berry", aliases: ["توتي", "فراولة"]),
        .init("STONE_FRUIT", "فاكهة ذات نواة", "Stone fruit", aliases: ["خوخ", "مشمش"]),
        .init("TROPICAL", "فواكه استوائية", "Tropical fruit", aliases: ["مانجو", "أناناس"]),
        .init("DRIED_FRUIT", "فواكه مجففة", "Dried fruit", aliases: ["زبيب", "تمر"]),
        .init("CHOCOLATE", "شوكولاتة", "Chocolate", aliases: ["كاكاو"]),
        .init("CARAMEL", "كراميل", "Caramel", aliases: ["سكر بني"]),
        .init("NUTTY", "مكسرات", "Nutty", aliases: ["لوز", "بندق"]),
        .init("SPICE", "بهارات", "Spice", aliases: ["قرفة", "هيل"]),
        .init("TEA_LIKE", "شاي", "Tea-like"),
        .init("HONEY_SWEET", "حلاوة العسل", "Honey sweetness"),
    ]

    public static func country(_ code: String) -> ReferenceEntry? { countries.first { $0.code == code } }
    public static func process(_ code: String) -> ReferenceEntry? { processes.first { $0.code == code } }
    public static func brewMethod(_ code: String) -> ReferenceEntry? { brewMethods.first { $0.code == code } }
    public static func flavor(_ code: String) -> ReferenceEntry? { flavors.first { $0.code == code } }
}

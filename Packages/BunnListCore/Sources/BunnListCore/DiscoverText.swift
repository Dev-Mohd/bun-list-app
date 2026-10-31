import Foundation

/// The words and choices behind «اكتشف»: which coffee leads, what a card says
/// about ratings, the roaster line, and one plain sentence per process.
public enum DiscoverText {
    /// The newest published coffee leads; the rest follow without it.
    public static func split(newest: [RemoteLot]) -> (featured: RemoteLot?, rest: [RemoteLot]) {
        guard let first = newest.first else { return (nil, []) }
        return (first, newest.filter { $0.id != first.id })
    }

    /// The roaster when every coffee shown is from it, so cards can skip repeating it.
    public static func sharedRoaster(_ lots: [RemoteLot]) -> String? {
        guard let first = lots.first?.roasterNameAr, !first.isEmpty,
              lots.allSatisfy({ $0.roasterNameAr == first }) else { return nil }
        return first
    }

    /// "★ ٤٫٥ · ١٢ تقييم" from real ratings, or an invitation when there are none.
    public static func rating(_ lot: RemoteLot) -> String {
        guard lot.reviewCount > 0 else { return "كن أول من يقيّمها" }
        let value = String(format: "%.1f", lot.averageRating)
        return "★ \(value) · \(RemoteTrendingLot.count(lot.reviewCount, "تقييم واحد", "تقييمين", "تقييمات", "تقييم"))"
    }

    /// Origin flag and process: "🇪🇹 إثيوبيا · لاهوائية".
    public static func originLine(_ lot: RemoteLot) -> String {
        let origin = [ReferenceCodes.flag(lot.originCode), lot.originNameAr].compactMap { $0 }.joined(separator: " ")
        return [origin, lot.processNameAr ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The line under the greeting, by the hour.
    public static func subtitle(hour: Int) -> String {
        switch hour {
        case 5..<11: return "قهوة الصباح؟"
        case 11..<16: return "وقت كوب الظهر"
        case 16..<20: return "شي حلو للعصرية؟"
        default: return "شي خفيف للمسا؟"
        }
    }

    /// One sentence on what a process does to the cup; nil for "other".
    public static func processGuide(_ code: String) -> String? {
        switch code {
        case "NATURAL": return "تجفّ الحبة داخل ثمرتها، فيطلع طعم فواكه وحلاوة أوضح."
        case "WASHED": return "تنشال الثمرة قبل التجفيف، فيطلع كوب صافي وحموضة واضحة."
        case "HONEY": return "تجفّ الحبة مع جزء من لبّ الثمرة، فتجمع بين الحلاوة والصفاء."
        case "ANAEROBIC": return "تتخمّر الثمرة بدون أكسجين، فتطلع فواكه قوية ونكهات جريئة."
        case "WET_HULLED": return "تنقشر الحبة وهي رطبة، فيطلع قوام ثقيل ونكهات ترابية وتوابل."
        case "CARBONIC_MACERATION": return "تتخمّر الثمرة في ثاني أكسيد الكربون، فيطلع كوب فواكهي ومعقّد."
        case "EXPERIMENTAL": return "معالجة خاصة جرّبها المزارع، وغالبًا تطلّع نكهات غير متوقعة."
        case "MIXED": return "مزيج من حبوب بمعالجات مختلفة، فيجمع صفات أكثر من كوب في كوب واحد."
        default: return nil
        }
    }
}

import Foundation

// Home-screen content that needs no server: the greeting, "هل تعلم؟" facts and
// the grind converter.

public enum Greeting {
    /// "صباح الخير" until noon, "مساء الخير" after; with the first name when known.
    public static func text(hour: Int, name: String?) -> String {
        let base = (5..<12).contains(hour) ? "صباح الخير" : "مساء الخير"
        guard let first = name?.split(separator: " ").first, !first.isEmpty else { return base }
        return "\(base)، \(first)"
    }
}

public enum CoffeeFacts {
    public static let all: [String] = [
        "اسم «موكا» جاي من ميناء المخا في اليمن، اللي كان أشهر ميناء لتصدير البن لقرون.",
        "اليمن من أوائل البلدان اللي زرعت البن وتاجرت فيه، من القرن الخامس عشر تقريبًا.",
        "أصل شجرة البن العربي (أرابيكا) من مرتفعات إثيوبيا.",
        "حبة البن هي بذرة ثمرة حمراء اسمها «كرز القهوة»، وأغلب الثمار فيها بذرتين.",
        "أحيانًا تحتوي الثمرة بذرة وحدة مدوّرة، اسمها «بيبيري» (Peaberry).",
        "في المعالجة المجففة تنشف الثمرة كاملة قبل نزع القشر، فتطلع القهوة أحلى وبنكهات فواكه أوضح.",
        "في المعالجة المغسولة يُنزع اللب قبل التجفيف، فتطلع القهوة أنظف وحموضتها أوضح.",
        "كل ما ارتفعت المزرعة، نضجت الثمار أبطأ، وغالبًا صارت نكهتها أعقد.",
        "الروبوستا فيها كافيين تقريبًا ضعف الأرابيكا.",
        "كوب القهوة المقطرة حوالي ٩٨٪ منه ماء، عشان كذا نوعية الماء تفرق كثير.",
        "البن يطلع غاز ثاني أكسيد الكربون بعد التحميص، وهذا سبب الصمام الصغير اللي على الأكياس.",
        "«القهوة العربية رمز الكرم» مسجلة في قائمة اليونسكو للتراث الثقافي غير المادي من ٢٠١٥.",
        "الإسبريسو يُحضّر بضغط حوالي ٩ بار.",
        "الحرارة المناسبة لتحضير القهوة تقريبًا بين ٩٠ و٩٦ درجة.",
        "البن المطحون يفقد روائحه بسرعة، عشان كذا الطحن قبل التحضير مباشرة يفرق.",
    ]

    /// The same fact all day, a different one tomorrow.
    public static func fact(forDay day: Int) -> String {
        all[((day % all.count) + all.count) % all.count]
    }
}

extension Grinder {
    /// Approximate equivalents of `clicks` on this grinder for every other grinder
    /// that publishes microns per click.
    public func equivalents(ofClicks clicks: Double) -> [(grinder: Grinder, clicks: Int)] {
        guard let microns = microns(forClicks: clicks) else { return [] }
        return Grinder.all.compactMap { other in
            guard other.id != id, let c = other.clicks(forMicrons: microns) else { return nil }
            return (other, c)
        }
    }

    public static var convertible: [Grinder] { all.filter { $0.micronsPerClick != nil } }
}

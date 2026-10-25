import Foundation

/// The app's icons: the classic one plus a dark and seasonal ones. `assetName` is
/// the alternate icon set in the asset catalog (nil = the primary icon).
public enum AppIconChoice: String, CaseIterable, Sendable {
    case classic, dark, ramadan, eidFitr, eidAdha, nationalDay, foundingDay

    public var nameAr: String {
        switch self {
        case .classic: return "كلاسيك"
        case .dark: return "داكن"
        case .ramadan: return "رمضان"
        case .eidFitr: return "عيد الفطر"
        case .eidAdha: return "عيد الأضحى"
        case .nationalDay: return "اليوم الوطني"
        case .foundingDay: return "يوم التأسيس"
        }
    }

    public var assetName: String? {
        switch self {
        case .classic: return nil
        case .dark: return "AppIcon-Dark"
        case .ramadan: return "AppIcon-Ramadan"
        case .eidFitr: return "AppIcon-EidFitr"
        case .eidAdha: return "AppIcon-EidAdha"
        case .nationalDay: return "AppIcon-NationalDay"
        case .foundingDay: return "AppIcon-FoundingDay"
        }
    }

    /// The small picture shown in the picker.
    public var previewName: String {
        "IconPreview-" + (assetName?.replacingOccurrences(of: "AppIcon-", with: "") ?? "Classic")
    }

    /// The occasion on `date` in Saudi Arabia, if any: Ramadan and the two Eids
    /// by the Umm al-Qura calendar, National Day 20–24 Sep, Founding Day 20–23 Feb.
    /// The national days win when they fall inside Ramadan.
    public static func season(on date: Date, timeZone: TimeZone = TimeZone(identifier: "Asia/Riyadh")!) -> AppIconChoice? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let g = gregorian.dateComponents([.month, .day], from: date)
        switch (g.month, g.day) {
        case (9?, let day?) where (20...24).contains(day): return .nationalDay
        case (2?, let day?) where (20...23).contains(day): return .foundingDay
        default: break
        }
        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.timeZone = timeZone
        let h = hijri.dateComponents([.month, .day], from: date)
        switch (h.month, h.day) {
        case (9?, _): return .ramadan
        case (10?, let day?) where day <= 3: return .eidFitr
        case (12?, let day?) where (9...13).contains(day): return .eidAdha
        default: return nil
        }
    }
}

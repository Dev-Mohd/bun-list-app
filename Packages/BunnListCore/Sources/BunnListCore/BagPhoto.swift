import Foundation

// Product-photo rules shared by the app's on-device checks. Real photos only: the
// app enhances light and sharpness but never generates. These rules decide when
// to ask for a retake, and how a coffee without any photo is drawn instead.

public enum BagPhotoIssue: String, Equatable, Hashable, Sendable {
    case tooSmall
    case tooFar
    case cutOff
    case blurry

    public var messageAr: String {
        switch self {
        case .tooSmall: return "الصورة صغيرة، صوّر من قريب بدقة أعلى."
        case .tooFar: return "الكيس بعيد، قرّب الجوال لين يعبّي الكيس أغلب الصورة."
        case .cutOff: return "جزء من الكيس طالع برا الصورة، خلّ الكيس كامل داخل الإطار."
        case .blurry: return "الصورة مغبّشة، ثبّت الجوال وصوّر بإضاءة أفضل."
        }
    }
}

public enum BagPhotoCheck {
    /// The bag's bounding box as fractions of the photo (0…1, any origin).
    public struct Box: Equatable, Sendable {
        public let minX: Double, minY: Double, maxX: Double, maxY: Double
        public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
        }
        public var area: Double { max(0, maxX - minX) * max(0, maxY - minY) }
    }

    public static let minSubjectPixels = 400.0
    public static let minAreaFraction = 0.08
    public static let edgeMargin = 0.012
    /// Mean edge strength (0…1) below which the bag reads as soft.
    public static let minSharpness = 0.018

    /// - Parameters:
    ///   - box: where the bag is in the photo.
    ///   - photoSize: the photo in pixels.
    ///   - sharpness: mean edge strength of the cut-out, nil when unmeasured.
    public static func issues(box: Box, photoWidth: Double, photoHeight: Double, sharpness: Double?) -> [BagPhotoIssue] {
        var issues: [BagPhotoIssue] = []
        let subjectShortSide = min((box.maxX - box.minX) * photoWidth, (box.maxY - box.minY) * photoHeight)
        if subjectShortSide < minSubjectPixels { issues.append(.tooSmall) }
        if box.area < minAreaFraction { issues.append(.tooFar) }
        if box.minX <= edgeMargin || box.minY <= edgeMargin || box.maxX >= 1 - edgeMargin || box.maxY >= 1 - edgeMargin {
            issues.append(.cutOff)
        }
        if let sharpness, sharpness < minSharpness { issues.append(.blurry) }
        return issues
    }
}

/// The tone of a drawn card for a coffee without a photo, from its origin region.
public enum CoffeeArtTone: String, Equatable, Sendable, CaseIterable {
    case africa, latinAmerica, arabia, asia, other

    public static func forOrigin(_ isoCode: String?) -> CoffeeArtTone {
        switch isoCode?.uppercased() {
        case "ET", "KE", "RW", "BI", "UG", "TZ", "CD", "MW", "ZM": return .africa
        case "CO", "BR", "PE", "GT", "HN", "CR", "SV", "NI", "PA", "MX", "BO", "EC": return .latinAmerica
        case "YE", "SA": return .arabia
        case "ID", "IN", "VN", "PG", "CN", "TH", "LA", "MM", "TL": return .asia
        default: return .other
        }
    }
}

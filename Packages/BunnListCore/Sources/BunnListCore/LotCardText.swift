import Foundation

extension FlavorFamily {
    /// The family that colors a coffee's card: its first note with a family, or
    /// `.other` when no note has one.
    public static func dominant(_ notes: [String]) -> FlavorFamily {
        notes.lazy.map(of).first { $0 != .other } ?? .other
    }
}

extension ReferenceCodes {
    /// The flag emoji for an ISO country code; nil for blends and anything not
    /// two letters.
    public static func flag(_ code: String?) -> String? {
        guard let code = code?.uppercased(), code.count == 2, code != "XB",
              code.unicodeScalars.allSatisfy({ ("A"..."Z").contains(Character($0)) }) else { return nil }
        return code.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }.map(String.init).joined()
    }
}

extension RemoteLot {
    /// One glanceable line for a card: "🇪🇹 لاهوائية · خوخ، أناناس".
    public var cardLine: String {
        let notes = flavorNotes.prefix(2).joined(separator: "، ")
        let head = [ReferenceCodes.flag(originCode), processNameAr].compactMap { $0 }.joined(separator: " ")
        return [head, notes].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

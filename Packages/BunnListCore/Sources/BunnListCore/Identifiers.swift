import Foundation

/// A UUID created once on the device for anything the user creates (collection entries, drafts,
/// operations). It is never regenerated on retry, season transfer or guest import.
public struct ClientID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }

    public init?(string: String) {
        guard let value = UUID(uuidString: string) else { return nil }
        rawValue = value
    }

    public var description: String { rawValue.uuidString.lowercased() }

    public static func < (lhs: ClientID, rhs: ClientID) -> Bool { lhs.description < rhs.description }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let value = UUID(uuidString: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid UUID \(text)"))
        }
        rawValue = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Opaque catalog identifier. Server IDs are opaque strings and their format is never parsed;
/// the only reserved shape is the `sample:` namespace used by the bundled demo catalog.
public struct OpaqueID<Tag>: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public static var sampleNamespace: String { "sample:" }

    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }

    /// Demo-catalog IDs must never be uploaded to a real account (C04 guest import filters them out).
    public var isSample: Bool { rawValue.hasPrefix(Self.sampleNamespace) }

    public var description: String { rawValue }

    public static func < (lhs: OpaqueID, rhs: OpaqueID) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum RoasterTag {}
public enum ProductTag {}
public enum LotTag {}

public typealias RoasterID = OpaqueID<RoasterTag>
public typealias ProductID = OpaqueID<ProductTag>
/// «محصول» in the UI is a lot (CoffeeLot), not a product.
public typealias LotID = OpaqueID<LotTag>

/// Who owns local records. C01 only creates guests; accounts arrive with C03/C04.
public enum OwnerID: Hashable, Codable, Sendable {
    case guest(UUID)
    case account(String)

    public static func newGuest() -> OwnerID { .guest(UUID()) }

    public var isGuest: Bool {
        if case .guest = self { return true }
        return false
    }
}

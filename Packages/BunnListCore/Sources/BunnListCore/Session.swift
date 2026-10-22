import Foundation

/// Deterministic, dependency-free hash for modelling token storage on Linux and Apple alike. The real
/// server stores refresh tokens under a proper KDF/secure hash; this stands in for the rotation and
/// reuse-detection contract, never for production hashing.
enum TokenHasher {
    static func hash(_ value: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 { h ^= UInt64(byte); h = h &* 0x100000001b3 }
        return "fnv1a:" + String(h, radix: 16)
    }
}

public struct RefreshRotation: Equatable, Sendable {
    public let newToken: String
}

/// A refresh-token family for one session. Tokens are kept hashed. Rotating the current token issues a
/// new one and consumes the old; presenting an already-consumed token is reuse and revokes the family.
public struct RefreshTokenFamily: Codable, Equatable, Sendable {
    public static let ttlSeconds: TimeInterval = 60 * 60 * 24 * 30

    public let accountID: String
    public private(set) var isRevoked = false
    private var currentHash: String
    private var issuedAt: Date
    private var consumedHashes: Set<String> = []
    private var makeToken: () -> String

    public init(accountID: String, initialToken: String, now: Date, tokenGenerator: @escaping () -> String = { UUID().uuidString }) {
        self.accountID = accountID
        currentHash = TokenHasher.hash(initialToken)
        issuedAt = now
        makeToken = tokenGenerator
    }

    public var debugStoredRepresentation: String { ([currentHash] + consumedHashes.sorted()).joined(separator: ",") }

    public mutating func rotate(presenting token: String, now: Date) throws -> RefreshRotation {
        if isRevoked { throw AuthError.sessionRevoked }
        let presented = TokenHasher.hash(token)
        if presented == currentHash {
            if now.timeIntervalSince(issuedAt) > Self.ttlSeconds { throw AuthError.refreshTokenExpired }
            consumedHashes.insert(currentHash)
            let newToken = makeToken()
            currentHash = TokenHasher.hash(newToken)
            issuedAt = now
            return RefreshRotation(newToken: newToken)
        }
        if consumedHashes.contains(presented) {
            isRevoked = true
            throw AuthError.refreshTokenReuseDetected
        }
        throw AuthError.refreshTokenReuseDetected
    }

    private enum CodingKeys: String, CodingKey { case accountID, isRevoked, currentHash, issuedAt, consumedHashes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try c.decode(String.self, forKey: .accountID)
        isRevoked = try c.decode(Bool.self, forKey: .isRevoked)
        currentHash = try c.decode(String.self, forKey: .currentHash)
        issuedAt = try c.decode(Date.self, forKey: .issuedAt)
        consumedHashes = try c.decode(Set<String>.self, forKey: .consumedHashes)
        makeToken = { UUID().uuidString }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accountID, forKey: .accountID)
        try c.encode(isRevoked, forKey: .isRevoked)
        try c.encode(currentHash, forKey: .currentHash)
        try c.encode(issuedAt, forKey: .issuedAt)
        try c.encode(consumedHashes, forKey: .consumedHashes)
    }

    public static func == (lhs: RefreshTokenFamily, rhs: RefreshTokenFamily) -> Bool {
        lhs.accountID == rhs.accountID && lhs.isRevoked == rhs.isRevoked && lhs.currentHash == rhs.currentHash
            && lhs.issuedAt == rhs.issuedAt && lhs.consumedHashes == rhs.consumedHashes
    }
}

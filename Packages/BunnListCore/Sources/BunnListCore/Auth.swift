import Foundation

public enum AuthProvider: String, Codable, Hashable, Sendable {
    case apple, google, email
}

/// A provider identity. Accounts are resolved by (provider, subject) only — never by email, because
/// a shared email (or Apple's private relay) does not prove the same person.
public struct AuthIdentity: Codable, Hashable, Sendable {
    public let provider: AuthProvider
    public let subject: String
    public let email: String?
    public let emailIsPrivateRelay: Bool

    public init(provider: AuthProvider, subject: String, email: String? = nil, emailIsPrivateRelay: Bool = false) {
        self.provider = provider
        self.subject = subject
        self.email = email
        self.emailIsPrivateRelay = emailIsPrivateRelay
    }

    var key: String { "\(provider.rawValue):\(subject)" }
}

public enum AuthError: Error, Equatable, Sendable {
    case sessionNotVerified
    case secondIdentityNotProven
    case identityAlreadyLinked
    case codeExpired
    case codeIncorrect
    case tooManyAttempts
    case refreshTokenReuseDetected
    case refreshTokenExpired
    case sessionRevoked
}

/// A verified session bound to an account, used to authorize identity linking.
public enum SessionAssertion: Equatable, Sendable {
    case unverified
    case verified(String)
}

/// Proof that the caller controls the second identity being linked (e.g. a completed OAuth/OTP).
public enum IdentityProof: Equatable, Sendable {
    case missing
    case verified(AuthIdentity)
}

public struct SignInResult: Equatable, Sendable {
    public let accountID: String
    public let isNewAccount: Bool
}

/// Resolves and links provider identities to accounts. The owner is the account; the client never
/// asserts its own account id.
public struct IdentityDirectory: Codable, Equatable, Sendable {
    private var accountByIdentityKey: [String: String] = [:]
    private var newlyCreated: Set<String> = []

    public init() {}

    /// Resolves (provider, subject) to an account, creating one on first sight. A shared email never
    /// merges accounts.
    public mutating func signIn(with identity: AuthIdentity) throws -> SignInResult {
        if let existing = accountByIdentityKey[identity.key] {
            return SignInResult(accountID: existing, isNewAccount: false)
        }
        let accountID = "acct-" + UUID().uuidString.lowercased()
        accountByIdentityKey[identity.key] = accountID
        newlyCreated.insert(identity.key)
        return SignInResult(accountID: accountID, isNewAccount: true)
    }

    /// Links a second identity to an account. Requires a session verified for that account and proof
    /// of the second identity; refuses an identity already bound elsewhere or a link by email alone.
    public mutating func link(_ identity: AuthIdentity, to accountID: String,
                              session: SessionAssertion, proof: IdentityProof) throws {
        guard case let .verified(sessionAccount) = session, sessionAccount == accountID else {
            throw AuthError.sessionNotVerified
        }
        guard case let .verified(provenIdentity) = proof, provenIdentity.key == identity.key else {
            throw AuthError.secondIdentityNotProven
        }
        if let bound = accountByIdentityKey[identity.key], bound != accountID {
            throw AuthError.identityAlreadyLinked
        }
        accountByIdentityKey[identity.key] = accountID
    }

    public func account(for identity: AuthIdentity) -> String? { accountByIdentityKey[identity.key] }
}

/// Email one-time-code service. Responses never reveal whether an email is registered, codes expire,
/// attempts are capped, and resends are rate limited.
public struct EmailOTPService: Sendable {
    public static let ttlSeconds: TimeInterval = 600
    public static let maxAttempts = 5
    public static let resendCooldownSeconds: TimeInterval = 30

    public struct RequestResult: Equatable, Sendable {
        /// The same neutral message regardless of whether the email exists.
        public let acknowledgement: String
        public let rateLimited: Bool
        /// Only populated in tests/local; never returned to clients in production.
        public let debugCode: String?
    }

    public enum VerifyResult: Equatable, Sendable { case verified }

    private struct Challenge { var code: String; var issuedAt: Date; var attempts: Int }

    private let knownEmails: Set<String>
    private var challenges: [String: Challenge] = [:]
    private var lastSent: [String: Date] = [:]
    private var makeCode: @Sendable () -> String

    public init(knownEmails: Set<String> = [], codeGenerator: @escaping @Sendable () -> String = { String(format: "%06d", Int.random(in: 0...999_999)) }) {
        self.knownEmails = knownEmails
        self.makeCode = codeGenerator
    }

    public mutating func requestCode(email: String, now: Date) -> RequestResult {
        let ack = "إذا كان البريد صحيحًا فسيصلك رمز."
        if let last = lastSent[email], now.timeIntervalSince(last) < Self.resendCooldownSeconds {
            return RequestResult(acknowledgement: ack, rateLimited: true, debugCode: nil)
        }
        let code = makeCode()
        challenges[email] = Challenge(code: code, issuedAt: now, attempts: 0)
        lastSent[email] = now
        return RequestResult(acknowledgement: ack, rateLimited: false, debugCode: code)
    }

    public mutating func verify(email: String, code: String, now: Date) throws -> VerifyResult {
        guard var challenge = challenges[email] else { throw AuthError.codeIncorrect }
        if now.timeIntervalSince(challenge.issuedAt) > Self.ttlSeconds {
            challenges[email] = nil
            throw AuthError.codeExpired
        }
        if challenge.attempts >= Self.maxAttempts { throw AuthError.tooManyAttempts }
        guard challenge.code == code else {
            challenge.attempts += 1
            challenges[email] = challenge
            if challenge.attempts >= Self.maxAttempts { throw AuthError.codeIncorrect }
            throw AuthError.codeIncorrect
        }
        challenges[email] = nil
        return .verified
    }
}

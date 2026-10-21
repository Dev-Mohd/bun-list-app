import Foundation

public enum ContentKind: String, Codable, Sendable {
    case experience, recipe, comment
}

/// Owner-controlled lifecycle. `unpublished` is the same entity and clientID withdrawn from public view;
/// `deleted` is final and its clientID can never be created again.
public enum ContentLifecycle: String, Codable, Sendable {
    case draft, published, unpublished, deleted
}

/// Independent of the lifecycle: an admin hide blocks visibility and republishing until lifted.
public enum ModerationStatus: String, Codable, Sendable {
    case visible, hidden
}

public enum LifecycleError: Error, Equatable, Sendable {
    case invalidTransition(from: ContentLifecycle, to: ContentLifecycle)
    case deletedIsFinal
    case hiddenByModeration
    case staleRevision(expected: Int, actual: Int)
}

public struct ContentState: Codable, Equatable, Sendable {
    public let kind: ContentKind
    public private(set) var lifecycle: ContentLifecycle
    public private(set) var moderation: ModerationStatus
    public private(set) var revision: Int
    private var lastRequestKey: ClientID?

    public init(kind: ContentKind) {
        self.kind = kind
        lifecycle = .draft
        moderation = .visible
        revision = 0
    }

    public var isPubliclyVisible: Bool { lifecycle == .published && moderation == .visible }

    /// Applies an owner transition. Repeating the same request key is a no-op; a request carrying an
    /// older revision is stale (HTTP 409 on the server).
    @discardableResult
    public mutating func transition(to target: ContentLifecycle, expectedRevision: Int, requestKey: ClientID) throws -> Bool {
        if requestKey == lastRequestKey, lifecycle == target { return false }
        if lifecycle == .deleted { throw LifecycleError.deletedIsFinal }
        guard expectedRevision == revision else {
            throw LifecycleError.staleRevision(expected: expectedRevision, actual: revision)
        }
        guard Self.allowed(kind: kind, from: lifecycle, to: target) else {
            throw LifecycleError.invalidTransition(from: lifecycle, to: target)
        }
        if target == .published, moderation == .hidden { throw LifecycleError.hiddenByModeration }
        lifecycle = target
        revision += 1
        lastRequestKey = requestKey
        return true
    }

    /// Admin action; owner edits or transitions never lift it.
    public mutating func setModeration(_ status: ModerationStatus) {
        guard status != moderation else { return }
        moderation = status
        revision += 1
    }

    static func allowed(kind: ContentKind, from: ContentLifecycle, to: ContentLifecycle) -> Bool {
        switch (kind, from, to) {
        case (_, .deleted, _): return false
        case (_, _, .deleted): return true
        case (_, .draft, .published): return true
        case (.experience, .published, .unpublished), (.recipe, .published, .unpublished): return true
        case (.experience, .unpublished, .published), (.recipe, .unpublished, .published): return true
        default: return false
        }
    }
}

/// Net reward for one entitlement across unpublish/republish cycles. It never exceeds the original
/// grant: +10, −10, +10, −10, +10 nets 10. The server ledger (C06) applies the same contract.
public struct EntitlementLedger: Codable, Equatable, Sendable {
    public let amount: Int
    public private(set) var entries: [Int] = []

    public init(amount: Int) { self.amount = amount }

    public var net: Int { entries.reduce(0, +) }

    public mutating func apply(_ lifecycle: ContentLifecycle) {
        switch lifecycle {
        case .published where net == 0: entries.append(amount)
        case .unpublished where net == amount, .deleted where net == amount: entries.append(-amount)
        default: break
        }
    }
}

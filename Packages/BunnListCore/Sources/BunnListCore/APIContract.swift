import Foundation

/// The client-facing error contract the app and server agree on (spec: 401/403/409/422/429).
public enum APIError: Error, Equatable, Sendable {
    case unauthorized   // 401 — no/!invalid credentials
    case forbidden      // 403 — authenticated but not allowed
    case conflict       // 409 — idempotency/version/tombstone conflict
    case unprocessable  // 422 — validation failed
    case rateLimited    // 429 — too many requests

    public var status: Int {
        switch self {
        case .unauthorized: return 401
        case .forbidden: return 403
        case .conflict: return 409
        case .unprocessable: return 422
        case .rateLimited: return 429
        }
    }
}

/// Server-side idempotency key: the owner, the operation, and the device-created clientID.
public struct IdempotencyKey: Hashable, Codable, Sendable {
    public let ownerID: String
    public let operation: String
    public let clientID: ClientID

    public init(ownerID: String, operation: String, clientID: ClientID) {
        self.ownerID = ownerID
        self.operation = operation
        self.clientID = clientID
    }
}

/// Outcome of beginning an idempotent operation.
public enum IdempotencyOutcome: Equatable, Sendable {
    case proceed                                    // first time — do the work, then complete()
    case inProgress                                 // reserved but not completed — caller should wait/retry
    case replay(resourceID: String, response: String?)  // already done — return the same resource (body may be gone)
}

/// Models the server's idempotency + creation-identity permanence. The response body may be evicted
/// after a TTL, but the creation identity (resourceID) is permanent, a different payload under the
/// same key conflicts, and a deleted resource is never recreated by an old retry.
public struct IdempotencyStore: Sendable {
    public static let responseCacheTTLSeconds: TimeInterval = 60 * 60 * 24

    private enum State: Equatable {
        case reserved
        case completed(resourceID: String, response: String, at: Date)
        case deleted(resourceID: String)
    }
    private struct Record: Equatable { var payloadHash: String; var state: State }
    private var records: [IdempotencyKey: Record] = [:]

    public init() {}

    public mutating func begin(_ key: IdempotencyKey, payloadHash: String, now: Date) throws -> IdempotencyOutcome {
        guard let record = records[key] else {
            records[key] = Record(payloadHash: payloadHash, state: .reserved)
            return .proceed
        }
        guard record.payloadHash == payloadHash else { throw APIError.conflict }
        switch record.state {
        case .reserved:
            return .inProgress
        case .deleted:
            throw APIError.conflict
        case let .completed(resourceID, response, at):
            if now.timeIntervalSince(at) > Self.responseCacheTTLSeconds {
                return .replay(resourceID: resourceID, response: nil)
            }
            return .replay(resourceID: resourceID, response: response)
        }
    }

    public mutating func complete(_ key: IdempotencyKey, resourceID: String, response: String, now: Date) {
        records[key] = Record(payloadHash: records[key]?.payloadHash ?? "", state: .completed(resourceID: resourceID, response: response, at: now))
    }

    public mutating func markDeleted(_ key: IdempotencyKey) {
        guard let record = records[key] else { return }
        if case let .completed(resourceID, _, _) = record.state {
            records[key] = Record(payloadHash: record.payloadHash, state: .deleted(resourceID: resourceID))
        }
    }
}

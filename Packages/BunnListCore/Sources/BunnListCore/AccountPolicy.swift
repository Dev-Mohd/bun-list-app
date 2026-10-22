import Foundation

/// Minimum-age gate. The number is configuration (16+ for this release, an open decision confirmed
/// with a reviewer before launch), not hard-coded policy.
public struct AgeGate: Sendable {
    public let minimumAge: Int
    private let calendar: Calendar

    public init(minimumAge: Int, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.minimumAge = minimumAge
        self.calendar = calendar
    }

    public func meets(birthDate: Date, now: Date) -> Bool {
        let years = calendar.dateComponents([.year], from: birthDate, to: now).year ?? 0
        return years >= minimumAge
    }
}

/// Tracks acceptance of the current terms/community-policy version; publishing requires it.
public struct TermsAcceptanceState: Codable, Equatable, Sendable {
    public let currentVersion: String
    public private(set) var acceptedVersion: String?
    public private(set) var acceptedAt: Date?

    public init(currentVersion: String) { self.currentVersion = currentVersion }

    public var mayPublish: Bool { acceptedVersion == currentVersion }

    public mutating func accept(version: String, at: Date) {
        acceptedVersion = version
        acceptedAt = at
    }
}

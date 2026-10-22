import Foundation

/// Everything the device keeps for C01. The app persists it with SwiftData; tests use the in-memory store.
public struct LocalSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var session: LocalSession
    public var book: CollectionBook
    public var experiences: ExperienceBook
    public var recipes: RecipeBook

    public init(session: LocalSession = LocalSession(), book: CollectionBook = CollectionBook(),
                experiences: ExperienceBook = ExperienceBook(), recipes: RecipeBook = RecipeBook()) {
        schemaVersion = Self.currentSchemaVersion
        self.session = session
        self.book = book
        self.experiences = experiences
        self.recipes = recipes
    }

    // Tolerate snapshots written before experiences/recipes existed (same schema version, additive).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        session = try container.decode(LocalSession.self, forKey: .session)
        book = try container.decode(CollectionBook.self, forKey: .book)
        experiences = try container.decodeIfPresent(ExperienceBook.self, forKey: .experiences) ?? ExperienceBook()
        recipes = try container.decodeIfPresent(RecipeBook.self, forKey: .recipes) ?? RecipeBook()
    }
}

public enum LocalStoreError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case writeFailed
}

/// Storage seam: Core decides what changes, the store only loads and saves whole snapshots atomically.
public protocol LocalSnapshotStore {
    func load() throws -> LocalSnapshot?
    func save(_ snapshot: LocalSnapshot) throws
}

public final class InMemorySnapshotStore: LocalSnapshotStore {
    public private(set) var saved: LocalSnapshot?
    public var failNextSave = false

    public init(_ initial: LocalSnapshot? = nil) { saved = initial }

    public func load() throws -> LocalSnapshot? {
        if let saved, saved.schemaVersion > LocalSnapshot.currentSchemaVersion {
            throw LocalStoreError.unsupportedSchemaVersion(saved.schemaVersion)
        }
        return saved
    }

    public func save(_ snapshot: LocalSnapshot) throws {
        if failNextSave {
            failNextSave = false
            throw LocalStoreError.writeFailed
        }
        saved = snapshot
    }
}

/// Applies a change to a copy, saves it, and only then exposes it. A failed save leaves the
/// visible state and the stored state unchanged, and the same call can simply be retried.
public final class LocalSnapshotController {
    public private(set) var snapshot: LocalSnapshot
    private let store: LocalSnapshotStore

    public init(store: LocalSnapshotStore) throws {
        self.store = store
        if let loaded = try store.load() {
            guard loaded.schemaVersion <= LocalSnapshot.currentSchemaVersion else {
                throw LocalStoreError.unsupportedSchemaVersion(loaded.schemaVersion)
            }
            snapshot = loaded
        } else {
            snapshot = LocalSnapshot()
            try store.save(snapshot)
        }
    }

    @discardableResult
    public func mutate<T>(_ change: (inout LocalSnapshot) throws -> T) throws -> T {
        var copy = snapshot
        let result = try change(&copy)
        try store.save(copy)
        snapshot = copy
        return result
    }
}

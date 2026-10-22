import BunnListCore
import Foundation
import SwiftData

/// One row per collection entry, with indexed columns for future queries and the full entry as JSON.
@Model
final class CollectionEntryRecord {
    @Attribute(.unique) var clientID: UUID
    var ownerKey: String
    var lotID: String
    var isActive: Bool
    var updatedAt: Date
    var payload: Data

    init(clientID: UUID, ownerKey: String, lotID: String, isActive: Bool, updatedAt: Date, payload: Data) {
        self.clientID = clientID
        self.ownerKey = ownerKey
        self.lotID = lotID
        self.isActive = isActive
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

/// The rest of the local snapshot (session, history, operations) as one versioned record.
@Model
final class LocalStateRecord {
    @Attribute(.unique) var key: String
    var schemaVersion: Int
    var payload: Data

    init(key: String, schemaVersion: Int, payload: Data) {
        self.key = key
        self.schemaVersion = schemaVersion
        self.payload = payload
    }
}

/// SwiftData behind Core's `LocalSnapshotStore`. Core decides every change; this type only loads and
/// saves whole snapshots, and a failed save is rolled back so nothing half-written stays in the context.
final class SwiftDataSnapshotStore: LocalSnapshotStore {
    private static let stateKey = "main"
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([CollectionEntryRecord.self, LocalStateRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// On-disk container at an explicit location (used by tests to simulate an app relaunch).
    static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema([CollectionEntryRecord.self, LocalStateRecord.self])
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func load() throws -> LocalSnapshot? {
        guard let state = try context.fetch(FetchDescriptor<LocalStateRecord>()).first(where: { $0.key == Self.stateKey }) else {
            return nil
        }
        guard state.schemaVersion <= LocalSnapshot.currentSchemaVersion else {
            throw LocalStoreError.unsupportedSchemaVersion(state.schemaVersion)
        }
        var snapshot = try decoder.decode(LocalSnapshot.self, from: state.payload)
        let entries = try context.fetch(FetchDescriptor<CollectionEntryRecord>()).map {
            try decoder.decode(CollectionEntry.self, from: $0.payload)
        }
        snapshot.book.restoreEntries(entries)
        return snapshot
    }

    func save(_ snapshot: LocalSnapshot) throws {
        do {
            let (header, entries) = snapshot.book.splitForStorage()
            var stateOnly = snapshot
            stateOnly.book = header
            let statePayload = try encoder.encode(stateOnly)
            if let state = try context.fetch(FetchDescriptor<LocalStateRecord>()).first(where: { $0.key == Self.stateKey }) {
                state.schemaVersion = snapshot.schemaVersion
                state.payload = statePayload
            } else {
                context.insert(LocalStateRecord(key: Self.stateKey, schemaVersion: snapshot.schemaVersion, payload: statePayload))
            }

            var existing: [UUID: CollectionEntryRecord] = [:]
            for record in try context.fetch(FetchDescriptor<CollectionEntryRecord>()) { existing[record.clientID] = record }
            for entry in entries {
                let payload = try encoder.encode(entry)
                let ownerKey = String(decoding: try encoder.encode(entry.ownerID), as: UTF8.self)
                if let record = existing.removeValue(forKey: entry.clientID.rawValue) {
                    record.ownerKey = ownerKey
                    record.lotID = entry.lotID.rawValue
                    record.isActive = entry.isActive
                    record.updatedAt = entry.updatedAt
                    record.payload = payload
                } else {
                    context.insert(CollectionEntryRecord(clientID: entry.clientID.rawValue, ownerKey: ownerKey,
                                                         lotID: entry.lotID.rawValue, isActive: entry.isActive,
                                                         updatedAt: entry.updatedAt, payload: payload))
                }
            }
            for record in existing.values { context.delete(record) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

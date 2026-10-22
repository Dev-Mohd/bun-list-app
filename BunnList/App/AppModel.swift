import BunnListCore
import Foundation

/// Result of a collect/rate attempt that may need the same-bag answer first.
enum BagAttempt: Equatable {
    case done(CollectOutcome)
    case needsDecision(BagConflict)
    case failed
}

/// UI-facing state. Every change goes through Core on a copy and is published only after it is saved.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var catalog: Catalog?
    @Published private(set) var snapshot = LocalSnapshot()
    @Published private(set) var loadError: String?
    @Published var errorMessage: String?

    private var controller: LocalSnapshotController?
    private let makeStore: () throws -> LocalSnapshotStore
    private let now: () -> Date

    init(makeStore: @escaping () throws -> LocalSnapshotStore, now: @escaping () -> Date = Date.init) {
        self.makeStore = makeStore
        self.now = now
        reload()
    }

    /// UI tests launch with `-uiTesting` to use an empty in-memory store.
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        let inMemory = arguments.contains("-uiTesting")
        return AppModel(makeStore: {
            SwiftDataSnapshotStore(container: try SwiftDataSnapshotStore.makeContainer(inMemory: inMemory))
        })
    }

    var owner: OwnerID { snapshot.session.activeOwner }
    var book: CollectionBook { snapshot.book }

    func reload() {
        do {
            catalog = try Catalog.bundledSample()
            let controller = try LocalSnapshotController(store: makeStore())
            self.controller = controller
            snapshot = controller.snapshot
            loadError = nil
        } catch LocalStoreError.unsupportedSchemaVersion {
            controller = nil
            loadError = "البيانات المحلية من إصدار أحدث من هذا التطبيق. لم يُحذف شيء؛ حدّث التطبيق ثم أعد المحاولة."
        } catch {
            controller = nil
            loadError = "تعذّر فتح البيانات المحلية. لم يُحذف شيء؛ أعد المحاولة."
        }
    }

    func entry(for lot: LotID) -> CollectionEntry? { book.entry(owner: owner, lot: lot) }

    // MARK: Actions

    /// `operationID` must be created once per user intent and reused when answering the bag question.
    func collect(_ lot: LotID, decision: BagDecision? = nil, operationID: ClientID) -> BagAttempt {
        guard let catalog else { return .failed }
        let owner = owner
        let at = now()
        do {
            let outcome = try perform { try $0.book.collect(lot, owner: owner, catalog: catalog, decision: decision,
                                                            operationID: operationID, now: at) }
            return .done(outcome)
        } catch CollectionError.needsBagDecision(let conflict) {
            return .needsDecision(conflict)
        } catch {
            return .failed
        }
    }

    func removeFromOwned(_ lot: LotID) {
        let owner = owner
        let at = now()
        _ = try? perform { try $0.book.removeFromOwned(lot, owner: owner, now: at) }
    }

    func setFavorite(_ value: Bool, lot: LotID) { updateFlag { try $0.setFavorite(value, lot: lot, owner: $1, catalog: $2, now: $3) } }
    func setWantsToTry(_ value: Bool, lot: LotID) { updateFlag { try $0.setWantsToTry(value, lot: lot, owner: $1, catalog: $2, now: $3) } }
    func setTried(_ value: Bool, lot: LotID) { updateFlag { try $0.setTried(value, lot: lot, owner: $1, catalog: $2, now: $3) } }

    func assignSeason(from source: LotID, to target: LotID, operationID: ClientID) -> Bool {
        guard let catalog else { return false }
        let owner = owner
        let at = now()
        return (try? perform {
            try $0.book.assignSeason(owner: owner, from: source, to: target, moveCollection: true, moveRating: true,
                                     catalog: catalog, operationID: operationID, now: at)
        }) != nil
    }

    // MARK: Internals

    private func updateFlag(_ change: (inout CollectionBook, OwnerID, Catalog, Date) throws -> Void) {
        guard let catalog else { return }
        let owner = owner
        let at = now()
        _ = try? perform { try change(&$0.book, owner, catalog, at) }
    }

    /// Runs a Core change and saves it. Domain errors (a bag question, a validation block, a
    /// not-owner guard) rethrow cleanly so the caller can react; only a storage/unknown failure
    /// shows the generic retry message, with the visible state left unchanged.
    @discardableResult
    func perform<T>(_ change: (inout LocalSnapshot) throws -> T) throws -> T {
        guard let controller else {
            errorMessage = "البيانات المحلية غير متاحة."
            throw LocalStoreError.writeFailed
        }
        do {
            let result = try controller.mutate(change)
            snapshot = controller.snapshot
            return result
        } catch let error where error is CollectionError || error is RecipeError
            || error is ExperienceError || error is LifecycleError {
            throw error
        } catch {
            errorMessage = "تعذّر الحفظ على الجهاز. لم يتغير شيء؛ حاول مرة أخرى."
            throw error
        }
    }
}

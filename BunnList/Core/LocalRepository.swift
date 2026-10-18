import Foundation

protocol StatePersistence {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

struct JSONFilePersistence: StatePersistence {
    let fileURL: URL
    func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL)
    }
    func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }
}

/// Persist first, then publish state. Failed writes leave both the draft and the UI state intact.
final class LocalRepository {
    private let persistence: any StatePersistence
    private(set) var state: LocalState

    init(persistence: any StatePersistence) throws {
        self.persistence = persistence
        if let data = try persistence.load() {
            guard let loaded = try? JSONDecoder().decode(LocalState.self, from: data),
                  Self.isValid(loaded) else { throw LocalError.damagedFile }
            state = loaded
        } else {
            state = .demo()
            try persistence.save(JSONEncoder().encode(state))
        }
    }

    private func commit(_ change: (inout LocalState) throws -> Void) throws {
        var next = state
        try change(&next)
        guard Self.isValid(next) else { throw LocalError.damagedFile }
        try persistence.save(JSONEncoder().encode(next))
        state = next
    }

    func saveDraft(_ draft: ExperienceDraft) throws {
        try commit { next in
            if let id = draft.editingID {
                guard let original = next.experiences.first(where: { $0.id == id }) else { throw LocalError.missing }
                guard original.ownerID == next.localUserID else { throw LocalError.unauthorized }
            }
            next.draft = draft
        }
    }

    /// A stable draft ID also makes a second submission of an already published draft harmless.
    @discardableResult
    func publish(_ draft: ExperienceDraft, now: Date = Date()) throws -> UUID {
        if draft.editingID == nil, state.experiences.contains(where: { $0.id == draft.id && $0.ownerID == state.localUserID }) {
            return draft.id
        }
        guard let coffeeID = draft.coffeeID, state.coffee(coffeeID) != nil else {
            throw LocalError.invalid("اختر المحصول أولًا.")
        }
        guard let method = draft.method else { throw LocalError.invalid("اختر طريقة التحضير.") }
        guard (1...5).contains(draft.stars) else { throw LocalError.invalid("قيّم نتيجة تجربتك من نجمة إلى خمس نجوم قبل النشر.") }
        let recipe = try draft.validatedRecipe()
        let id = draft.editingID ?? draft.id
        try commit { next in
            if let editingID = draft.editingID {
                guard let index = next.experiences.firstIndex(where: { $0.id == editingID }) else { throw LocalError.missing }
                guard next.experiences[index].ownerID == next.localUserID else { throw LocalError.unauthorized }
                var experience = next.experiences[index]
                experience.coffeeID = coffeeID
                experience.method = method
                experience.stars = draft.stars
                experience.experiencedAt = draft.experiencedAt
                experience.note = draft.note
                experience.recipe = recipe
                experience.updatedAt = now
                next.experiences[index] = experience
            } else {
                next.experiences.insert(BrewExperience(id: id, ownerID: next.localUserID, coffeeID: coffeeID,
                    method: method, stars: draft.stars, experiencedAt: draft.experiencedAt, note: draft.note,
                    recipe: recipe, originalExperienceID: draft.originalExperienceID, createdAt: now, updatedAt: now), at: 0)
            }
            if next.draft?.id == draft.id { next.draft = nil }
        }
        return id
    }

    func deleteExperience(_ id: UUID) throws {
        try commit { next in
            guard let experience = next.experiences.first(where: { $0.id == id }) else { throw LocalError.missing }
            guard experience.ownerID == next.localUserID else { throw LocalError.unauthorized }
            next.experiences.removeAll { $0.id == id }
            if next.draft?.editingID == id { next.draft = nil }
        }
    }

    func rateCoffee(_ coffeeID: String, stars: Int) throws {
        guard state.coffee(coffeeID) != nil, (1...5).contains(stars) else { throw LocalError.invalid("اختر تقييمًا صحيحًا للمحصول.") }
        try commit { next in
            next.ratings.removeAll { $0.userID == next.localUserID && $0.coffeeID == coffeeID }
            next.ratings.append(CoffeeRating(userID: next.localUserID, coffeeID: coffeeID, stars: stars))
        }
    }

    func toggleLibrary(_ coffeeID: String, favorite: Bool) throws {
        guard state.coffee(coffeeID) != nil else { throw LocalError.missing }
        try commit { next in
            var entry = next.libraryEntry(for: coffeeID)
            if favorite { entry.isFavorite.toggle() } else { entry.wantsToTry.toggle() }
            next.library.removeAll { $0.userID == next.localUserID && $0.coffeeID == coffeeID }
            next.library.append(entry)
        }
    }

    private static func isValid(_ state: LocalState) -> Bool {
        let coffeeIDs = Set(state.coffees.map(\.id))
        let userIDs = Set(state.profiles.map(\.id))
        guard state.schemaVersion == 1, userIDs.contains(state.localUserID),
              coffeeIDs.count == state.coffees.count, userIDs.count == state.profiles.count,
              Set(state.experiences.map(\.id)).count == state.experiences.count,
              Set(state.ratings.map(\.id)).count == state.ratings.count,
              Set(state.library.map { "\($0.userID):\($0.coffeeID)" }).count == state.library.count else { return false }
        guard state.experiences.allSatisfy({ experience in
            let recipe = experience.recipe
            return coffeeIDs.contains(experience.coffeeID) && userIDs.contains(experience.ownerID)
                && (1...5).contains(experience.stars)
                && [recipe.coffeeGrams, recipe.waterGrams, recipe.yieldGrams, recipe.seconds].allSatisfy { $0 == nil || ($0!.isFinite && $0! > 0) }
                && (experience.method == .filter ? recipe.yieldGrams == nil : recipe.waterGrams == nil)
        }), state.ratings.allSatisfy({ coffeeIDs.contains($0.coffeeID) && userIDs.contains($0.userID) && (1...5).contains($0.stars) }),
        state.library.allSatisfy({ coffeeIDs.contains($0.coffeeID) && userIDs.contains($0.userID) }) else { return false }
        if let draft = state.draft {
            if let coffeeID = draft.coffeeID, !coffeeIDs.contains(coffeeID) { return false }
            if let editingID = draft.editingID,
               !state.experiences.contains(where: { $0.id == editingID && $0.ownerID == state.localUserID }) { return false }
        }
        return true
    }
}

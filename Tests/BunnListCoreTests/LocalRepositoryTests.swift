import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import BunnListCore
#else
@testable import BunnList
#endif

final class MemoryPersistence: StatePersistence {
    var data: Data?
    var fails = false
    func load() throws -> Data? { data }
    func save(_ data: Data) throws {
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        self.data = data
    }
}

final class LocalRepositoryTests: XCTestCase {
    private func draft(stars: Int = 4) -> ExperienceDraft {
        var draft = ExperienceDraft()
        draft.coffeeID = "ethiopia"
        draft.method = .filter
        draft.stars = stars
        draft.coffeeGrams = "١٥٫٥"
        draft.waterGrams = "250"
        draft.note = "تجربة اختبار"
        return draft
    }

    func testPublishAndRestoreFromRealFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = JSONFilePersistence(fileURL: directory.appendingPathComponent("state.json"))
        let repository = try LocalRepository(persistence: persistence)
        let draft = draft()
        try repository.saveDraft(draft)
        let id = try repository.publish(draft)
        let reopened = try LocalRepository(persistence: persistence)
        let saved = try XCTUnwrap(reopened.state.experiences.first { $0.id == id })
        XCTAssertEqual(saved.note, draft.note)
        XCTAssertEqual(saved.recipe.coffeeGrams, 15.5)
        XCTAssertEqual(saved.ownerID, reopened.state.localUserID)
        XCTAssertNil(reopened.state.draft)
        XCTAssertTrue(reopened.state.hasTried("ethiopia"))
    }

    func testMultipleExperiencesDoNotChangeCoffeeRatingAndSubmissionIsIdempotent() throws {
        let repository = try LocalRepository(persistence: MemoryPersistence())
        let oldAverage = repository.state.average(for: "ethiopia")
        let oldCount = repository.state.ratings.count
        let first = draft(stars: 1)
        let second = draft(stars: 5)
        let count = repository.state.experiences.count
        try repository.publish(first)
        try repository.publish(first)
        try repository.publish(second)
        XCTAssertEqual(repository.state.experiences.count, count + 2)
        XCTAssertEqual(repository.state.average(for: "ethiopia"), oldAverage)
        XCTAssertEqual(repository.state.ratings.count, oldCount)
    }

    func testUpdatingRatingReplacesOneVoteAndSurvivesRestart() throws {
        let storage = MemoryPersistence()
        let repository = try LocalRepository(persistence: storage)
        try repository.rateCoffee("ethiopia", stars: 1)
        try repository.rateCoffee("ethiopia", stars: 5)
        let reopened = try LocalRepository(persistence: storage)
        XCTAssertEqual(reopened.state.ratings(for: "ethiopia").count, 3)
        XCTAssertEqual(reopened.state.ratings.filter { $0.userID == "local" && $0.coffeeID == "ethiopia" }.map(\.stars), [5])
        XCTAssertEqual(try XCTUnwrap(reopened.state.average(for: "ethiopia")), 14.0 / 3.0, accuracy: 0.001)
    }

    func testRecipeCopyIsNewUnratedDraftAndLeavesOriginalIntact() throws {
        let repository = try LocalRepository(persistence: MemoryPersistence())
        let original = try XCTUnwrap(repository.state.experiences.first)
        let copy = ExperienceDraft.copyingRecipe(original)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.originalExperienceID, original.id)
        XCTAssertEqual(copy.stars, 0)
        XCTAssertEqual(copy.note, "")
        XCTAssertNil(copy.editingID)
        XCTAssertEqual(try copy.validatedRecipe(), original.recipe)
        try repository.saveDraft(copy)
        XCTAssertThrowsError(try repository.publish(copy))
        XCTAssertEqual(repository.state.experiences.first, original)
        XCTAssertEqual(repository.state.draft, copy)
    }

    func testInvalidPublishKeepsDraftAndInput() throws {
        let storage = MemoryPersistence()
        let repository = try LocalRepository(persistence: storage)
        let invalid = draft(stars: 0)
        try repository.saveDraft(invalid)
        let count = repository.state.experiences.count
        XCTAssertThrowsError(try repository.publish(invalid))
        let reopened = try LocalRepository(persistence: storage)
        XCTAssertEqual(reopened.state.draft, invalid)
        XCTAssertEqual(reopened.state.experiences.count, count)
        var missing = draft()
        missing.coffeeID = nil
        XCTAssertThrowsError(try repository.publish(missing))
        missing.coffeeID = "ethiopia"
        missing.method = nil
        XCTAssertThrowsError(try repository.publish(missing))
    }

    func testFailedDiskWriteIsAtomicAndRetryPublishesOnce() throws {
        let storage = MemoryPersistence()
        let repository = try LocalRepository(persistence: storage)
        let draft = draft()
        try repository.saveDraft(draft)
        let before = repository.state
        let beforeData = storage.data
        storage.fails = true
        XCTAssertThrowsError(try repository.publish(draft))
        XCTAssertEqual(repository.state, before)
        XCTAssertEqual(storage.data, beforeData)
        storage.fails = false
        try repository.publish(draft)
        try repository.publish(draft)
        XCTAssertEqual(repository.state.experiences.filter { $0.id == draft.id }.count, 1)
        XCTAssertNil(repository.state.draft)
    }

    func testOptionalQuantitiesArePositiveAndMethodSpecific() throws {
        for value in ["0", "-1", "NaN", "inf", "abc"] {
            var invalid = draft()
            invalid.coffeeGrams = value
            XCTAssertThrowsError(try invalid.validatedRecipe(), value)
        }
        var empty = draft()
        empty.coffeeGrams = ""
        empty.waterGrams = ""
        XCTAssertNil(try empty.validatedRecipe().coffeeGrams)
        XCTAssertNil(try empty.validatedRecipe().waterGrams)
        var espresso = draft()
        espresso.method = .espresso
        espresso.yieldGrams = "٣٦"
        espresso.waterGrams = "invalid hidden field"
        let recipe = try espresso.validatedRecipe()
        XCTAssertEqual(recipe.yieldGrams, 36)
        XCTAssertNil(recipe.waterGrams)
        var filter = draft()
        filter.yieldGrams = "invalid hidden field"
        XCTAssertNil(try filter.validatedRecipe().yieldGrams)
    }

    func testEditingPreservesIdentityCreationAndDeletingDoesNotRemoveRating() throws {
        let repository = try LocalRepository(persistence: MemoryPersistence())
        let original = try XCTUnwrap(repository.state.experiences.first { $0.ownerID == "local" })
        let ratings = repository.state.ratings
        var edit = ExperienceDraft.editing(original)
        edit.note = "ملاحظة محدثة"
        edit.stars = 2
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        try repository.saveDraft(edit)
        XCTAssertEqual(try repository.publish(edit, now: now), original.id)
        let updated = try XCTUnwrap(repository.state.experiences.first { $0.id == original.id })
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.updatedAt, now)
        XCTAssertEqual(updated.note, edit.note)
        try repository.deleteExperience(original.id)
        XCTAssertFalse(repository.state.hasTried(original.coffeeID))
        XCTAssertEqual(repository.state.ratings, ratings)
    }

    func testCannotEditOrDeleteOtherProfilesExperiences() throws {
        let repository = try LocalRepository(persistence: MemoryPersistence())
        let original = try XCTUnwrap(repository.state.experiences.first { $0.ownerID != "local" })
        let edit = ExperienceDraft.editing(original)
        XCTAssertThrowsError(try repository.saveDraft(edit))
        XCTAssertThrowsError(try repository.publish(edit))
        XCTAssertThrowsError(try repository.deleteExperience(original.id))
        XCTAssertTrue(repository.state.experiences.contains(original))
    }

    func testDraftAndLibrarySurviveRestart() throws {
        let storage = MemoryPersistence()
        let repository = try LocalRepository(persistence: storage)
        var incomplete = ExperienceDraft()
        incomplete.note = "مسودة غير مكتملة"
        try repository.saveDraft(incomplete)
        try repository.toggleLibrary("ethiopia", favorite: true)
        try repository.toggleLibrary("ethiopia", favorite: false)
        let reopened = try LocalRepository(persistence: storage)
        XCTAssertEqual(reopened.state.draft, incomplete)
        XCTAssertTrue(reopened.state.libraryEntry(for: "ethiopia").isFavorite)
        XCTAssertTrue(reopened.state.libraryEntry(for: "ethiopia").wantsToTry)
        try reopened.toggleLibrary("ethiopia", favorite: true)
        XCTAssertFalse(reopened.state.libraryEntry(for: "ethiopia").isFavorite)
        XCTAssertTrue(reopened.state.libraryEntry(for: "ethiopia").wantsToTry)
    }

    func testCorruptAndUnsupportedDataAreNotOverwritten() throws {
        let storage = MemoryPersistence()
        storage.data = Data("not JSON".utf8)
        let original = storage.data
        XCTAssertThrowsError(try LocalRepository(persistence: storage))
        XCTAssertEqual(storage.data, original)
        var state = LocalState.demo()
        state.schemaVersion = 999
        storage.data = try JSONEncoder().encode(state)
        XCTAssertThrowsError(try LocalRepository(persistence: storage))
        state.schemaVersion = 1
        state.ratings.append(state.ratings[0])
        storage.data = try JSONEncoder().encode(state)
        XCTAssertThrowsError(try LocalRepository(persistence: storage))
    }

    func testSearchFindsCoffeeAndRoasterAndEmptyResults() {
        let state = LocalState.demo()
        XCTAssertEqual(state.search("قوجي").map(\.id), ["ethiopia"])
        XCTAssertEqual(state.search("الأفق").map(\.id), ["colombia"])
        XCTAssertEqual(state.search("  ").count, 3)
        XCTAssertTrue(state.search("محصول غير موجود").isEmpty)
    }
}

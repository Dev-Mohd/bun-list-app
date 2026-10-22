import BunnListCore
import Foundation

/// Result of a rate attempt that may need the same-bag answer first (mirrors BagAttempt for collect).
enum RateAttempt: Equatable {
    case done(RatingOutcome)
    case needsDecision(BagConflict)
    case failed
}

/// C02 actions: lot rating, brew experiences, and recipes. Each goes through Core on a copy and is
/// published only after the snapshot is saved, reusing `perform`.
extension AppModel {
    // MARK: Rating

    func ratingStats(for lot: LotID) -> LotRatingStats {
        LotStats.rating(for: lot, votes: book.ratings)
    }

    func myRating(for lot: LotID) -> Int? {
        book.rating(owner: owner, lot: lot)?.stars
    }

    func rate(_ lot: LotID, stars: Int, decision: BagDecision? = nil, operationID: ClientID) -> RateAttempt {
        guard let catalog else { return .failed }
        let owner = owner
        let at = now()
        do {
            let outcome = try perform {
                try $0.book.rate(lot, stars: stars, owner: owner, catalog: catalog, decision: decision,
                                 operationID: operationID, now: at)
            }
            return .done(outcome)
        } catch CollectionError.needsBagDecision(let conflict) {
            return .needsDecision(conflict)
        } catch {
            return .failed
        }
    }

    // MARK: Experiences

    func experiences(for lot: LotID) -> [BrewExperience] {
        snapshot.experiences.published(lot: lot)
    }

    func myExperiences(for lot: LotID? = nil) -> [BrewExperience] {
        let all = snapshot.experiences.all(owner: owner)
        guard let lot else { return all }
        return all.filter { $0.lotID == lot }
    }

    func brewParticipants(for lot: LotID) -> [(method: ReferenceEntry, people: Int)] {
        LotStats.brewMethodParticipants(for: lot, in: snapshot.experiences)
            .compactMap { code, count in ReferenceCodes.brewMethod(code).map { ($0, count) } }
            .sorted { $0.people != $1.people ? $0.people > $1.people : $0.method.code < $1.method.code }
    }

    /// Adds a brew experience and publishes it. Returns false and surfaces a message on failure.
    @discardableResult
    func addExperience(lot: LotID, methodCode: String, stars: Int, brewedAt: Date, note: String) -> Bool {
        let owner = owner
        let at = now()
        return (try? perform {
            try $0.experiences.add(owner: owner, lot: lot, methodCode: methodCode, stars: stars,
                                   brewedAt: brewedAt, note: note, now: at, publish: true)
        }) != nil
    }

    func setExperienceLifecycle(_ id: ClientID, to target: ContentLifecycle) {
        let owner = owner
        let at = now()
        _ = try? perform { try $0.experiences.setLifecycle(id, owner: owner, to: target, now: at) }
    }

    // MARK: Recipes

    func myRecipes() -> [Recipe] { snapshot.recipes.all(owner: owner) }

    func recipe(_ id: ClientID) -> Recipe? { snapshot.recipes.recipe(id, owner: owner) }

    /// Saves a draft (valid or not). Returns its id, or nil if the save failed.
    func saveRecipeDraft(_ recipe: Recipe) -> ClientID? {
        try? perform { $0.recipes.saveDraft(recipe) }
    }

    /// Publishes a recipe. Returns the validation problems that blocked it, or [] on success.
    func publishRecipe(_ id: ClientID) -> [RecipeProblem] {
        let owner = owner
        let at = now()
        do {
            try perform { try $0.recipes.publish(id, owner: owner, now: at) }
            return []
        } catch RecipeError.notPublishable(let problems) {
            return problems
        } catch {
            return []
        }
    }

    @discardableResult
    func copyRecipe(_ id: ClientID) -> ClientID? {
        let owner = owner
        let at = now()
        return try? perform { try $0.recipes.copy(id, by: owner, now: at) }
    }

    func setRecipeLifecycle(_ id: ClientID, to target: ContentLifecycle) {
        let owner = owner
        let at = now()
        _ = try? perform { try $0.recipes.setLifecycle(id, owner: owner, to: target, now: at) }
    }
}

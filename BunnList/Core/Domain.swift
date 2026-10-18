import Foundation

enum BrewMethod: String, Codable, CaseIterable, Identifiable {
    case filter, espresso
    var id: String { rawValue }
    var title: String { self == .filter ? "ترشيح" : "إسبريسو" }
}

struct CoffeeLot: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var roaster: String
    var origin: String?
    var process: String?
    var tastingNotes: String?
}

struct PublicProfile: Identifiable, Codable, Equatable {
    var id: String
    var displayName: String
}

struct Recipe: Codable, Equatable {
    var coffeeGrams: Double?
    var waterGrams: Double?
    var yieldGrams: Double?
    var seconds: Double?
    var grind: String?
}

struct BrewExperience: Identifiable, Codable, Equatable {
    var id: UUID
    var ownerID: String
    var coffeeID: String
    var method: BrewMethod
    var stars: Int
    var experiencedAt: Date
    var note: String
    var recipe: Recipe
    var originalExperienceID: UUID?
    var createdAt: Date
    var updatedAt: Date
}

struct ExperienceDraft: Identifiable, Codable, Equatable {
    var id = UUID()
    var editingID: UUID?
    var coffeeID: String?
    var method: BrewMethod?
    var stars = 0
    var experiencedAt = Date()
    var note = ""
    var coffeeGrams = ""
    var waterGrams = ""
    var yieldGrams = ""
    var seconds = ""
    var grind = ""
    var originalExperienceID: UUID?

    static func editing(_ experience: BrewExperience) -> Self {
        var draft = copyingRecipe(experience)
        draft.editingID = experience.id
        draft.stars = experience.stars
        draft.note = experience.note
        draft.experiencedAt = experience.experiencedAt
        draft.originalExperienceID = experience.originalExperienceID
        return draft
    }

    static func copyingRecipe(_ experience: BrewExperience) -> Self {
        var draft = Self()
        draft.coffeeID = experience.coffeeID
        draft.method = experience.method
        draft.coffeeGrams = experience.recipe.coffeeGrams.map { String($0) } ?? ""
        draft.waterGrams = experience.recipe.waterGrams.map { String($0) } ?? ""
        draft.yieldGrams = experience.recipe.yieldGrams.map { String($0) } ?? ""
        draft.seconds = experience.recipe.seconds.map { String($0) } ?? ""
        draft.grind = experience.recipe.grind ?? ""
        draft.originalExperienceID = experience.id
        return draft
    }

    func validatedRecipe() throws -> Recipe {
        Recipe(
            coffeeGrams: try Self.quantity(coffeeGrams, label: "كمية البن"),
            waterGrams: method == .filter ? try Self.quantity(waterGrams, label: "كمية الماء") : nil,
            yieldGrams: method == .espresso ? try Self.quantity(yieldGrams, label: "ناتج الإسبريسو") : nil,
            seconds: try Self.quantity(seconds, label: "مدة التحضير"),
            grind: grind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : grind
        )
    }

    private static func quantity(_ input: String, label: String) throws -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digits = trimmed.map { char -> String in
            if let value = char.wholeNumberValue { return String(value) }
            return String(char)
        }.joined().replacingOccurrences(of: "٫", with: ".").replacingOccurrences(of: ",", with: ".")
        guard let number = Double(digits), number.isFinite, number > 0 else {
            throw LocalError.invalid("أدخل قيمة موجبة صحيحة لحقل \(label)، أو اتركه فارغًا.")
        }
        return number
    }
}

struct CoffeeRating: Codable, Equatable, Identifiable {
    var userID: String
    var coffeeID: String
    var stars: Int
    var id: String { "\(userID):\(coffeeID)" }
}

struct LibraryEntry: Codable, Equatable {
    var userID: String
    var coffeeID: String
    var isFavorite = false
    var wantsToTry = false
}

struct LocalState: Codable, Equatable {
    var schemaVersion = 1
    var localUserID: String
    var coffees: [CoffeeLot]
    var profiles: [PublicProfile]
    var experiences: [BrewExperience]
    var draft: ExperienceDraft?
    var ratings: [CoffeeRating]
    var library: [LibraryEntry]

    func coffee(_ id: String) -> CoffeeLot? { coffees.first { $0.id == id } }
    func profile(_ id: String) -> PublicProfile? { profiles.first { $0.id == id } }
    func ratings(for coffeeID: String) -> [CoffeeRating] { ratings.filter { $0.coffeeID == coffeeID } }
    func average(for coffeeID: String) -> Double? {
        let values = ratings(for: coffeeID)
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0) { $0 + $1.stars }) / Double(values.count)
    }
    func libraryEntry(for coffeeID: String) -> LibraryEntry {
        library.first { $0.userID == localUserID && $0.coffeeID == coffeeID }
            ?? LibraryEntry(userID: localUserID, coffeeID: coffeeID)
    }
    func hasTried(_ coffeeID: String) -> Bool {
        experiences.contains { $0.ownerID == localUserID && $0.coffeeID == coffeeID }
    }
    func search(_ query: String) -> [CoffeeLot] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return coffees }
        return coffees.filter {
            $0.name.localizedStandardContains(query) || $0.roaster.localizedStandardContains(query)
        }
    }
}

enum LocalError: LocalizedError {
    case invalid(String)
    case unauthorized
    case missing
    case damagedFile
    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .unauthorized: return "يمكنك إدارة تجارب حسابك المحلي فقط."
        case .missing: return "لم يعد العنصر متاحًا."
        case .damagedFile: return "تعذّرت قراءة بيانات الجهاز. لم تُستبدل بياناتك؛ احتفظ بملفها وافحصه قبل المتابعة."
        }
    }
}

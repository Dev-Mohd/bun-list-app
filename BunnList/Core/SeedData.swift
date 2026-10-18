import Foundation

extension LocalState {
    static func demo() -> Self {
        let date = Date(timeIntervalSince1970: 1_792_281_600)
        let coffees = [
            CoffeeLot(id: "ethiopia", name: "قوجي — إثيوبيا", roaster: "محمصة السهل · تجريبية", origin: "إثيوبيا، قوجي", process: "مجففة", tastingNotes: "توت · ياسمين · شوكولاتة"),
            CoffeeLot(id: "colombia", name: "هويلا — كولومبيا", roaster: "محمصة الأفق · تجريبية", origin: "كولومبيا، هويلا", process: "مغسولة", tastingNotes: "كراميل · برتقال · لوز"),
            CoffeeLot(id: "kenya", name: "نييري — كينيا", roaster: "محمصة الوادي · تجريبية", origin: "كينيا، نييري", process: "مغسولة", tastingNotes: "كشمش · حمضيات · شاي أسود")
        ]
        let profiles = [
            PublicProfile(id: "local", displayName: "حسابي التجريبي"),
            PublicProfile(id: "sara", displayName: "سارة · شخصية تجريبية"),
            PublicProfile(id: "omar", displayName: "عمر · شخصية تجريبية")
        ]
        let experiences = [
            BrewExperience(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, ownerID: "sara", coffeeID: "ethiopia", method: .filter, stars: 5, experiencedAt: date, note: "رائحة زهرية وحلاوة واضحة بعد أن تبرد القهوة. تجربة توضيحية.", recipe: Recipe(coffeeGrams: 15, waterGrams: 250, seconds: 150, grind: "متوسطة"), createdAt: date, updatedAt: date),
            BrewExperience(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, ownerID: "omar", coffeeID: "colombia", method: .espresso, stars: 4, experiencedAt: date.addingTimeInterval(-3600), note: "قوام متوازن ونهاية تشبه الكراميل. تجربة توضيحية.", recipe: Recipe(coffeeGrams: 18, yieldGrams: 36, seconds: 28), createdAt: date.addingTimeInterval(-3600), updatedAt: date),
            BrewExperience(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, ownerID: "local", coffeeID: "kenya", method: .filter, stars: 4, experiencedAt: date.addingTimeInterval(-7200), note: "حموضة لطيفة ونكهة فاكهية. يمكنك تعديل هذه التجربة المحلية أو حذفها.", recipe: Recipe(coffeeGrams: 20, waterGrams: 320), createdAt: date.addingTimeInterval(-7200), updatedAt: date)
        ]
        return Self(localUserID: "local", coffees: coffees, profiles: profiles, experiences: experiences,
                    ratings: [CoffeeRating(userID: "sara", coffeeID: "ethiopia", stars: 5),
                              CoffeeRating(userID: "omar", coffeeID: "ethiopia", stars: 4),
                              CoffeeRating(userID: "local", coffeeID: "kenya", stars: 4)], library: [])
    }
}

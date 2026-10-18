import SwiftUI
import UIKit

enum Brand {
    static let ink = Color("Ink")
    static let olive = Color("Olive")
    static let background = Color("Background")
    static let gold = Color("Gold")
    static let brown = Color("Brown")
}

struct BrandHeading: View {
    var body: some View {
        HStack(spacing: 12) {
            if let image = UIImage(named: "BunnListSymbol") {
                Image(uiImage: image).resizable().scaledToFit().frame(width: 42, height: 48)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("بن لست").font(.title.bold()).foregroundStyle(Brand.ink)
                Text("اكتشف قهوتك، وشارك تجربتك").font(.subheadline).foregroundStyle(.secondary)
                if UIImage(named: "BunnListSymbol") == nil {
                    Text("ملف الشعار الأصلي غير مضمّن بعد").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct DemoNotice: View {
    var body: some View {
        Label("نسخة تجريبية — النشر على هذا الجهاز فقط", systemImage: "iphone")
            .font(.caption).foregroundStyle(Brand.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(Brand.olive.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
    }
}

struct StarsView: View {
    let value: Int
    var label = "تقييم التجربة"
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= value ? "star.fill" : "star")
                    .foregroundStyle(Brand.gold)
            }
        }.font(.caption)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label): \(value) من ٥ نجوم")
    }
}

struct StarPicker: View {
    @Binding var value: Int
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.medium))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) { starButtons }
                VStack(alignment: .leading, spacing: 4) { starButtons }
            }
            Text(value == 0 ? "لم تختر تقييمًا" : "\(value) من ٥ نجوم")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var starButtons: some View {
        ForEach(1...5, id: \.self) { star in
            Button { value = star } label: {
                Image(systemName: star <= value ? "star.fill" : "star")
                    .font(.title2).foregroundStyle(Brand.gold)
                    .frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.plain)
                .accessibilityIdentifier("rating-star-\(star)")
                .accessibilityLabel("\(label): \(star) من ٥ نجوم")
                .accessibilityAddTraits(value == star ? .isSelected : [])
        }
    }
}

struct CoffeeCard: View {
    @EnvironmentObject private var store: AppStore
    let coffee: CoffeeLot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(coffee.name).font(.headline).foregroundStyle(Brand.ink)
                    Text(coffee.roaster).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "leaf").font(.title2).foregroundStyle(Brand.olive).accessibilityHidden(true)
            }
            if let notes = coffee.tastingNotes { Text(notes).font(.caption).foregroundStyle(Brand.brown) }
            if let average = store.state.average(for: coffee.id) {
                Label("\(average.formatted(.number.precision(.fractionLength(1)))) · \(store.state.ratings(for: coffee.id).count) تقييم للمحصول", systemImage: "star.fill")
                    .font(.caption).foregroundStyle(Brand.ink)
            } else { Text("لا توجد تقييمات للمحصول بعد").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Brand.olive.opacity(0.18)))
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct ExperienceCard: View {
    @EnvironmentObject private var store: AppStore
    let experience: BrewExperience
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label(store.state.profile(experience.ownerID)?.displayName ?? "مستخدم تجريبي", systemImage: "person.crop.circle")
                    .font(.subheadline).foregroundStyle(Brand.olive)
                Spacer(minLength: 4)
                Text(experience.method.title).font(.caption).foregroundStyle(.secondary)
            }
            Text(store.state.coffee(experience.coffeeID)?.name ?? "محصول").font(.headline).foregroundStyle(Brand.ink)
            StarsView(value: experience.stars)
            if !experience.note.isEmpty { Text(experience.note).font(.body).foregroundStyle(Brand.ink).lineLimit(3) }
            Text(experience.experiencedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Brand.olive.opacity(0.18)))
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

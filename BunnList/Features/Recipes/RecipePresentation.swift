import BunnListCore
import SwiftUI

extension AuthModel {
    /// Runs `call` with the access token; on 401 refreshes once and retries.
    func withToken<T>(_ call: (String) async throws -> T) async throws -> T {
        guard let token = currentAccessToken() else { throw APIError.unauthorized }
        do {
            return try await call(token)
        } catch APIError.unauthorized {
            guard let fresh = await refreshAccessToken() else { throw APIError.unauthorized }
            return try await call(fresh)
        }
    }

    /// Like `withToken`, but signed-out callers go without one.
    func withOptionalToken<T>(_ call: (String?) async throws -> T) async throws -> T {
        guard isSignedIn else { return try await call(nil) }
        return try await withToken { try await call($0) }
    }
}

/// Arabic labels and number formatting shared by the recipe screens.
enum RecipeText {
    static func method(_ code: String) -> String { ReferenceCodes.brewMethod(code)?.nameAr ?? code }

    static func temperature(_ t: BrewTemperature) -> String { t == .iced ? "مثلج" : "ساخن" }

    static func stepKind(_ kind: RecipeStepKind) -> String {
        switch kind {
        case .bloom: return "تفتيح"
        case .pour: return "صبة"
        case .wait: return "انتظار"
        case .swirl: return "تدوير"
        case .stir: return "تقليب"
        case .press: return "ضغط"
        case .serve: return "تقديم"
        }
    }

    static func stepIcon(_ kind: RecipeStepKind) -> String {
        switch kind {
        case .bloom: return "drop.circle"
        case .pour: return "drop.fill"
        case .wait: return "hourglass"
        case .swirl: return "tornado"
        case .stir: return "arrow.triangle.2.circlepath"
        case .press: return "arrow.down.to.line"
        case .serve: return "cup.and.saucer.fill"
        }
    }

    static let stepKinds: [RecipeStepKind] = [.bloom, .pour, .wait, .swirl, .stir, .press, .serve]

    /// "دائري · بطيء" for a pour, or nil when neither is set.
    static func pourDetail(_ step: RemoteRecipeStep) -> String? {
        let parts = [step.pourStyle?.nameAr, step.pourSpeed?.nameAr].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func number(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func ratio(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "1:" + value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func problem(_ problem: RecipeProblem) -> String {
        switch problem {
        case .missingTitle: return "أضف عنوانًا للوصفة"
        case .missingMethod: return "اختر طريقة التحضير"
        case .missingHotWater: return "حدّد كمية الماء"
        case .pourSumDoesNotMatchHotWater: return "مجموع الصبات لا يساوي كمية الماء"
        case .negativeOrZeroWater: return "كل صبة تحتاج كمية ماء أكبر من صفر"
        case .missingEspressoDose: return "حدّد وزن البن"
        case .missingEspressoYield: return "حدّد وزن الناتج"
        case .waterOnNonPourStep: return "الماء يُضاف فقط في التفتيح والصبات"
        case .missingGrind: return "حدّد درجة الطحن"
        case .missingSteps: return "أضف خطوات التحضير"
        }
    }

    static func state(_ state: RemoteExperience.State) -> String {
        switch state {
        case .draft: return "مسودة"
        case .published: return "منشورة"
        case .unpublished: return "غير منشورة"
        case .deleted: return "محذوفة"
        }
    }
}

/// The dark summary card at the top of the editor and detail screens.
struct RecipeSummaryCard: View {
    let title: String
    let methodCode: String
    let temperature: BrewTemperature
    let ratio: Double?
    let waterTempC: Double?
    let totalSeconds: Int
    let outputGrams: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: temperature == .iced ? "snowflake" : "cup.and.saucer.fill")
                    .font(.title3)
                    .foregroundStyle(Brand.gold)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? "وصفة بدون اسم" : title).font(.title3.bold()).foregroundStyle(.white)
                    Text("\(RecipeText.method(methodCode)) · \(RecipeText.temperature(temperature))")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                stat(RecipeText.ratio(ratio), "النسبة")
                divider
                stat(waterTempC.map { "\(RecipeText.number($0))°" } ?? "—", "الحرارة")
                divider
                stat(totalSeconds > 0 ? RecipeText.duration(totalSeconds) : "—", "الوقت")
                divider
                stat(outputGrams.map { "\(RecipeText.number($0))غ" } ?? "—", "الناتج")
            }
        }
        .padding(18)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 32)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.headline, design: .monospaced)).foregroundStyle(Brand.gold)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

extension RecipeSummaryCard {
    init(draft: RecipeDraft) {
        self.init(title: draft.title, methodCode: draft.methodCode, temperature: draft.temperature,
                  ratio: draft.ratio, waterTempC: draft.waterTempC, totalSeconds: draft.totalSeconds,
                  outputGrams: draft.outputGrams)
    }
}

/// A selectable capsule used for method / type / coffee choices.
struct ChoiceChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(isSelected ? Color.black : Color.secondary.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(isSelected ? 0 : 0.3)))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// One recipe in a list.
struct RecipeListRow: View {
    let recipe: RemoteRecipe
    var showsAuthor = false

    private var draft: RecipeDraft { RecipeDraft(editing: recipe) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(recipe.title.isEmpty ? "وصفة بدون اسم" : recipe.title).font(.headline)
                Spacer()
                if recipe.isMine && recipe.state != .published {
                    Text(RecipeText.state(recipe.state)).font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            Text("\(RecipeText.method(recipe.methodCode)) · \(RecipeText.temperature(recipe.temperature)) · \(RecipeText.ratio(draft.ratio))")
                .font(.caption).foregroundStyle(.secondary)
            if let lot = recipe.lot {
                Label("\(lot.nameAr) — \(lot.roasterNameAr)", systemImage: "leaf").font(.caption).foregroundStyle(Brand.olive)
            }
            if showsAuthor {
                Label(recipe.authorName, systemImage: "person").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

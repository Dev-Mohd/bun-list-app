import BunnListCore
import SwiftUI

/// «كيف طلعت؟» after a brew: one tap. Tapping a star saves the brew experience
/// straight away (private unless published) with the brew log (recipe, grind, time,
/// taste), which is what earns its points and passport stamp under the usual rules.
/// The taste, the note and publishing are extras that update the same record;
/// without stars, nothing is saved. Picking a taste shows one change to try next time.
@MainActor
struct BrewFinishView: View {
    let ref: BrewFinishRef

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var stars = 0
    @State private var taste: BrewTaste?
    @State private var note = ""
    @State private var publish = false
    @State private var isSaving = false
    /// One record per brew: every save after the first edits it.
    @State private var clientID = UUID().uuidString
    @State private var savedOnce = false
    @State private var brewedAt = Date()
    /// Something changed while a save was in flight: save again after it.
    @State private var dirty = false
    @State private var saved = false
    @State private var errorMessage: String?
    @State private var keepingRecipe: RecipeDraft?
    @State private var keptRecipe = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var fix: TasteFix? {
        taste.map {
            TasteFix.suggest(taste: $0, methodCode: ref.plan.methodCode, setting: ref.grindSetting, grinder: ref.grinder,
                             doseGrams: ref.plan.doseGrams,
                             waterGrams: ref.plan.isEspresso ? ref.plan.yieldGrams : ref.plan.hotWaterGrams)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if saved { savedView } else { form }
            }
            .brandScreen()
            .navigationTitle("كيف طلعت؟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !saved && stars == 0 {
                    ToolbarItem(placement: .cancellationAction) { Button("تخطّي") { dismiss() } }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(item: Binding(get: { keepingRecipe.map(KeptDraft.init) }, set: { if $0 == nil { keepingRecipe = nil } })) { kept in
            ServerRecipeEditor(draft: kept.draft) { _ in keptRecipe = true }
                .environmentObject(auth)
        }
    }

    private var form: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Text(ref.coffeeName).font(.headline)
                    Text("\(RecipeText.method(ref.plan.methodCode))\(ref.seconds > 0 ? " · " + RecipeText.duration(ref.seconds) : "")")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { n in
                            Button {
                                stars = n
                                Task { await save() }
                            } label: {
                                Image(systemName: n <= stars ? "star.fill" : "star")
                                    .font(.system(size: 34)).foregroundStyle(n <= stars ? Brand.gold : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(n) نجوم")
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .sensoryFeedback(.selection, trigger: stars)
                    .padding(.top, 6)
                    if savedOnce {
                        Label("انحفظت", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold()).foregroundStyle(Brand.olive)
                            .transition(.opacity)
                    } else if stars == 0 {
                        Text("اضغط نجمة وتنحفظ على طول").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Section("الطعم بكلمة") {
                TasteChips(selected: $taste)
                    .onChange(of: taste) { _, _ in if stars > 0 { Task { await save() } } }
                if let fix { FixCard(fix: fix, lead: "المرة الجاية") }
            }
            Section {
                if !ref.grindSetting.trimmingCharacters(in: .whitespaces).isEmpty {
                    LabeledContent("الطحنة", value: ref.grindSetting)
                }
                LabeledContent("الوصفة", value: ref.plan.title)
                TextField("ملاحظة (اختياري)", text: $note, axis: .vertical).lineLimit(1...4)
            }
            Section {
                Toggle("انشرها مع تجارب هالقهوة", isOn: $publish).tint(Brand.olive)
            } footer: {
                Text("النجمة تكفي. الطعم والملاحظة والنشر إضافات تتحدّث على نفس التجربة.")
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            Section {
                Button {
                    Task {
                        // The note and the publish toggle go in with this last save.
                        let stored = await save()
                        // A save already in flight picks these up when it finishes.
                        if stored || isSaving { withAnimation { saved = true } }
                    }
                } label: {
                    Text("تم").font(.headline).frame(maxWidth: .infinity)
                }
                .disabled(stars == 0)
            }
        }
    }

    private var savedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(Brand.olive)
                .symbolEffect(.bounce, value: saved)
            Text("انحفظت تجربتك").font(.title2.bold())
            Text("تلقاها في صفحة القهوة، وتحسب في نقاطك وجوازك حسب القواعد.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let fix {
                FixCard(fix: fix, lead: "المرة الجاية").padding(.top, 4)
                Text("بنذكّرك فيها أول ما تختار هالقهوة في «حضّر».").font(.caption).foregroundStyle(.secondary)
            }
            if canKeepRecipe {
                Button {
                    keepingRecipe = RecipeDraft(
                        plan: ref.plan, lot: RemoteRecipeLot(slug: ref.slug, nameAr: ref.coffeeName, roasterNameAr: ref.roasterName),
                        grinderId: ref.grinder?.id, grindSetting: ref.grindSetting)
                } label: {
                    Label(keptRecipe ? "انحفظت في وصفاتك" : "احفظها كوصفة لك", systemImage: keptRecipe ? "checkmark" : "bookmark")
                }
                .buttonStyle(.bordered)
                .disabled(keptRecipe)
                .padding(.top, 4)
            }
            Button("تم") { dismiss() }.buttonStyle(.borderedProminent).tint(Brand.olive).padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: saved)
    }

    /// A barista or community recipe that went well can be kept as one's own.
    private var canKeepRecipe: Bool {
        if case .mine = ref.plan.source { return false }
        return auth.isSignedIn
    }

    /// Saves (or updates) this brew's record. True when what's on screen is stored.
    @discardableResult
    private func save() async -> Bool {
        guard stars > 0 else { return false }
        if isSaving { dirty = true; return false }
        isSaving = true
        defer { isSaving = false }
        var ok = false
        repeat {
            dirty = false
            let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
            let log = BrewLogEntry(plan: ref.plan, grinderId: ref.grinder?.id, grindSetting: ref.grindSetting,
                                   seconds: ref.seconds, taste: taste)
            let rating = stars, shared = publish
            do {
                _ = try await auth.withToken {
                    try await client.saveExperience(slug: ref.slug, accessToken: $0, clientID: clientID,
                                                    methodCode: ref.plan.methodCode, stars: rating, brewedAt: brewedAt,
                                                    note: text, publish: shared, log: log)
                }
                errorMessage = nil
                withAnimation { savedOnce = true }
                ok = true
            } catch APIError.forbidden {
                errorMessage = "حسابك موقوف عن النشر حاليًا."
                ok = false
            } catch {
                errorMessage = "ما انحفظت. حاول مرة ثانية."
                ok = false
            }
        } while dirty
        return ok
    }
}

/// One taste word at a time; tapping it again clears it.
private struct TasteChips: View {
    @Binding var selected: BrewTaste?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(BrewTaste.allCases, id: \.self) { taste in
                let on = selected == taste
                Button {
                    withAnimation(.spring(response: 0.3)) { selected = on ? nil : taste }
                } label: {
                    VStack(spacing: 2) {
                        Text(taste.nameAr).font(.subheadline.bold())
                        Text(taste.hintAr).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(on ? Brand.background.opacity(0.8) : .secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8).padding(.horizontal, 4)
                    .background(on ? Brand.olive : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(on ? Brand.background : Brand.ink)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: on)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// One suggested change, said plainly as a suggestion.
struct FixCard: View {
    let fix: TasteFix
    let lead: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: fix.change == .keep ? "checkmark.seal.fill" : "wand.and.stars")
                .font(.title3).foregroundStyle(Brand.olive)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(lead): \(fix.titleAr)").font(.subheadline.bold()).foregroundStyle(Brand.ink)
                Text(fix.detailAr).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.olive.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct KeptDraft: Identifiable {
    let draft: RecipeDraft
    var id: String { draft.clientID }
}

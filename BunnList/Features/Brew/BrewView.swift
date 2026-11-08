import BunnListCore
import SwiftUI

/// «حضّر»: pick the coffee (the last one you brewed first) and the method, then a
/// recipe from the tabs (★ for this coffee: the roaster's and the community's; BunnList's
/// starting and champion recipes; yours; the community's), swipe between them, set how
/// many cups (everything scales), set the grind, brew with the timer, and optionally
/// note how it came out. «آخر مرة» brings back your last brew of this coffee and
/// method with one change to try. Scanning lives in search and the scan buttons now.
@MainActor
struct BrewView: View {
    @EnvironmentObject private var auth: AuthModel
    /// Slugs, most recent first, comma-separated.
    @AppStorage("recentBrews") private var recentRaw = ""
    @AppStorage("lastBrewMethod") private var method = "V60"
    /// Set by the home's «كمّل» card: the coffee to open on.
    @AppStorage("brewFocus") private var focusSlug = ""
    @AppStorage("myGrinderID") private var myGrinderID = ""
    @AppStorage(MyGrinder.key) private var myGuideGrinderID = ""
    @ObservedObject private var grinders = GrinderCatalog.shared

    @State private var coffees: [RemoteCollectionItem]?
    @State private var failed = false
    @State private var selectedSlug: String?
    @State private var groups: BrewPlanner.Groups?
    @State private var tab: BrewPlanner.Groups.Tab = .bunnlist
    @State private var selectedPlanID: String?
    /// The card showing in the swipeable row; selecting follows it.
    @State private var pageID: String?
    @State private var cups = 1
    @State private var newRecipe: DraftRef?
    @State private var memory: BrewMemory?
    @State private var grindSetting = ""
    @State private var session: BrewSessionRef?
    @State private var pendingFinish: BrewFinishRef?
    @State private var finishing: BrewFinishRef?
    @State private var showScan = false
    @State private var showAdd = false
    @State private var showSignIn = false
    @State private var showGrinder = false
    @State private var showRecipes = false
    @State private var showConverter = false
    @State private var lastBrew: RemoteHome.LastBrew?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var recent: [String] { recentRaw.split(separator: ",").map(String.init) }
    private var selected: RemoteCollectionItem? { coffees?.first { $0.slug == selectedSlug } }
    private var basePlan: BrewPlan? { groups?.all.first { $0.id == selectedPlanID } ?? groups?.plans(tab).first }
    /// The selected recipe at the chosen number of cups: what gets brewed and logged.
    private var plan: BrewPlan? { basePlan?.scaled(toCups: cups) }
    private var guideGrinder: RemoteGrinder? { grinders.grinder(myGuideGrinderID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if auth.isSignedIn { content } else { signedOut }
            }
            .safeAreaInset(edge: .bottom) { if auth.isSignedIn { startButton } }
            .background(Brand.background.ignoresSafeArea())
            .brandScreen()
            .navigationTitle("وش بتحضّر؟")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showScan = true } label: { Image(systemName: "camera.viewfinder") }
                        .accessibilityLabel("امسح كيس")
                }
            }
            .task(id: auth.isSignedIn) { await loadCoffees() }
            .onChange(of: focusSlug) { _, _ in Task { await applyFocus() } }
            .refreshable { await loadCoffees() }
            // Reloads when the guide grinder arrives too, so last time's setting carries over.
            .task(id: "\(selectedSlug ?? "")|\(method)|\(guideGrinder?.id ?? "")") { await loadPlans() }
            .sheet(isPresented: $showScan) { AIBagScanView().environmentObject(auth) }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await loadCoffees() } }) {
                AddCoffeeSearchView().environmentObject(auth)
            }
            .sheet(isPresented: $showSignIn) { SignInView() }
            .sheet(isPresented: $showRecipes) { RecipesHubView() }
            .sheet(item: $newRecipe, onDismiss: { Task { await loadPlans() } }) { ref in
                ServerRecipeEditor(draft: ref.draft) { _ in }.environmentObject(auth)
            }
            .sheet(isPresented: $showConverter) { GrindConverterView() }
            .task(id: auth.isSignedIn) { await loadLastBrew() }
            .sheet(isPresented: $showGrinder) { NavigationStack { GrinderGuideView(showsDone: true) }.environmentObject(auth) }
            .task { await grinders.load() }
            .fullScreenCover(item: $session, onDismiss: {
                if let pendingFinish { finishing = pendingFinish; self.pendingFinish = nil }
            }) { ref in
                BrewSessionView(plan: ref.plan) { seconds in
                    remember(ref.slug)
                    pendingFinish = BrewFinishRef(slug: ref.slug, coffeeName: ref.coffeeName, plan: ref.plan, seconds: seconds,
                                                  grinder: ref.grinder, grindSetting: ref.grindSetting, roasterName: ref.roasterName)
                }
            }
            .sheet(item: $finishing, onDismiss: { Task { await loadPlans(); await loadLastBrew() } }) { ref in
                BrewFinishView(ref: ref).environmentObject(auth)
            }
        }
    }

    // MARK: Signed out

    private var signedOut: some View {
        VStack(spacing: 14) {
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 54)).foregroundStyle(Brand.olive)
            Text("حضّر قهوتك خطوة بخطوة").font(.title3.bold())
            Text("سجّل دخولك عشان نجيب قهوات مجموعتك ووصفاتك، ونحفظ تجاربك.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("تسجيل الدخول") { showSignIn = true }
                .buttonStyle(.borderedProminent).tint(Brand.olive)
        }
        .padding(32)
        .padding(.top, 60)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let lastBrew, lastBrew.lot.slug != selectedSlug || lastBrew.experience.methodCode != method {
                ContinueCard(lot: lastBrew.lot,
                             memory: BrewMemory.latest([lastBrew.experience], methodCode: lastBrew.experience.methodCode,
                                                       grinder: guideGrinder),
                             methodCode: lastBrew.experience.methodCode) {
                    method = lastBrew.experience.methodCode
                    focusSlug = lastBrew.lot.slug
                }
                .padding(.horizontal)
            }
            coffeeSection
            if selected != nil {
                methodSection
                recipeSection
            }
            tools
        }
        .padding(.vertical)
    }

    private var coffeeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let coffees {
                if coffees.isEmpty {
                    emptyCollection
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(coffees) { item in coffeeTile(item) }
                            addTile
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
            } else if failed {
                Label("ما قدرنا نجيب مجموعتك. اسحب للتحديث.", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary).padding(.horizontal)
            } else {
                HStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 150, corner: 16).frame(width: 112) } }
                    .padding(.horizontal)
            }
        }
    }

    private func coffeeTile(_ item: RemoteCollectionItem) -> some View {
        let isSelected = item.slug == selectedSlug
        return Button {
            withAnimation(.spring(response: 0.3)) { selectedSlug = item.slug }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                LotPhotoWell(imageUrl: item.imageUrl, notes: [], roaster: item.roasterNameAr, name: item.nameAr,
                             origin: item.originNameAr, originCode: item.originCode, padding: 4)
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? Brand.olive : .clear, lineWidth: 3))
                Text(item.nameAr).font(.subheadline.bold()).lineLimit(1)
                Text(recent.first == item.slug ? "آخر وحدة حضّرتها" : item.roasterNameAr)
                    .font(.caption2).foregroundStyle(recent.first == item.slug ? Brand.olive : .secondary).lineLimit(1)
            }
            .frame(width: 112)
            .scaleEffect(isSelected ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var addTile: some View {
        Button { showAdd = true } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.title2.bold())
                Text("قهوة ثانية").font(.caption.bold())
            }
            .foregroundStyle(Brand.olive)
            .frame(width: 112, height: 112)
            .background(RoundedRectangle(cornerRadius: 16).stroke(Brand.olive.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }

    private var emptyCollection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("مجموعتك فاضية. أضف القهوة اللي عندك وابدأ.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button { showAdd = true } label: { Label("ابحث عنها", systemImage: "magnifyingglass") }
                    .buttonStyle(.borderedProminent).tint(Brand.olive)
                Button { showScan = true } label: { Label("امسح الكيس", systemImage: "camera.viewfinder") }
                    .buttonStyle(.bordered).tint(Brand.olive)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("الطريقة").font(.title3.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BrewPlanner.methods, id: \.self) { code in
                        let on = code == method
                        Button { method = code } label: {
                            Text(RecipeText.method(code))
                                .font(.subheadline.bold())
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(on ? Brand.olive : Color(.secondarySystemGroupedBackground), in: Capsule())
                                .foregroundStyle(on ? Brand.background : Brand.ink)
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: on)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private var recipeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let memory { LastBrewCard(memory: memory).padding(.horizontal) }
            HStack(alignment: .firstTextBaseline) {
                Text("الوصفة").font(.title3.bold())
                Spacer()
                if (groups?.plans(tab).count ?? 0) > 1 {
                    Label("اسحب لوصفات ثانية", systemImage: "hand.draw").font(.caption).foregroundStyle(Brand.olive)
                }
            }
            .padding(.horizontal)
            if let groups {
                recipeTabs(groups)
                if groups.plans(tab).isEmpty {
                    // «وصفاتي» always shows; empty, it offers to make one for this coffee and method.
                    CreateRecipeCard {
                        var draft = RecipeDraft(lot: selected.map { RemoteRecipeLot(slug: $0.slug, nameAr: $0.nameAr, roasterNameAr: $0.roasterNameAr) })
                        if let preset = BrewPreset.presets(for: method).first ?? BrewPreset.all.first { draft.apply(preset) }
                        newRecipe = DraftRef(draft: draft)
                    }
                    .padding(.horizontal)
                } else {
                    recipeCards(groups.plans(tab))
                }
                GrindRow(grinder: guideGrinder, setting: $grindSetting, hint: basePlan?.grindText ?? "") { showGrinder = true }
                    .padding(.horizontal)
            } else {
                VStack(spacing: 10) { SkeletonBlock(height: 34, corner: 17).frame(width: 220); SkeletonBlock(height: 170, corner: 18) }
                    .padding(.horizontal)
            }
        }
    }

    private func recipeTabs(_ groups: BrewPlanner.Groups) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(BrewPlanner.Groups.Tab.allCases.filter { groups.tabs.contains($0) || $0 == .mine }, id: \.self) { t in
                    let on = t == tab
                    let gold = t == .forCoffee
                    Button { select(tab: t) } label: {
                        Text("\(t.titleAr) \(groups.plans(t).count.formatted())")
                            .font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(on ? (gold ? Brand.gold : Brand.ink) : (gold ? Brand.gold.opacity(0.15) : Color(.secondarySystemGroupedBackground)),
                                        in: Capsule())
                            .foregroundStyle(on ? Brand.background : (gold ? Brand.gold : Brand.ink))
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: on)
                }
            }
            .padding(.horizontal)
        }
    }

    private func recipeCards(_ options: [BrewPlan]) -> some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(options) { option in
                        let isSelected = option.id == basePlan?.id
                        PlanCard(plan: isSelected ? option.scaled(toCups: cups) : option, base: option, isSelected: isSelected,
                                 cups: isSelected ? cups : option.baseCups,
                                 guideGrinder: guideGrinder, legacyGrinder: Grinder.find(myGrinderID),
                                 onCups: { cups = $0 }) {
                            withAnimation(.snappy) { pageID = option.id }
                        }
                        .containerRelativeFrame(.horizontal)
                        .id(option.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $pageID)
            .onChange(of: pageID) { _, id in
                guard let id, id != selectedPlanID else { return }
                selectPlan(id)
            }
            if options.count > 1 {
                HStack(spacing: 5) {
                    ForEach(options) { option in
                        Capsule().fill(option.id == basePlan?.id ? Brand.olive : Color.secondary.opacity(0.3))
                            .frame(width: option.id == basePlan?.id ? 16 : 6, height: 6)
                    }
                }
                .animation(.snappy, value: basePlan?.id)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func select(tab t: BrewPlanner.Groups.Tab) {
        tab = t
        guard let first = groups?.plans(t).first else { return }
        selectPlan(first.id)
        pageID = first.id
    }

    /// Picks a recipe: back to its own number of cups, and its suggested grind unless last time's is kept.
    private func selectPlan(_ id: String) {
        selectedPlanID = id
        guard let option = groups?.all.first(where: { $0.id == id }) else { return }
        cups = option.baseCups
        if memory?.startingSetting(grinderId: guideGrinder?.id) == nil { grindSetting = suggestedSetting(for: option) }
    }

    /// Recipes and the grind converter (they used to sit on the home).
    private var tools: some View {
        HStack(spacing: 10) {
            toolButton("الوصفات", icon: "book.closed.fill") { showRecipes = true }
            toolButton("محوّل الطحن", icon: "dial.medium.fill") { showConverter = true }
        }
        .padding(.horizontal)
    }

    private func toolButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(Brand.olive)
        }
        .buttonStyle(.plain)
    }

    private func loadLastBrew() async {
        guard auth.isSignedIn else { lastBrew = nil; return }
        lastBrew = (try? await auth.withToken { try await client.fetchHome(accessToken: $0) })?.lastBrew
    }

    @ViewBuilder
    private var startButton: some View {
        if let plan, let coffee = selected {
            Button {
                BrewTip().invalidate(reason: .actionPerformed)
                session = BrewSessionRef(slug: coffee.slug, coffeeName: coffee.nameAr, plan: plan,
                                         grinder: guideGrinder, grindSetting: grindSetting, roasterName: coffee.roasterNameAr)
            } label: {
                Label("ابدأ التحضير", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Brand.olive, in: Capsule())
                    .foregroundStyle(Brand.background)
                    .shadow(color: Brand.olive.opacity(0.3), radius: 12, y: 6)
            }
            .appTip(BrewTip(), arrowEdge: .bottom)
            .buttonStyle(CardPressStyle())
            .padding(.horizontal)
            .padding(.bottom, 8)
            .accessibilityIdentifier("brew-begin")
        }
    }

    // MARK: Data

    private func loadCoffees() async {
        guard auth.isSignedIn else { return }
        do {
            let items = try await auth.withToken { try await client.fetchCollection(accessToken: $0) }
            // Bags you own first, then everything else; the last brewed always leads.
            let owned = items.filter(\.owned) + items.filter { !$0.owned }
            coffees = BrewPlanner.ordered(owned, slug: \.slug, recent: recent)
            failed = false
            if selectedSlug == nil || !(coffees ?? []).contains(where: { $0.slug == selectedSlug }) {
                selectedSlug = coffees?.first?.slug
            }
            if !focusSlug.isEmpty, (coffees ?? []).contains(where: { $0.slug == focusSlug }) {
                selectedSlug = focusSlug
                focusSlug = ""
            }
        } catch {
            failed = coffees == nil
        }
    }

    private func loadPlans() async {
        guard let slug = selectedSlug else { return }
        groups = nil
        selectedPlanID = nil
        pageID = nil
        memory = nil
        let mine = (try? await auth.withToken { try await client.fetchMyRecipes(accessToken: $0) }) ?? []
        let lotCommunity = (try? await auth.withOptionalToken { try await client.exploreRecipes(lotSlug: slug, accessToken: $0) }) ?? []
        let methodCommunity = (try? await auth.withOptionalToken { try await client.exploreRecipes(accessToken: $0) }) ?? []
        let detail = try? await client.fetchLotDetail(slug: slug)
        let history = (try? await auth.withToken { try await client.fetchMyExperiences(slug: slug, accessToken: $0) }) ?? []
        guard slug == selectedSlug else { return }
        let found = BrewPlanner.groups(methodCode: method, lotSlug: slug, roasterName: detail?.roasterNameAr ?? selected?.roasterNameAr ?? "المحمصة",
                                       roasterRecipes: detail?.roasterRecipes ?? [], mine: mine,
                                       lotCommunity: lotCommunity, methodCommunity: methodCommunity)
        let last = BrewMemory.latest(history, methodCode: method, grinder: guideGrinder)
        groups = found
        memory = last
        // Last time's recipe leads again when it's still on offer; otherwise this coffee's own, else BunnList's.
        let lastID = found.all.first { $0.id == last?.log.recipeId }?.id
        tab = found.tab(of: lastID) ?? found.defaultTab
        let id = lastID ?? found.plans(tab).first?.id
        selectedPlanID = id
        pageID = id
        cups = found.all.first { $0.id == id }?.baseCups ?? 1
        grindSetting = last?.startingSetting(grinderId: guideGrinder?.id)
            ?? found.all.first { $0.id == id }.map(suggestedSetting(for:)) ?? ""
    }

    /// Your grinder's approximate clicks for the recipe, when known.
    private func suggestedSetting(for plan: BrewPlan) -> String {
        plan.approximateClicks(on: guideGrinder).map(String.init) ?? ""
    }

    /// Selects the coffee the home asked for, reloading the collection if it's new there.
    private func applyFocus() async {
        guard !focusSlug.isEmpty else { return }
        if coffees?.contains(where: { $0.slug == focusSlug }) != true { await loadCoffees() }
        if coffees?.contains(where: { $0.slug == focusSlug }) == true { selectedSlug = focusSlug }
        focusSlug = ""
    }

    private func remember(_ slug: String) {
        recentRaw = BrewPlanner.remember(slug, in: recent).joined(separator: ",")
    }
}

struct BrewSessionRef: Identifiable {
    let slug: String
    let coffeeName: String
    let plan: BrewPlan
    let grinder: RemoteGrinder?
    let grindSetting: String
    var roasterName = ""
    var id: String { slug + plan.id }
}

struct BrewFinishRef: Identifiable {
    let slug: String
    let coffeeName: String
    let plan: BrewPlan
    let seconds: Int
    let grinder: RemoteGrinder?
    let grindSetting: String
    var roasterName = ""
    var id: String { slug + plan.id + String(seconds) }
}

/// «آخر مرة»: how your last brew of this coffee and method went, and the one
/// change to try this time.
private struct LastBrewCard: View {
    let memory: BrewMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("آخر مرة", systemImage: "clock.arrow.circlepath").font(.subheadline.bold())
                Spacer()
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { n in
                        Image(systemName: n <= memory.stars ? "star.fill" : "star").font(.caption2)
                            .foregroundStyle(n <= memory.stars ? Brand.gold : .secondary)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            Text(summary).font(.caption).foregroundStyle(.secondary)
            if let fix = memory.fix { FixCard(fix: fix, lead: "هالمرة") }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let log = memory.log
        var parts: [String] = []
        if let taste = log.taste { parts.append("طلعت \(taste.nameAr)") }
        if let setting = log.grindSetting { parts.append("طحنة \(setting)") }
        if let s = log.brewSeconds { parts.append(RecipeText.duration(s)) }
        if let title = log.recipeTitle { parts.append(title) }
        if let date = memory.brewedAt { parts.append(date.formatted(.relative(presentation: .named))) }
        return parts.joined(separator: " · ")
    }
}

/// The grind you'll actually use, logged with the brew: a number stepper on a
/// counting grinder, free text otherwise.
private struct GrindRow: View {
    let grinder: RemoteGrinder?
    @Binding var setting: String
    /// The recipe's grind in words, shown as the suggestion when there's no number yet.
    var hint: String = ""
    var chooseGrinder: () -> Void

    private var counts: Bool { grinder?.adjustment == "clicks" || grinder?.adjustment == "stepped" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("طحنتك", systemImage: "dial.medium").font(.subheadline.bold())
                Spacer()
                Button(action: chooseGrinder) {
                    Text(grinder.map { "\($0.brand) \($0.title)" } ?? "اختر مطحنتك").font(.caption.bold()).lineLimit(1)
                }
                .tint(Brand.olive)
            }
            if counts {
                HStack(spacing: 14) {
                    stepButton("minus", -1)
                    TextField("—", text: $setting)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.title2.bold().monospacedDigit())
                        .frame(minWidth: 70)
                    stepButton("plus", 1)
                    Text(grinder?.adjustment == "clicks" ? "كليك" : "درجة").font(.caption).foregroundStyle(.secondary)
                }
                .environment(\.layoutDirection, .leftToRight)
                .frame(maxWidth: .infinity)
            } else {
                TextField(hint.isEmpty ? (grinder == nil ? "مثلًا: ٢٢ كليك أو متوسط ناعم" : "رقمك على المطحنة") : "مقترح: \(hint)",
                          text: $setting)
                    .textFieldStyle(.roundedBorder)
            }
            Text("نحفظها مع التجربة عشان المرة الجاية نبدأ منها.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func stepButton(_ symbol: String, _ delta: Double) -> some View {
        Button {
            let value = (Double(setting.replacingOccurrences(of: ",", with: ".")) ?? (grinder?.rangeMin ?? 0)) + delta
            let clamped = min(max(value, grinder?.rangeMin ?? 0), grinder?.rangeMax ?? 999)
            setting = clamped == clamped.rounded() ? String(Int(clamped)) : String(format: "%.1f", clamped)
        } label: {
            Image(systemName: symbol).font(.headline)
                .frame(width: 40, height: 40).background(Brand.background, in: Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: setting)
        .accessibilityLabel(delta < 0 ? "أنعم" : "أخشن")
    }
}

/// One recipe option: where it's from, the numbers, and the grind (with your
/// grinder's approximate clicks when both are known).
private struct PlanCard: View {
    /// The recipe at the chosen cups (what the numbers show).
    let plan: BrewPlan
    /// As written, for the cups stepper's range.
    let base: BrewPlan
    let isSelected: Bool
    let cups: Int
    let guideGrinder: RemoteGrinder?
    let legacyGrinder: Grinder?
    var onCups: (Int) -> Void
    var onSelect: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(plan.title).font(.headline).foregroundStyle(Brand.ink)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Brand.olive : .secondary)
                }
                Text(plan.sourceAr)
                    .font(.caption.bold())
                    .foregroundStyle(sourceColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(sourceColor.opacity(0.12), in: Capsule())
                if isSelected, base.scalesByCups { cupsRow }
                HStack(spacing: 8) {
                    fact(RecipeText.number(plan.doseGrams) + "غ", "بن")
                    if plan.isEspresso {
                        fact(RecipeText.number(plan.yieldGrams) + "غ", "ناتج")
                    } else {
                        fact(RecipeText.number(plan.hotWaterGrams) + "غ", "ماء")
                    }
                    fact(RecipeText.number(plan.waterTempC) + "°", "حرارة")
                    if plan.usesTimer, plan.totalSeconds > 0 { fact(RecipeText.minutes(plan.totalSeconds), "وقت") }
                }
                if !plan.grindText.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("الطحنة: \(plan.grindText)", systemImage: "dial.medium").font(.caption)
                        if let (clicks, name) = conversion {
                            Text("≈ \(clicks) كليك على \(name) · تقريبي، ابدأ منه وعدّل بذوقك")
                                .font(.caption2).foregroundStyle(Brand.olive)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                if let credit = plan.credit, let url = URL(string: credit.sourceURL) {
                    Button { openURL(url) } label: {
                        Label(credit.advanced ? "متقدمة · المصدر المنشور" : "المصدر المنشور", systemImage: "link")
                            .font(.caption2.bold())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.gold)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isSelected ? strokeColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Your guide grinder first; the older built-in list for those who picked there.
    private var conversion: (Int, String)? {
        if let g = guideGrinder, let c = plan.approximateClicks(on: g) { return (c, "\(g.brand) \(g.title)") }
        if guideGrinder == nil, let g = legacyGrinder, let c = plan.approximateClicks(on: g) { return (c, g.name) }
        return nil
    }

    private var sourceColor: Color {
        switch plan.source {
        case .mine: return Brand.olive
        case .community, .roaster, .champion: return Brand.gold
        case .base: return Brand.brown
        }
    }

    /// This coffee's roaster recipe stands out in gold, as do champions'.
    private var isGold: Bool {
        switch plan.source {
        case .roaster, .champion: return true
        default: return false
        }
    }
    private var strokeColor: Color { isGold ? Brand.gold : Brand.olive }
    private var cardFill: AnyShapeStyle {
        isGold ? AnyShapeStyle(LinearGradient(colors: [Color(.secondarySystemGroupedBackground), Brand.gold.opacity(0.08)],
                                              startPoint: .top, endPoint: .bottom))
               : AnyShapeStyle(Color(.secondarySystemGroupedBackground))
    }

    /// «كم كوب؟»: coffee, water and every pour follow the count; the strength stays.
    private var cupsRow: some View {
        HStack {
            Text(base.cupNameAr == "فنجان" ? "كم فنجان؟" : "كم كوب؟").font(.subheadline.bold())
            Spacer()
            HStack(spacing: 14) {
                cupButton("minus", cups - 1, enabled: cups > 1)
                Text(cups.formatted()).font(.title3.bold().monospacedDigit()).frame(minWidth: 26)
                cupButton("plus", cups + 1, enabled: cups < base.maxCups)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Brand.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private func cupButton(_ symbol: String, _ value: Int, enabled: Bool) -> some View {
        Button { onCups(value) } label: {
            Image(systemName: symbol).font(.headline)
                .frame(width: 34, height: 34)
                .background(symbol == "plus" ? Brand.olive : Color.secondary.opacity(0.15), in: Circle())
                .foregroundStyle(symbol == "plus" ? Brand.background : Brand.ink)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .sensoryFeedback(.selection, trigger: cups)
        .accessibilityLabel(symbol == "plus" ? "كوب زيادة" : "كوب أقل")
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.subheadline.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Brand.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }
}

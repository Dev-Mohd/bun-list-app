import BunnListCore
import SwiftUI

/// «حضّر»: pick the coffee (the last one you brewed first) and the method, take a
/// recipe (yours, then the community's for this coffee, then a BunnList starting
/// recipe, always saying which), set the grind, brew with the timer, and optionally
/// note how it came out. «آخر مرة» brings back your last brew of this coffee and
/// method with one change to try. Scanning lives in search and the scan buttons now.
@MainActor
struct BrewView: View {
    @EnvironmentObject private var auth: AuthModel
    /// Slugs, most recent first, comma-separated.
    @AppStorage("recentBrews") private var recentRaw = ""
    @AppStorage("lastBrewMethod") private var method = "V60"
    @AppStorage("myGrinderID") private var myGrinderID = ""
    @AppStorage(MyGrinder.key) private var myGuideGrinderID = ""
    @ObservedObject private var grinders = GrinderCatalog.shared

    @State private var coffees: [RemoteCollectionItem]?
    @State private var failed = false
    @State private var selectedSlug: String?
    @State private var plans: [BrewPlan]?
    @State private var selectedPlanID: String?
    @State private var memory: BrewMemory?
    @State private var grindSetting = ""
    @State private var session: BrewSessionRef?
    @State private var pendingFinish: BrewFinishRef?
    @State private var finishing: BrewFinishRef?
    @State private var showScan = false
    @State private var showAdd = false
    @State private var showSignIn = false
    @State private var showGrinder = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var recent: [String] { recentRaw.split(separator: ",").map(String.init) }
    private var selected: RemoteCollectionItem? { coffees?.first { $0.slug == selectedSlug } }
    private var plan: BrewPlan? { plans?.first { $0.id == selectedPlanID } ?? plans?.first }
    private var guideGrinder: RemoteGrinder? { grinders.grinder(myGuideGrinderID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if auth.isSignedIn { content } else { signedOut }
            }
            .safeAreaInset(edge: .bottom) { if auth.isSignedIn { startButton } }
            .background(Brand.background.ignoresSafeArea())
            .brandScreen()
            .navigationTitle("حضّر")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showScan = true } label: { Image(systemName: "camera.viewfinder") }
                        .accessibilityLabel("امسح كيس")
                }
            }
            .task(id: auth.isSignedIn) { await loadCoffees() }
            .refreshable { await loadCoffees() }
            // Reloads when the guide grinder arrives too, so last time's setting carries over.
            .task(id: "\(selectedSlug ?? "")|\(method)|\(guideGrinder?.id ?? "")") { await loadPlans() }
            .sheet(isPresented: $showScan) { AIBagScanView().environmentObject(auth) }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await loadCoffees() } }) {
                AddCoffeeSearchView().environmentObject(auth)
            }
            .sheet(isPresented: $showSignIn) { SignInView() }
            .sheet(isPresented: $showGrinder) { NavigationStack { GrinderGuideView(showsDone: true) }.environmentObject(auth) }
            .task { await grinders.load() }
            .fullScreenCover(item: $session, onDismiss: {
                if let pendingFinish { finishing = pendingFinish; self.pendingFinish = nil }
            }) { ref in
                BrewSessionView(plan: ref.plan) { seconds in
                    remember(ref.slug)
                    pendingFinish = BrewFinishRef(slug: ref.slug, coffeeName: ref.coffeeName, plan: ref.plan, seconds: seconds,
                                                  grinder: ref.grinder, grindSetting: ref.grindSetting)
                }
            }
            .sheet(item: $finishing, onDismiss: { Task { await loadPlans() } }) { ref in
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
            coffeeSection
            if selected != nil {
                methodSection
                recipeSection
            }
        }
        .padding(.vertical)
    }

    private var coffeeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("وش بتحضّر؟").font(.title3.bold()).padding(.horizontal)
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
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 30)
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
            Text("الوصفة").font(.title3.bold()).padding(.horizontal)
            if let plans {
                VStack(spacing: 10) {
                    ForEach(plans) { option in
                        PlanCard(plan: option, isSelected: option.id == plan?.id,
                                 guideGrinder: guideGrinder, legacyGrinder: Grinder.find(myGrinderID)) {
                            selectedPlanID = option.id
                            if memory?.startingSetting(grinderId: guideGrinder?.id) == nil { grindSetting = suggestedSetting(for: option) }
                        }
                    }
                }
                .padding(.horizontal)
                GrindRow(grinder: guideGrinder, setting: $grindSetting) { showGrinder = true }
                    .padding(.horizontal)
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 20)
            }
        }
    }

    @ViewBuilder
    private var startButton: some View {
        if let plan, let coffee = selected {
            Button {
                session = BrewSessionRef(slug: coffee.slug, coffeeName: coffee.nameAr, plan: plan,
                                         grinder: guideGrinder, grindSetting: grindSetting)
            } label: {
                Label("ابدأ التحضير", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Brand.olive, in: Capsule())
                    .foregroundStyle(Brand.background)
                    .shadow(color: Brand.olive.opacity(0.3), radius: 12, y: 6)
            }
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
        } catch {
            failed = coffees == nil
        }
    }

    private func loadPlans() async {
        guard let slug = selectedSlug else { return }
        plans = nil
        selectedPlanID = nil
        memory = nil
        let mine = (try? await auth.withToken { try await client.fetchMyRecipes(accessToken: $0) }) ?? []
        let community = (try? await auth.withOptionalToken { try await client.exploreRecipes(lotSlug: slug, accessToken: $0) }) ?? []
        let history = (try? await auth.withToken { try await client.fetchMyExperiences(slug: slug, accessToken: $0) }) ?? []
        guard slug == selectedSlug else { return }
        let options = BrewPlanner.options(methodCode: method, lotSlug: slug, mine: mine, community: community)
        let last = BrewMemory.latest(history, methodCode: method, grinder: guideGrinder)
        plans = options
        memory = last
        // Last time's recipe leads again when it's still on offer.
        selectedPlanID = options.first { $0.id == last?.log.recipeId }?.id ?? options.first?.id
        grindSetting = last?.startingSetting(grinderId: guideGrinder?.id)
            ?? options.first { $0.id == selectedPlanID }.map(suggestedSetting(for:)) ?? ""
    }

    /// Your grinder's approximate clicks for the recipe, when known.
    private func suggestedSetting(for plan: BrewPlan) -> String {
        plan.approximateClicks(on: guideGrinder).map(String.init) ?? ""
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
    var id: String { slug + plan.id }
}

struct BrewFinishRef: Identifiable {
    let slug: String
    let coffeeName: String
    let plan: BrewPlan
    let seconds: Int
    let grinder: RemoteGrinder?
    let grindSetting: String
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
                TextField(grinder == nil ? "مثلًا: ٢٢ كليك أو متوسط ناعم" : "رقمك على المطحنة", text: $setting)
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
    let plan: BrewPlan
    let isSelected: Bool
    let guideGrinder: RemoteGrinder?
    let legacyGrinder: Grinder?
    var onSelect: () -> Void

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
                HStack(spacing: 8) {
                    fact(RecipeText.number(plan.doseGrams) + "غ", "بن")
                    if plan.isEspresso {
                        fact(RecipeText.number(plan.yieldGrams) + "غ", "ناتج")
                    } else {
                        fact(RecipeText.number(plan.hotWaterGrams) + "غ", "ماء")
                    }
                    fact(RecipeText.number(plan.waterTempC) + "°", "حرارة")
                    if plan.usesTimer, plan.totalSeconds > 0 { fact(RecipeText.duration(plan.totalSeconds), "وقت") }
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
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isSelected ? Brand.olive : .clear, lineWidth: 2))
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
        case .community: return Brand.gold
        case .base: return Brand.brown
        }
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

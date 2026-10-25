import BunnListCore
import SwiftUI

/// "رحلتك": coffee journeys/quests whose progress is computed from the signed-in
/// user's server collection (coffees owned/tried, distinct origins and roasters,
/// favorites). Guests see the quests locked with a prompt to sign in.
struct JourneysView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var items: [RemoteCollectionItem] = []
    @State private var showSignIn = false

    private var quests: [Quest] {
        let owned = items.filter(\.owned).count
        let tried = items.filter(\.tried).count
        let favorite = items.filter(\.favorite).count
        let origins = Set(items.compactMap(\.originCode)).count
        let roasters = Set(items.map(\.roasterNameAr).filter { !$0.isEmpty }).count
        return [
            Quest(id: "collect", title: "اجمع قهوتك", subtitle: "اجمع ٥ محاصيل في مجموعتك.",
                  icon: "square.stack.3d.up.fill", color: Brand.olive, current: owned, target: 5),
            Quest(id: "taste", title: "ذوّاق", subtitle: "جرّب ٥ محاصيل مختلفة.",
                  icon: "cup.and.saucer.fill", color: Brand.brown, current: tried, target: 5),
            Quest(id: "origins", title: "مستكشف المناشئ", subtitle: "اجمع قهوة من ٥ دول مختلفة.",
                  icon: "globe", color: Color.green, current: origins, target: 5),
            Quest(id: "roasters", title: "جامع المحامص", subtitle: "اجمع قهوة من ٥ محامص.",
                  icon: "building.2.fill", color: Brand.gold, current: roasters, target: 5),
            Quest(id: "favorites", title: "المفضّلة", subtitle: "علّم ٥ محاصيل كمفضّلة.",
                  icon: "heart.fill", color: Color.red, current: favorite, target: 5),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if !auth.isSignedIn { signInCard }
                    ForEach(quests) { QuestCard(quest: $0, locked: !auth.isSignedIn) }
                }
                .padding()
            }
            .brandScreen()
            .navigationTitle("رحلتك")
            .task { await load() }
            .onChange(of: auth.isSignedIn) { _, _ in Task { await load() } }
            .refreshable { await load() }
            .sheet(isPresented: $showSignIn) { SignInView() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Circle().fill(Brand.olive.opacity(0.15)).frame(width: 84, height: 84)
                .overlay(Image(systemName: "map.fill").font(.largeTitle).foregroundStyle(Brand.olive))
            Text("انطلق في مغامرات القهوة").font(.title2.bold()).foregroundStyle(Brand.ink)
            Text("اجمع، جرّب، واستكشف — وافتح مغامرات جديدة كل ما كبرت مجموعتك.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var signInCard: some View {
        Button { showSignIn = true } label: {
            VStack(spacing: 8) {
                Text("مغامرتك تنتظرك").font(.headline).foregroundStyle(Brand.ink)
                Text("سجّل الدخول وابدأ رحلات القهوة وتابع تقدّمك.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Label("سجّل دخول", systemImage: "person.badge.plus")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Brand.ink, in: Capsule()).foregroundStyle(Brand.background)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Brand.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard auth.isSignedIn, let token = auth.currentAccessToken() else { items = []; return }
        let client = CatalogAPIClient(transport: URLSessionTransport())
        do {
            items = try await client.fetchCollection(accessToken: token)
        } catch APIError.unauthorized {
            if let fresh = await auth.refreshAccessToken() {
                items = (try? await client.fetchCollection(accessToken: fresh)) ?? items
            }
        } catch {
            // keep what we have
        }
    }
}

private struct Quest: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let current: Int
    let target: Int

    var done: Bool { current >= target }
    var progress: Double { target == 0 ? 0 : min(1, Double(current) / Double(target)) }
}

private struct QuestCard: View {
    let quest: Quest
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(quest.color.opacity(locked ? 0.25 : 1))
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: quest.icon).font(.title3).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(quest.title).font(.headline).foregroundStyle(Brand.ink)
                        if quest.done { Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.olive) }
                        if locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(quest.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ProgressView(value: quest.progress).tint(quest.color)
            Text("\(quest.current)/\(quest.target)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        .opacity(locked ? 0.7 : 1)
    }
}

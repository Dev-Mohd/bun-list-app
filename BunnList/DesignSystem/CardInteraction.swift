import BunnListCore
import SwiftUI

// What makes a coffee card feel alive: it sinks a little under the finger while
// the bag lifts off the card, a long press opens a preview with quick actions
// (favorite, tried, want to try, share), and the action answers with a haptic
// and an icon that pops over the bag.

private struct CardPressedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True while the card around this view is held down.
    var cardPressed: Bool {
        get { self[CardPressedKey.self] }
        set { self[CardPressedKey.self] = newValue }
    }
}

/// For NavigationLinks around coffee cards: a soft sink, the bag lifts, a light tap.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.cardPressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension View {
    /// Cards fade and settle in as they scroll into view.
    func cardScrollIn() -> some View {
        scrollTransition(.animated(.spring(response: 0.45, dampingFraction: 0.8))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.55)
                .scaleEffect(phase.isIdentity ? 1 : 0.92)
                .offset(y: phase.isIdentity ? 0 : (phase == .topLeading ? -8 : 12))
        }
    }

    /// Side cards in a horizontal row lean back and shrink, like a carousel.
    func carouselCard() -> some View {
        scrollTransition(axis: .horizontal) { content, phase in
            content
                .scaleEffect(1 - abs(phase.value) * 0.08)
                .rotation3DEffect(.degrees(phase.value * -10), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .opacity(1 - abs(phase.value) * 0.25)
        }
    }

    /// Long-press preview and quick collection actions for a coffee card.
    func lotQuickActions(slug: String, name: String, roaster: String, imageUrl: String?, notes: [String],
                         origin: String?, originCode: String?, known: RemoteCollectionFlags? = nil) -> some View {
        modifier(LotQuickActions(slug: slug, name: name, roaster: roaster, imageUrl: imageUrl, notes: notes,
                                 origin: origin, originCode: originCode, known: known))
    }
}

/// The context menu, its preview, and the pop that confirms an action.
private struct LotQuickActions: ViewModifier {
    let slug: String
    let name: String
    let roaster: String
    let imageUrl: String?
    let notes: [String]
    let origin: String?
    let originCode: String?
    /// The flags when the caller already has them (collection); otherwise read on use.
    let known: RemoteCollectionFlags?

    @EnvironmentObject private var auth: AuthModel
    @State private var flags: RemoteCollectionFlags?
    @State private var burst: String?
    @State private var burstTick = 0
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    enum Flag { case favorite, tried, wantsToTry }

    private var current: RemoteCollectionFlags? { flags ?? known }

    func body(content: Content) -> some View {
        content
            .overlay {
                if let burst {
                    Image(systemName: burst)
                        .font(.system(size: 54, weight: .bold))
                        .foregroundStyle(.white, Brand.olive)
                        .symbolRenderingMode(.palette)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .sensoryFeedback(.success, trigger: burstTick)
            .contextMenu {
                if auth.isSignedIn {
                    button(.favorite, on: "إزالة من المفضلة", off: "أضف للمفضلة", icon: "heart")
                    button(.tried, on: "ما جرّبتها", off: "جرّبتها", icon: "cup.and.saucer")
                    button(.wantsToTry, on: "إزالة من أبي أجربها", off: "أبي أجربها", icon: "bookmark")
                }
                ShareLink(item: ServerConfig.baseURL.appendingPathComponent("coffees").appendingPathComponent(slug),
                          message: Text("\(name) من \(roaster) على BunnList")) {
                    Label("مشاركة", systemImage: "square.and.arrow.up")
                }
            } preview: {
                preview
            }
    }

    private func isOn(_ flag: Flag) -> Bool {
        current.map { Self.value(flag, in: $0) } ?? false
    }

    private static func value(_ flag: Flag, in f: RemoteCollectionFlags) -> Bool {
        switch flag {
        case .favorite: return f.favorite
        case .tried: return f.tried
        case .wantsToTry: return f.wantsToTry
        }
    }

    private func button(_ flag: Flag, on: String, off: String, icon: String) -> some View {
        let active = isOn(flag)
        return Button { Task { await toggle(flag) } } label: {
            Label(active ? on : off, systemImage: active ? icon + ".slash" : icon)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            LotPhotoWell(imageUrl: imageUrl, notes: notes, roaster: roaster, name: name, origin: origin, originCode: originCode, padding: 8)
                .frame(width: 280, height: 280)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.title3.bold())
                Text(roaster).font(.subheadline).foregroundStyle(.secondary)
                if !notes.isEmpty {
                    Text(notes.prefix(4).joined(separator: " · ")).font(.caption).foregroundStyle(Brand.olive)
                }
            }
            .padding([.horizontal, .bottom], 14)
        }
        .frame(width: 280)
        .background(Brand.background)
    }

    private func toggle(_ flag: Flag) async {
        do {
            try await auth.withToken { token in
                // With unknown flags the menu offered "add", so it only ever adds.
                let known = current
                let now: RemoteCollectionFlags
                if let known { now = known } else { now = try await client.fetchCollectionFlags(slug: slug, accessToken: token) }
                let turningOn = known.map { !Self.value(flag, in: $0) } ?? true
                let next = RemoteCollectionFlags(
                    owned: now.owned,
                    favorite: flag == .favorite ? turningOn : now.favorite,
                    wantsToTry: flag == .wantsToTry ? turningOn : now.wantsToTry,
                    tried: flag == .tried ? turningOn : now.tried
                )
                flags = try await client.updateCollectionFlags(slug: slug, accessToken: token, owned: next.owned,
                                                               favorite: next.favorite, wantsToTry: next.wantsToTry, tried: next.tried)
                if turningOn { pop(flag) }
            }
        } catch {
            // The menu has closed either way; a failed toggle just doesn't pop.
        }
    }

    private func pop(_ flag: Flag) {
        let icon: String
        switch flag {
        case .favorite: icon = "heart.circle.fill"
        case .tried: icon = "cup.and.saucer.fill"
        case .wantsToTry: icon = "bookmark.circle.fill"
        }
        burstTick += 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { burst = icon }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.3)) { burst = nil }
        }
    }
}

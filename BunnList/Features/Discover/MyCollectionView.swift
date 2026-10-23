import BunnListCore
import SwiftUI

/// The signed-in user's whole collection (GET /api/v1/collection) — every lot they
/// marked owned / favorite / want-to-try / tried, in one place. Rows push the lot detail.
struct MyCollectionView: View {
    enum Phase: Equatable {
        case loading
        case loaded([RemoteCollectionItem])
        case failed(String)
    }

    @EnvironmentObject private var auth: AuthModel
    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("جارٍ الجلب…")
            case let .failed(message):
                ContentUnavailableView {
                    Label("تعذّر الجلب", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("إعادة المحاولة") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
            case let .loaded(items):
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("مجموعتك فارغة", systemImage: "square.stack.3d.up")
                    } description: {
                        Text("علّم المحاصيل بـ «لديّ» أو «مفضّل» من صفحة المحصول، وتظهر هنا.")
                    }
                } else {
                    List(items) { item in
                        NavigationLink(value: item.slug) { CollectionItemRow(item: item) }
                    }
                }
            }
        }
        .navigationTitle("مجموعتي")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard auth.isSignedIn, let token = auth.currentAccessToken() else {
            phase = .failed("سجّل الدخول لعرض مجموعتك.")
            return
        }
        phase = .loading
        let client = CatalogAPIClient(transport: URLSessionTransport())
        do {
            phase = .loaded(try await client.fetchCollection(accessToken: token))
        } catch APIError.unauthorized {
            if let fresh = await auth.refreshAccessToken(), let items = try? await client.fetchCollection(accessToken: fresh) {
                phase = .loaded(items)
            } else {
                phase = .failed("انتهت الجلسة. سجّل الدخول من جديد.")
            }
        } catch {
            phase = .failed("تعذّر جلب مجموعتك. تحقّق من اتصالك ثم أعد المحاولة.")
        }
    }
}

private struct CollectionItemRow: View {
    let item: RemoteCollectionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.nameAr).font(.headline)
            Text(item.roasterNameAr).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if item.owned { flag("لديّ", "checkmark.circle.fill") }
                if item.favorite { flag("مفضّل", "heart.fill") }
                if item.wantsToTry { flag("ودّي أجرّب", "bookmark.fill") }
                if item.tried { flag("جرّبته", "cup.and.saucer.fill") }
            }
        }
        .padding(.vertical, 2)
    }

    private func flag(_ label: String, _ icon: String) -> some View {
        Label(label, systemImage: icon).font(.caption).foregroundStyle(Brand.olive)
    }
}

import BunnListCore
import SwiftUI

/// "اقتراحاتي": the user's coffee suggestions and where each stands. Approved ones
/// open the published coffee, where the user is credited as its discoverer.
@MainActor
struct MySubmissionsView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var items: [RemoteMySubmission]?
    @State private var failed = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        List {
            if let items {
                if items.isEmpty {
                    ContentUnavailableView("ما اقترحت قهوة بعد", systemImage: "sparkles",
                                           description: Text("امسح كيس قهوة من تبويب «مسح» واقترحها، وإذا انقبلت يظهر اسمك كمكتشف لها."))
                }
                ForEach(items) { item in
                    if let slug = item.lotSlug {
                        NavigationLink { LiveLotDetailView(slug: slug) } label: { row(item) }
                    } else {
                        row(item)
                    }
                }
            } else if failed {
                ContentUnavailableView("تعذّر التحميل", systemImage: "wifi.exclamationmark")
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .brandScreen()
        .navigationTitle("اقتراحاتي")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ item: RemoteMySubmission) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.name).font(.headline)
                Spacer()
                statusBadge(item.status)
            }
            Text(item.roasterName).font(.subheadline).foregroundStyle(.secondary)
            if item.status == "REJECTED", let note = item.reviewNote, !note.isEmpty {
                Text("السبب: \(note)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let (text, color): (String, Color) = switch status {
        case "APPROVED": ("انقبلت ⭐", Brand.olive)
        case "REJECTED": ("مرفوضة", .red)
        default: ("تحت المراجعة", .orange)
        }
        return Text(text).font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func load() async {
        failed = false
        do {
            items = try await auth.withToken { try await client.fetchMySubmissions(accessToken: $0) }
        } catch {
            failed = true
        }
    }
}

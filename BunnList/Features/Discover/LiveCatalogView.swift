import BunnListCore
import SwiftUI

/// Read-only list of coffee lots fetched live from the server (GET /api/v1/catalog/lots).
/// Separate from the on-device demo catalog; shows whatever has been published server-side.
@MainActor
final class LiveCatalogModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded([RemoteLot])
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    private let client: CatalogAPIClient

    init(client: CatalogAPIClient = CatalogAPIClient(transport: URLSessionTransport())) {
        self.client = client
    }

    func load() async {
        phase = .loading
        do {
            phase = .loaded(try await client.fetchLots())
        } catch {
            phase = .failed("تعذّر جلب المحاصيل. تحقّق من اتصالك ثم أعد المحاولة.")
        }
    }
}

struct LiveCatalogView: View {
    @StateObject private var model = LiveCatalogModel()
    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var showMyCollection = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView("جارٍ الجلب…")
                case let .failed(message):
                    ContentUnavailableView {
                        Label("تعذّر الجلب", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("إعادة المحاولة") { Task { await model.load() } }
                            .buttonStyle(.borderedProminent)
                    }
                case let .loaded(lots):
                    if lots.isEmpty {
                        ContentUnavailableView {
                            Label("لا محاصيل منشورة بعد", systemImage: "cup.and.saucer")
                        } description: {
                            Text("لم تُنشر محاصيل على الخادم بعد. تُضاف لاحقًا من لوحة الموقع، وتظهر هنا تلقائيًا.")
                        }
                    } else {
                        List(lots) { lot in
                            NavigationLink(value: lot.slug) { LiveLotRow(lot: lot) }
                                .accessibilityIdentifier("live-lot-\(lot.slug)")
                        }
                    }
                }
            }
            .navigationTitle("محاصيل مباشرة")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { LiveLotDetailView(slug: $0) }
            .navigationDestination(isPresented: $showMyCollection) { MyCollectionView() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
                if auth.isSignedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showMyCollection = true } label: { Label("مجموعتي", systemImage: "square.stack.3d.up") }
                            .accessibilityIdentifier("open-my-collection")
                    }
                }
            }
        }
        .task { await model.load() }
    }
}

struct LiveLotRow: View {
    let lot: RemoteLot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(lot.nameAr).font(.headline)
                Text(lot.roasterNameAr).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if let origin = lot.originNameAr { Label(origin, systemImage: "globe").labelStyle(.titleAndIcon) }
                    if let process = lot.processLabel { Text("· \(process)") }
                }
                .font(.caption).foregroundStyle(.secondary)
                if lot.reviewCount > 0 {
                    Label("\(lot.averageRating.formatted(.number.precision(.fractionLength(1)))) · \(lot.reviewCount) تقييم",
                          systemImage: "star.fill")
                        .font(.caption).foregroundStyle(Brand.olive)
                }
                if !lot.flavorNotes.isEmpty {
                    Text(lot.flavorNotes.prefix(3).joined(separator: " • "))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let urlString = lot.imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.1)
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Brand.olive.opacity(0.12))
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: "cup.and.saucer.fill").foregroundStyle(Brand.olive))
        }
    }
}

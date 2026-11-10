import BunnListCore
import SwiftUI

/// «تحميلات الموقع»: taps on the site's download buttons, by platform, by button and by day.
@MainActor
struct AdminSiteClicksView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var days = 30
    @State private var clicks: RemoteSiteClicks?
    @State private var failed = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        List {
            Section {
                Picker("المدة", selection: $days) {
                    Text("٧ أيام").tag(7)
                    Text("٣٠ يوم").tag(30)
                    Text("٩٠ يوم").tag(90)
                }
                .pickerStyle(.segmented)
            }
            if let clicks {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clicks.total.formatted()).font(.system(size: 44, weight: .bold)).foregroundStyle(Brand.olive).monospacedDigit()
                        Text("ضغطة على أزرار التحميل").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("الضغطة مو تحميل مؤكد: هي كم واحد ضغط الزر وراح للمتجر. زيارات محركات البحث ما تنحسب.")
                }
                if clicks.total == 0 {
                    Section { Text("ما فيه ضغطات في هالمدة.").foregroundStyle(.secondary) }
                } else {
                    breakdown("حسب الجهاز", clicks.byPlatform, total: clicks.total, name: RemoteSiteClicks.platformAr)
                    breakdown("حسب الزر", clicks.bySource, total: clicks.total, name: RemoteSiteClicks.sourceAr)
                    Section("حسب اليوم") {
                        let peak = max(clicks.byDay.map(\.count).max() ?? 1, 1)
                        ForEach(clicks.byDay.reversed()) { d in
                            row(d.day, d.count, share: Double(d.count) / Double(peak), ltr: true)
                        }
                    }
                }
            } else if failed {
                Section { Label("تعذّر التحميل. اسحب للتحديث.", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
            } else {
                Section { LoadingRows(rows: 4) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background.ignoresSafeArea())
        .navigationTitle("تحميلات الموقع")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: days) { await load() }
        .refreshable { await load() }
    }

    private func breakdown(_ title: String, _ counts: [String: Int], total: Int, name: @escaping (String) -> String) -> some View {
        Section(title) {
            ForEach(RemoteSiteClicks.sorted(counts), id: \.key) { item in
                row(name(item.key), item.count, share: Double(item.count) / Double(max(total, 1)), ltr: false)
            }
        }
    }

    private func row(_ title: String, _ count: Int, share: Double, ltr: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline).environment(\.layoutDirection, ltr ? .leftToRight : .rightToLeft)
                Spacer()
                Text(count.formatted()).font(.subheadline.bold()).monospacedDigit()
            }
            GeometryReader { geo in
                Capsule().fill(Brand.olive.opacity(0.18))
                    .overlay(alignment: .leading) { Capsule().fill(Brand.olive).frame(width: max(4, geo.size.width * share)) }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        failed = false
        do { clicks = try await auth.withToken { try await client.adminSiteClicks(days: days, accessToken: $0) } }
        catch { failed = true }
    }
}

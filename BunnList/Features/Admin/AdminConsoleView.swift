import BunnListCore
import Charts
import SwiftUI

/// The admin console's home: what needs attention, the week in numbers, 30 days
/// of activity, and the way into review, coffees and reports.
@MainActor
struct AdminConsoleView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var overview: RemoteAdminOverview?
    @State private var failed = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                attention
                if let o = overview {
                    stats(o)
                    chart(o)
                } else if failed {
                    Label("ما قدرنا نجيب الأرقام. اسحب للتحديث.", systemImage: "wifi.slash").foregroundStyle(.secondary)
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 40)
                }
                sections
            }
            .padding()
        }
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("لوحة التحكم")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            overview = try await auth.withToken { try await client.adminOverview(accessToken: $0) }
            failed = false
        } catch {
            failed = overview == nil
        }
    }

    // MARK: Needs attention

    @ViewBuilder
    private var attention: some View {
        let pending = overview?.pendingSubmissions ?? 0
        let reports = overview?.openReports ?? 0
        if pending > 0 || reports > 0 {
            VStack(spacing: 8) {
                if reports > 0 {
                    NavigationLink { AdminReportsView() } label: {
                        alert("\(reports.formatted()) بلاغ مفتوح", icon: "flag.fill", color: .red)
                    }
                }
                if pending > 0 {
                    NavigationLink { AdminReviewView() } label: {
                        alert("\(pending.formatted()) اقتراح ينتظر المراجعة", icon: "tray.full.fill", color: Brand.gold)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func alert(_ text: String, icon: String, color: Color) -> some View {
        HStack {
            Label(text, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Spacer()
            Image(systemName: "chevron.backward").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Numbers

    private func stats(_ o: RemoteAdminOverview) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile(o.users, "مستخدم", sub: "+\(o.newUsers7d.formatted()) هالأسبوع", icon: "person.2.fill", color: Brand.olive)
            tile(o.activeToday, "نشط اليوم", icon: "bolt.fill", color: Brand.gold)
            tile(o.lots, "قهوة منشورة", icon: "cup.and.saucer.fill", color: Brand.brown)
            tile(o.reviews7d, "تقييم", sub: "آخر ٧ أيام", icon: "star.fill", color: Brand.gold)
            tile(o.recipes7d, "وصفة", sub: "آخر ٧ أيام", icon: "book.closed.fill", color: Brand.olive)
            tile(o.brews7d, "تحضير", sub: "آخر ٧ أيام", icon: "drop.fill", color: Brand.brown)
            tile(o.scans7d, "مسح كيس", sub: "آخر ٧ أيام", icon: "camera.viewfinder", color: Brand.ink)
        }
    }

    private func tile(_ value: Int, _ label: String, sub: String? = nil, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(value.formatted()).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let sub { Text(sub).font(.system(size: 10)).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func chart(_ o: RemoteAdminOverview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("آخر ٣٠ يوم").font(.headline)
            Chart(o.series) { d in
                BarMark(x: .value("اليوم", d.day), y: .value("نشطين", d.active))
                    .foregroundStyle(Brand.olive.gradient)
                if d.newUsers > 0 {
                    PointMark(x: .value("اليوم", d.day), y: .value("جدد", d.newUsers))
                        .foregroundStyle(Brand.gold)
                        .symbolSize(30)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 140)
            .environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 14) {
                Label("حسابات نشطة", systemImage: "square.fill").foregroundStyle(Brand.olive)
                Label("مستخدمين جدد", systemImage: "circle.fill").foregroundStyle(Brand.gold)
            }
            .font(.caption2)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Sections

    private var sections: some View {
        VStack(spacing: 10) {
            NavigationLink { AdminReviewView() } label: {
                row("مراجعة الاقتراحات", detail: "القبول والرفض والاستيراد", icon: "checkmark.shield.fill", count: overview?.pendingSubmissions)
            }
            NavigationLink { AdminLotsView() } label: {
                row("القهوات", detail: "تعديل، إخفاء، تغيير الصورة", icon: "cup.and.saucer.fill", count: nil)
            }
            NavigationLink { AdminReportsView() } label: {
                row("البلاغات", detail: "التقييمات والوصفات والحسابات", icon: "flag.fill", count: overview?.openReports)
            }
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, detail: String, icon: String, count: Int?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Brand.background)
                .frame(width: 44, height: 44)
                .background(Brand.olive, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let count, count > 0 {
                Text(count.formatted()).font(.caption.bold().monospacedDigit()).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.red))
            }
            Image(systemName: "chevron.backward").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

import BunnListCore
import Charts
import SwiftUI

/// The admin console's home, top to bottom by urgency: what waits on you, how the
/// app is doing this week against last, 30 days of activity, the catalog's gaps,
/// then every tool grouped by what it's for.
@MainActor
struct AdminConsoleView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var overview: RemoteAdminOverview?
    @State private var counts: RemoteQueueCounts?
    @State private var failed = false
    @State private var metric = Metric.active
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    enum Metric: String, CaseIterable, Identifiable {
        case active, newUsers, brews
        var id: String { rawValue }
        var titleAr: String {
            switch self {
            case .active: return "نشطين"
            case .newUsers: return "جدد"
            case .brews: return "تحضيرات"
            }
        }
        func value(_ day: RemoteAdminOverview.Day) -> Int {
            switch self {
            case .active: return day.active
            case .newUsers: return day.newUsers
            case .brews: return day.brews ?? 0
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                attention
                if let o = overview {
                    pulse(o)
                    chart(o)
                } else if failed {
                    Label("ما قدرنا نجيب الأرقام. اسحب للتحديث.", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    VStack(spacing: 10) {
                        SkeletonBlock(height: 96, corner: 18)
                        SkeletonBlock(height: 180, corner: 18)
                    }
                }
                catalog
                tools
            }
            .padding()
        }
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("لوحة التحكم")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        // Again on every return, so finished work comes off the counts.
        .onAppear { Task { await load() } }
    }

    private func load() async {
        if let o = try? await auth.withToken({ try await client.adminOverview(accessToken: $0) }) { overview = o }
        failed = overview == nil
        if let q = try? await auth.withToken({ try await client.queueCounts(accessToken: $0) }) { counts = q }
    }

    // MARK: Header

    private var waiting: Int? { overview?.waiting }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.caption.bold()).foregroundStyle(Brand.background.opacity(0.7))
            Text(headline).font(.title2.bold()).foregroundStyle(Brand.background)
            if let o = overview {
                HStack(spacing: 18) {
                    headerFigure(o.users, "مستخدم")
                    headerFigure(o.lots, "قهوة منشورة")
                    headerFigure(o.activeToday, "نشط اليوم")
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Brand.ink, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        guard let waiting else { return "لوحة التحكم" }
        switch waiting {
        case 0: return "كل شي تمام، ما فيه شي ينتظرك"
        case 1: return "شي واحد ينتظرك"
        case 2: return "شيئين ينتظرونك"
        default: return "\(waiting.formatted()) أشياء تنتظرك"
        }
    }

    private func headerFigure(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value.formatted()).font(.title3.bold().monospacedDigit()).foregroundStyle(Brand.background)
            Text(label).font(.caption2).foregroundStyle(Brand.background.opacity(0.7))
        }
    }

    // MARK: Needs attention

    private var attention: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("يحتاج انتباهك")
            HStack(spacing: 10) {
                NavigationLink { RoasterQueueView(kind: .pending) } label: {
                    attentionCard(overview?.pendingSubmissions ?? counts?.pending, "اقتراحات", icon: "tray.and.arrow.down.fill")
                }
                NavigationLink { AdminReportsView() } label: {
                    attentionCard(overview?.openReports ?? counts?.reports, "بلاغات", icon: "flag.fill")
                }
                NavigationLink { AdminFeedbackView() } label: {
                    attentionCard(overview?.unreadFeedback, "رسائل الناس", icon: "envelope.fill")
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func attentionCard(_ count: Int?, _ title: String, icon: String) -> some View {
        let hot = (count ?? 0) > 0
        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.subheadline)
                .foregroundStyle(hot ? Brand.background : Brand.olive)
                .frame(height: 20)
            Text(count.map { $0.formatted() } ?? "—")
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(hot ? Brand.background : Brand.ink)
            Text(title).font(.caption.bold())
                .foregroundStyle(hot ? Brand.background.opacity(0.85) : .secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(14)
        .background(hot ? Brand.gold : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(count.map { $0.formatted() } ?? "غير معروف")")
    }

    // MARK: This week

    private func pulse(_ o: RemoteAdminOverview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("هالأسبوع")
                Spacer()
                if comparable(o) { Text("مقارنة بالأسبوع اللي قبله").font(.caption2).foregroundStyle(.secondary) }
            }
            if let active = o.active7d {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Brand.olive.opacity(0.15), lineWidth: 8)
                        Circle().trim(from: 0, to: CGFloat(min(AdminTrend.share(active, of: o.users), 100)) / 100)
                            .stroke(Brand.olive, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(AdminTrend.share(active, of: o.users))٪").font(.subheadline.bold().monospacedDigit())
                    }
                    .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(active.formatted()) من \(o.users.formatted()) فتحوا التطبيق").font(.subheadline.bold())
                        Text(o.brewers7d.map { "\($0.formatted()) منهم سجّلوا تحضيرة" } ?? "خلال آخر ٧ أيام")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityElement(children: .combine)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                kpi(o.newUsers7d, "مستخدم جديد", previous: o.prev7d?.newUsers, icon: "person.badge.plus")
                kpi(o.brews7d, "تحضيرة", previous: o.prev7d?.brews, icon: "drop.fill")
                kpi(o.reviews7d, "تقييم", previous: o.prev7d?.reviews, icon: "star.fill")
                kpi(o.recipes7d, "وصفة منشورة", previous: o.prev7d?.recipes, icon: "book.closed.fill")
                kpi(o.scans7d, "مسح كيس", previous: o.prev7d?.scans, icon: "camera.viewfinder")
                if let brewers = o.brewers7d { kpi(brewers, "شخص حضّر", previous: nil, icon: "person.fill.checkmark") }
            }
        }
    }

    /// Last week had something to compare with (a brand-new app has nothing yet).
    private func comparable(_ o: RemoteAdminOverview) -> Bool {
        guard let p = o.prev7d else { return false }
        return p.newUsers + p.reviews + p.recipes + p.brews + p.scans > 0
    }

    private func kpi(_ value: Int, _ label: String, previous: Int?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).font(.caption).foregroundStyle(Brand.olive)
                Spacer()
                trend(current: value, previous: previous)
            }
            Text(value.formatted()).font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    /// ▲ 20٪ in olive, ▼ in red; nothing when last week had none to compare with.
    @ViewBuilder
    private func trend(current: Int, previous: Int?) -> some View {
        if let percent = AdminTrend.percent(current: current, previous: previous) {
            let up = percent >= 0
            Label("\(abs(percent).formatted())٪", systemImage: percent == 0 ? "equal" : (up ? "arrow.up" : "arrow.down"))
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(percent == 0 ? Color.secondary : (up ? Brand.olive : .red))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background((percent == 0 ? Color.secondary : (up ? Brand.olive : .red)).opacity(0.12), in: Capsule())
                .accessibilityLabel(percent == 0 ? "بدون تغيير" : "\(up ? "زاد" : "نقص") \(abs(percent)) بالمية")
        }
    }

    // MARK: 30 days

    private func chart(_ o: RemoteAdminOverview) -> some View {
        let values = o.series.map { metric.value($0) }
        let hasBrews = o.series.contains { $0.brews != nil }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("آخر ٣٠ يوم").font(.headline)
                Spacer()
                Text(metric == .active ? "أعلى يوم \((values.max() ?? 0).formatted())" : "المجموع \(values.reduce(0, +).formatted())")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Picker("المقياس", selection: $metric) {
                ForEach(Metric.allCases.filter { $0 != .brews || hasBrews }) { Text($0.titleAr).tag($0) }
            }
            .pickerStyle(.segmented)
            Chart(o.series) { day in
                AreaMark(x: .value("اليوم", day.day), y: .value(metric.titleAr, metric.value(day)))
                    .foregroundStyle(LinearGradient(colors: [Brand.olive.opacity(0.35), Brand.olive.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("اليوم", day.day), y: .value(metric.titleAr, metric.value(day)))
                    .foregroundStyle(Brand.olive)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .frame(height: 150)
            .environment(\.layoutDirection, .leftToRight)
            .animation(.easeInOut(duration: 0.3), value: metric)
            HStack {
                Text(shortDay(o.series.first?.day))
                Spacer()
                Text("اليوم")
            }
            .font(.caption2).foregroundStyle(.tertiary)
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    /// "2026-11-02" → "11/02".
    private func shortDay(_ day: String?) -> String {
        guard let parts = day?.split(separator: "-"), parts.count == 3 else { return "" }
        return "\(parts[1])/\(parts[2])"
    }

    // MARK: Catalog quality

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("جودة الكتالوج")
            group {
                NavigationLink { RoasterQueueView(kind: .incomplete) } label: {
                    row("قهاوي ناقصة معلومات", detail: counts.map {
                        "منشأ \($0.noOrigin.formatted()) · معالجة \($0.noProcess.formatted()) · نكهات \($0.noNotes.formatted())"
                    } ?? "المنشأ والمعالجة والنكهات", icon: "exclamationmark.circle.fill", tint: .red, count: counts?.incomplete)
                }
                divider
                NavigationLink { AdminLotsView(startFilter: .noPhoto) } label: {
                    row("قهاوي بدون صورة", detail: "أضف صورة الكيس", icon: "photo.badge.plus", tint: Brand.gold, count: counts?.noPhoto)
                }
                divider
                NavigationLink { RoasterQueueView(kind: .photos) } label: {
                    row("مراجعة الصور", detail: "شيل الخلفية، قص، رجّع الأصل", icon: "photo.on.rectangle.angled", tint: Brand.olive, count: nil)
                }
                divider
                NavigationLink { DuplicatesView() } label: {
                    row("قهاوي مكررة", detail: "نفس القهوة منشورة مرتين: اختر وحدة وادمج", icon: "square.on.square", tint: Brand.brown, count: nil)
                }
            }
        }
    }

    // MARK: Tools

    private var tools: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("المحتوى")
                group {
                    NavigationLink { AdminReviewView() } label: {
                        row("الاقتراحات والاستيراد", detail: "القائمة الكاملة، التحديد الجماعي، استيراد المحامص", icon: "checkmark.shield.fill", tint: Brand.olive, count: nil)
                    }
                    divider
                    NavigationLink { AdminLotsView() } label: {
                        row("القهوات", detail: "تعديل، إخفاء، تغيير الصورة", icon: "cup.and.saucer.fill", tint: Brand.brown, count: nil)
                    }
                    divider
                    NavigationLink { AdminGrindersView() } label: {
                        row("دليل المطاحن", detail: "المواصفات ومصادرها والصور", icon: "dial.medium.fill", tint: Brand.ink, count: nil)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("الناس")
                group {
                    NavigationLink { AdminUsersView() } label: {
                        row("المستخدمين", detail: "البحث، الإيقاف، الأدمن، شارة المؤسس", icon: "person.2.fill", tint: Brand.olive, count: nil)
                    }
                    divider
                    NavigationLink { AdminChallengesView() } label: {
                        row("تحدي الأسبوع", detail: "تحدي جديد، المدة، النقاط", icon: "flag.checkered", tint: Brand.gold, count: nil)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("التواصل")
                group {
                    NavigationLink { AdminBroadcastView() } label: {
                        row("الإشعارات", detail: "أرسل الآن، أو رسائل متكررة كل كم يوم", icon: "megaphone.fill", tint: Brand.gold, count: nil)
                    }
                    divider
                    NavigationLink { AdminUpdatesView() } label: {
                        row("تحديثات BunnList", detail: "انشر خبر أو ميزة، والناس يعلّقون تحته", icon: "text.bubble.fill", tint: Brand.olive, count: nil)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("النمو")
                group {
                    NavigationLink { AdminSiteClicksView() } label: {
                        row("تحميلات الموقع", detail: "ضغطات أزرار التحميل حسب الجهاز واليوم", icon: "arrow.down.circle.fill", tint: Brand.brown, count: nil)
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.title3.bold())
    }

    /// One rounded card holding a list of rows.
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .buttonStyle(.plain)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var divider: some View {
        Divider().padding(.leading, 60)
    }

    private func row(_ title: String, detail: String, icon: String, tint: Color, count: Int?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.subheadline.bold()).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let count {
                Text(count.formatted()).font(.caption.bold().monospacedDigit())
                    .foregroundStyle(count > 0 ? Color.white : Color.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(count > 0 ? AnyShapeStyle(tint) : AnyShapeStyle(Color.secondary.opacity(0.12)), in: Capsule())
            }
            Image(systemName: "chevron.backward").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

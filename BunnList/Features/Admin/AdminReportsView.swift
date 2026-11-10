import BunnListCore
import SwiftUI

/// Reports from people: the content, who reported it and why. "إزالة" hides the
/// content (the review, recipe, note or profile text); "إبقاء" keeps it. Either
/// closes every open report on the same thing.
@MainActor
struct AdminReportsView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var closed = false
    @State private var reports: [RemoteAdminReport]?
    @State private var failed = false
    @State private var busy: String?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Picker("الحالة", selection: $closed) {
                    Text("مفتوحة").tag(false)
                    Text("منتهية").tag(true)
                }
                .pickerStyle(.segmented)
                if let reports {
                    if reports.isEmpty {
                        ContentUnavailableView(closed ? "ما فيه بلاغات منتهية" : "ما فيه بلاغات تنتظرك", systemImage: "checkmark.shield",
                                               description: Text(closed ? "" : "أي بلاغ جديد يطلع لك هنا وفي أول لوحة التحكم."))
                            .padding(.top, 40)
                    } else {
                        Text("\(reports.count.formatted()) \(closed ? "منتهية" : "تنتظر قرارك")")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(reports) { report in
                            card(report)
                                .padding(14)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                } else if failed {
                    Label("ما قدرنا نجيب البلاغات. اسحب للتحديث.", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 150, corner: 18) }
                }
            }
            .padding()
        }
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("البلاغات")
        .task(id: closed) { reports = nil; await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            reports = try await auth.withToken { try await client.adminReports(closed: closed, accessToken: $0) }
            failed = false
        } catch {
            failed = reports == nil
        }
    }

    private func card(_ r: RemoteAdminReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(ReportReason.nameAr(r.reason), systemImage: "flag.fill").font(.subheadline.bold()).foregroundStyle(.red)
                Spacer()
                if r.sameTargetCount > 1 {
                    Text("\(r.sameTargetCount.formatted()) بلاغات").font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(.red.opacity(0.12)))
                }
            }
            Text(r.title).font(.subheadline.weight(.semibold))
            if let owner = r.ownerName { Text("صاحبه: \(owner)").font(.caption).foregroundStyle(.secondary) }
            if let text = r.text, !text.isEmpty {
                Text(text).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            }
            if let details = r.details, !details.isEmpty {
                Text("«\(details)»").font(.caption).foregroundStyle(.secondary)
            }
            Text("بلّغ: \(r.reporterName ?? "—")").font(.caption2).foregroundStyle(.tertiary)
            if r.status == "open" {
                HStack {
                    Button { Task { await resolve(r, remove: false) } } label: {
                        Label("إبقاء", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(Brand.olive)
                    Button(role: .destructive) { Task { await resolve(r, remove: true) } } label: {
                        Label("إزالة", systemImage: "eye.slash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .disabled(busy != nil)
            } else {
                Label(r.status == "removed" ? "انزال" : "انترك", systemImage: r.status == "removed" ? "eye.slash" : "checkmark")
                    .font(.caption.bold()).foregroundStyle(r.status == "removed" ? .red : Brand.olive)
            }
        }
    }

    private func resolve(_ r: RemoteAdminReport, remove: Bool) async {
        busy = r.id
        defer { busy = nil }
        do {
            try await auth.withToken { try await client.resolveReport(id: r.id, remove: remove, accessToken: $0) }
            await load()
        } catch {
            failed = false
        }
    }
}

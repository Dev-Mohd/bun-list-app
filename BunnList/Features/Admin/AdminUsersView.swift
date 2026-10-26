import BunnListCore
import SwiftUI

/// The newest accounts, or a search by @username, name or email.
@MainActor
struct AdminUsersView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var query = ""
    @State private var users: [RemoteAdminUserRow]?
    @State private var failed = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        List {
            if let users {
                if users.isEmpty { ContentUnavailableView("ما فيه نتائج", systemImage: "person.slash") }
                ForEach(users) { user in
                    NavigationLink { AdminUserDetailView(accountID: user.accountId) { Task { await load() } } } label: {
                        HStack(spacing: 12) {
                            AvatarView(url: user.avatarUrl, name: user.shownName, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.shownName).font(.subheadline.bold()).lineLimit(1)
                                if let username = user.username, user.displayName != nil {
                                    Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if user.isAdmin { badge("أدمن", Brand.olive) }
                            if user.suspended { badge("موقوف", .red) }
                        }
                    }
                }
            } else if failed {
                Label("ما قدرنا نجيب المستخدمين", systemImage: "wifi.slash").foregroundStyle(.secondary)
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("المستخدمين")
        .searchable(text: $query, prompt: "@اسم المستخدم أو الاسم أو الإيميل")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await load()
        }
        .refreshable { await load() }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.bold()).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func load() async {
        do {
            users = try await auth.withToken { try await client.adminUsers(query: query, accessToken: $0) }
            failed = false
        } catch {
            failed = users == nil
        }
    }
}

/// One account: who they are, what they've done, and the admin actions.
@MainActor
struct AdminUserDetailView: View {
    let accountID: String
    var onChange: () -> Void = {}

    @EnvironmentObject private var auth: AuthModel
    @State private var user: RemoteAdminUser?
    @State private var message: String?
    @State private var showSuspend = false
    @State private var confirmAdmin = false
    @State private var isBusy = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        Group {
            if let user { content(user) } else if message != nil {
                ContentUnavailableView("تعذّر التحميل", systemImage: "exclamationmark.triangle")
            } else { ProgressView() }
        }
        .brandScreen()
        .navigationTitle(user.map { $0.username.map { "@" + $0 } ?? "حساب" } ?? "حساب")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showSuspend) {
            SuspendSheet { reason, days in Task { await act(.suspend(reason: reason, days: days)) } }
        }
    }

    private func load() async {
        do { user = try await auth.withToken { try await client.adminUser(id: accountID, accessToken: $0) } }
        catch { message = "تعذّر التحميل" }
    }

    private func act(_ action: AdminUserAction) async {
        isBusy = true
        defer { isBusy = false }
        do {
            user = try await auth.withToken { try await client.adminUserAction(id: accountID, action, accessToken: $0) }
            message = nil
            onChange()
        } catch APIError.unprocessable {
            message = "ما ينفع هالإجراء على هذا الحساب (حسابك أنت، أو أدمن)."
        } catch {
            message = "ما تم الإجراء. حاول مرة ثانية."
        }
    }

    private func content(_ u: RemoteAdminUser) -> some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AvatarView(url: u.avatarUrl, name: u.displayName ?? u.username ?? "؟", size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(u.displayName ?? "بدون اسم").font(.headline)
                        if let username = u.username { Text("@\(username)").font(.subheadline).foregroundStyle(.secondary) }
                        if let email = u.email { Text(email).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                }
                if let bio = u.bio, !bio.isEmpty { Text(bio).font(.callout) }
                LabeledContent("انضم", value: Self.date(u.joinedAt))
                LabeledContent("آخر نشاط", value: u.lastActiveDay ?? "—")
                LabeledContent("النقاط", value: u.points.formatted())
                if let username = u.username {
                    NavigationLink("صفحته العامة") { PublicProfileView(username: username) }
                }
            }

            if let s = u.suspension {
                Section("موقوف عن النشر") {
                    Text(s.reason)
                    LabeledContent("لين", value: s.until.map(Self.date) ?? "ما يرفع إلا يدويًا")
                }
            }

            Section("نشاطه") {
                LabeledContent("تقييمات", value: u.counts.reviews.formatted())
                LabeledContent("وصفات منشورة", value: u.counts.recipes.formatted())
                LabeledContent("تحضيرات", value: u.counts.brews.formatted())
                LabeledContent("اكتشافات", value: u.counts.discoveries.formatted())
                LabeledContent("متابِعون / يتابع", value: "\(u.counts.followers.formatted()) / \(u.counts.following.formatted())")
                if u.counts.reports > 0 {
                    LabeledContent("بلاغات على حسابه", value: u.counts.reports.formatted()).foregroundStyle(.red)
                }
            }

            if !u.recentReviews.isEmpty {
                Section("آخر تقييماته") {
                    ForEach(u.recentReviews, id: \.self) { r in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(r.lotNameAr).font(.subheadline.bold())
                                Spacer()
                                Text("\(r.rating)/5").font(.caption.monospacedDigit())
                                if r.status != "PUBLISHED" {
                                    Image(systemName: "eye.slash").font(.caption).foregroundStyle(.red)
                                }
                            }
                            if let body = r.body, !body.isEmpty { Text(body).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }

            if let message {
                Section { Label(message, systemImage: "info.circle").foregroundStyle(.red) }
            }

            Section("إجراءات") {
                if u.suspended {
                    Button("رفع الإيقاف") { Task { await act(.unsuspend) } }.tint(Brand.olive)
                } else if !u.isAdmin {
                    Button("إيقاف عن النشر…", role: .destructive) { showSuspend = true }
                }
                Button(u.isAdmin ? "سحب صلاحية الأدمن" : "إعطاء صلاحية أدمن") { confirmAdmin = true }
                    .confirmationDialog(u.isAdmin ? "تسحب صلاحية الأدمن؟" : "تعطيه صلاحية أدمن؟", isPresented: $confirmAdmin,
                                        titleVisibility: .visible) {
                        Button(u.isAdmin ? "سحب" : "إعطاء", role: u.isAdmin ? .destructive : nil) {
                            Task { await act(.setAdmin(!u.isAdmin)) }
                        }
                    } message: {
                        Text(u.isAdmin ? "ما يقدر يدخل لوحة التحكم بعدها." : "يقدر يراجع ويعدّل القهوات ويوقف الحسابات ويرسل إشعارات للكل.")
                    }
            }
            .disabled(isBusy)
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background.ignoresSafeArea())
        .refreshable { await load() }
    }

    static func date(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}

/// Reason and length for "إيقاف عن النشر".
private struct SuspendSheet: View {
    var onSuspend: (String, Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var days: Int? = 7

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("السبب (ما يشوفه إلا الأدمن)", text: $reason, axis: .vertical).lineLimit(2...4)
                }
                Section("المدة") {
                    Picker("المدة", selection: $days) {
                        Text("يوم").tag(Optional(1))
                        Text("أسبوع").tag(Optional(7))
                        Text("شهر").tag(Optional(30))
                        Text("لين أرفعه").tag(Int?.none)
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
                Section {
                    Text("يقدر يتصفح التطبيق عادي، بس ما يقدر ينشر تقييمات أو وصفات أو اقتراحات أو يعدّل ملفه.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("إيقاف عن النشر")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إيقاف", role: .destructive) {
                        onSuspend(reason.trimmingCharacters(in: .whitespacesAndNewlines), days)
                        dismiss()
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

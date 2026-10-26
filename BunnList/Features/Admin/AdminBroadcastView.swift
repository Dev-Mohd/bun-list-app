import BunnListCore
import SwiftUI

/// Push a notification to everyone, to recent users, or to your own phone first.
/// People who turned off "أخبار التطبيق" don't get it.
@MainActor
struct AdminBroadcastView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var title = ""
    @State private var message = ""
    @State private var audience: BroadcastAudience = .test
    @State private var info: RemoteBroadcasts?
    @State private var isSending = false
    @State private var confirm = false
    @State private var result: String?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var ready: Bool {
        title.trimmingCharacters(in: .whitespaces).count >= 2 && message.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        Form {
            Section {
                TextField("العنوان", text: $title).onChange(of: title) { _, v in if v.count > 60 { title = String(v.prefix(60)) } }
                TextField("النص", text: $message, axis: .vertical).lineLimit(2...5)
                    .onChange(of: message) { _, v in if v.count > 200 { message = String(v.prefix(200)) } }
            } footer: {
                Text("\(message.count)/200")
            }

            if ready { Section("كذا بيطلع") { preview } }

            Section("لمين؟") {
                Picker("الجمهور", selection: $audience) {
                    ForEach(BroadcastAudience.allCases) { a in Text(label(a)).tag(a) }
                }
                .pickerStyle(.inline).labelsHidden()
            }

            Section {
                Button {
                    if audience == .test { Task { await send() } } else { confirm = true }
                } label: {
                    Label(isSending ? "نرسل…" : (audience == .test ? "أرسل تجربة لجوالي" : "أرسل"), systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Brand.olive)
                .disabled(!ready || isSending)
                .listRowBackground(Color.clear)
                if let result { Label(result, systemImage: "info.circle").foregroundStyle(Brand.olive) }
            }

            if let history = info?.history, !history.isEmpty {
                Section("المرسلة") {
                    ForEach(history) { h in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.title).font(.subheadline.bold())
                            Text(h.body).font(.caption).foregroundStyle(.secondary)
                            Text("\(BroadcastAudience(rawValue: h.audience)?.nameAr ?? h.audience) · وصل \(h.delivered.formatted()) جهاز · \(AdminUserDetailView.date(h.createdAt))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("إرسال إشعار")
        .task { await load() }
        .confirmationDialog("ترسل لـ\(label(audience))؟", isPresented: $confirm, titleVisibility: .visible) {
            Button("أرسل") { Task { await send() } }
        } message: {
            Text("ما تقدر تتراجع بعد الإرسال. جرّبه على جوالك أول إذا ما جربته.")
        }
    }

    private func label(_ a: BroadcastAudience) -> String {
        switch a {
        case .test: return a.nameAr
        case .active30: return info.map { "\(a.nameAr) (\($0.audiences.active30.formatted()))" } ?? a.nameAr
        case .all: return info.map { "\(a.nameAr) (\($0.audiences.all.formatted()))" } ?? a.nameAr
        }
    }

    private var preview: some View {
        HStack(alignment: .top, spacing: 10) {
            Image("IconPreview-Classic").resizable().scaledToFit().frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(message).font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func load() async {
        info = try? await auth.withToken { try await client.adminBroadcasts(accessToken: $0) }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            let r = try await auth.withToken {
                try await client.sendBroadcast(title: title, body: message, audience: audience, accessToken: $0)
            }
            result = "انرسل لـ\(r.accounts.formatted()) حساب، ووصل \(r.delivered.formatted()) جهاز"
            if audience != .test { title = ""; message = "" }
            await load()
        } catch APIError.forbidden {
            result = "الإشعارات مو مفعّلة في السيرفر (مفاتيح APNs ناقصة في Vercel)"
        } catch {
            result = "ما انرسل. حاول مرة ثانية."
        }
    }
}

import BunnListCore
import SwiftUI

/// Post «تحديثات BunnList» (optionally with a push to everyone) and remove old ones.
@MainActor
struct AdminUpdatesView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var draft = UpdateDraft()
    @State private var updates: [RemoteUpdate]?
    @State private var posting = false
    @State private var confirm = false
    @State private var result: String?
    @State private var commenting: RemoteUpdate?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        Form {
            Section {
                TextField("العنوان", text: $draft.title)
                    .onChange(of: draft.title) { _, v in if v.count > 80 { draft.title = String(v.prefix(80)) } }
                TextField("وش الجديد؟", text: $draft.body, axis: .vertical).lineLimit(3...10)
                    .onChange(of: draft.body) { _, v in if v.count > 2000 { draft.body = String(v.prefix(2000)) } }
                Toggle("أرسل إشعار للكل", isOn: $draft.notify).tint(Brand.olive)
            } header: {
                Text("تحديث جديد")
            } footer: {
                Text("يطلع في المجتمع باسم BunnList، والناس يعلّقون تحته.")
            }

            Section {
                Button {
                    if draft.notify { confirm = true } else { Task { await post() } }
                } label: {
                    Label(posting ? "ننشر…" : "انشر", systemImage: "megaphone.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Brand.olive)
                .disabled(!draft.isReady || posting)
                .listRowBackground(Color.clear)
                if let result { Label(result, systemImage: "info.circle").foregroundStyle(Brand.olive) }
            }

            if let updates, !updates.isEmpty {
                Section("المنشورة") {
                    ForEach(updates) { u in
                        Button { commenting = u } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(u.title).font(.subheadline.bold()).foregroundStyle(.primary)
                                Text(u.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text("\(u.commentCount.formatted()) تعليق · \(AdminUserDetailView.date(u.createdAt))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { Task { await remove(u) } } label: { Label("حذف", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .navigationTitle("تحديثات BunnList")
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("ننشر ونرسل إشعار لكل المستخدمين؟", isPresented: $confirm, titleVisibility: .visible) {
            Button("انشر وأرسل") { Task { await post() } }
        }
        .sheet(item: $commenting) { u in CommentsSheet(target: .update, id: u.id, title: u.title) }
    }

    private func load() async {
        updates = try? await auth.withToken { try await client.fetchUpdates(accessToken: $0) }
    }

    private func post() async {
        posting = true
        result = nil
        defer { posting = false }
        do {
            let update = try await auth.withToken { try await client.postUpdate(draft, accessToken: $0) }
            Haptics.tap()
            withAnimation { updates = [update] + (updates ?? []) }
            result = draft.notify ? "انتشر وانرسل الإشعار." : "انتشر."
            draft = UpdateDraft()
        } catch {
            result = "ما انتشر، جرّب مرة ثانية."
        }
    }

    private func remove(_ u: RemoteUpdate) async {
        do {
            try await auth.withToken { try await client.deleteUpdate(id: u.id, accessToken: $0) }
            withAnimation { updates?.removeAll { $0.id == u.id } }
        } catch {
            result = "ما انحذف، جرّب مرة ثانية."
        }
    }
}

/// Suggestions, experiences and problems from users; reply and they get a notification.
@MainActor
struct AdminFeedbackView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var showAll = false
    @State private var inbox: RemoteFeedbackInbox?
    @State private var failed = false
    @State private var replying: RemoteFeedback?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        List {
            Picker("العرض", selection: $showAll) {
                Text("بانتظار الرد").tag(false)
                Text("الكل").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            if let inbox {
                if inbox.items.isEmpty {
                    ContentUnavailableView(showAll ? "ما وصلت رسائل للحين" : "رديت على الكل 👏", systemImage: "tray")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(inbox.items) { item in
                        Button { replying = item } label: { row(item) }.buttonStyle(.plain)
                    }
                }
            } else if failed {
                Label("ما قدرنا نجيب الرسائل. اسحب للتحديث.", systemImage: "wifi.slash").foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("صندوق الاقتراحات")
        .task(id: showAll) { await load() }
        .refreshable { await load() }
        .sheet(item: $replying) { item in
            FeedbackReplySheet(item: item) { updated in
                if let i = inbox?.items.firstIndex(where: { $0.id == item.id }), let current = inbox {
                    var items = current.items
                    if showAll { items[i] = updated } else { items.remove(at: i) }
                    inbox = RemoteFeedbackInbox(items: items, open: max(current.open - 1, 0))
                }
            }
        }
    }

    private func row(_ f: RemoteFeedback) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: f.avatarUrl, name: f.name, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(f.name ?? "مستخدم").font(.subheadline.bold())
                    if let u = f.username { Text("@\(u)").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Label(f.feedbackKind.nameAr, systemImage: f.feedbackKind.symbol).font(.caption2.bold()).foregroundStyle(Brand.olive)
                }
                Text(f.body).font(.subheadline).lineLimit(4)
                HStack(spacing: 6) {
                    Text(AdminUserDetailView.date(f.createdAt)).font(.caption2).foregroundStyle(.secondary)
                    if f.isAnswered { Label("تم الرد", systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(Brand.olive) }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func load() async {
        failed = false
        do { inbox = try await auth.withToken { try await client.feedbackInbox(all: showAll, accessToken: $0) } }
        catch { if inbox == nil { failed = true } }
    }
}

@MainActor
private struct FeedbackReplySheet: View {
    let item: RemoteFeedback
    var onReplied: (RemoteFeedback) -> Void

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var reply = ""
    @State private var sending = false
    @State private var error: String?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            Form {
                Section(item.feedbackKind.nameAr) {
                    Text(item.body)
                    if let previous = item.reply {
                        LabeledContent("ردك السابق") { Text(previous).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    TextField("ردّك باسم BunnList", text: $reply, axis: .vertical).lineLimit(3...8)
                } footer: {
                    Text("يوصله إشعار ويشوف الرد في «تواصل معنا».")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(item.name ?? "رد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "نرسل…" : "أرسل") { Task { await send() } }
                        .disabled(sending || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            let updated = try await auth.withToken { try await client.replyFeedback(id: item.id, reply: text, accessToken: $0) }
            Haptics.tap()
            onReplied(updated)
            dismiss()
        } catch {
            self.error = "ما انرسل الرد، جرّب مرة ثانية."
        }
    }
}

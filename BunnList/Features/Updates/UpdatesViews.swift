import BunnListCore
import SwiftUI

// «تحديثات BunnList»: posts from the team with comments under them, and «تواصل معنا»,
// where people send a suggestion, an experience or a problem and read the team's reply.

/// The team's avatar: the BunnList symbol on cream.
struct OfficialAvatar: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(Brand.background)
            if let image = UIImage(named: "BunnListSymbol") {
                Image(uiImage: image).resizable().scaledToFit().padding(size * 0.2)
            } else {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(Brand.olive)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Brand.gold.opacity(0.6), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// «BunnList» with a seal, used wherever the team speaks.
struct OfficialName: View {
    var font: Font = .subheadline.bold()

    var body: some View {
        HStack(spacing: 3) {
            Text("BunnList").font(font)
            Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Brand.gold)
        }
        .accessibilityLabel("BunnList، الحساب الرسمي")
    }
}

/// The latest update on the community screen; opens the full list.
struct UpdatesCard: View {
    let latest: RemoteUpdate?

    var body: some View {
        NavigationLink { UpdatesView() } label: {
            HStack(alignment: .top, spacing: 12) {
                OfficialAvatar(size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("تحديثات BunnList").font(.headline).foregroundStyle(Brand.ink)
                        Spacer()
                        Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                    if let latest {
                        Text(latest.title).font(.subheadline.bold()).foregroundStyle(Brand.ink).lineLimit(1)
                        Text(latest.body).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Text("أخبار التطبيق، والقهوات الجديدة، وصندوق اقتراحاتك.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .card()
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

@MainActor
struct UpdatesView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var updates: [RemoteUpdate]?
    @State private var failed = false
    @State private var commenting: RemoteUpdate?
    @State private var showFeedback = false
    @State private var showSignIn = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                feedbackPrompt
                if let updates {
                    if updates.isEmpty {
                        ContentUnavailableView("ما فيه تحديثات للحين", systemImage: "megaphone",
                                               description: Text("أول ما ننشر شي جديد بيطلع هنا."))
                            .padding(.top, 30)
                    } else {
                        ForEach(updates) { update in post(update) }
                    }
                } else if failed {
                    ContentUnavailableView {
                        Label("ما قدرنا نجيب التحديثات", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("إعادة المحاولة") { Task { await load() } }
                    }
                } else {
                    ProgressView().padding(.top, 40)
                }
            }
            .padding(.vertical)
        }
        .background(Brand.background.ignoresSafeArea())
        .navigationTitle("تحديثات BunnList")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $commenting) { update in
            CommentsSheet(target: .update, id: update.id, title: update.title) { count in
                if let i = updates?.firstIndex(where: { $0.id == update.id }) {
                    let u = updates![i]
                    updates![i] = RemoteUpdate(id: u.id, title: u.title, body: u.body, author: u.author, createdAt: u.createdAt, commentCount: count)
                }
            }
        }
        .sheet(isPresented: $showFeedback) { NavigationStack { FeedbackView(showsClose: true) } }
        .sheet(isPresented: $showSignIn) { SignInView() }
    }

    private var feedbackPrompt: some View {
        Button {
            if auth.isSignedIn { showFeedback = true } else { showSignIn = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "envelope.open.fill").font(.title3).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Brand.olive, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("عندك اقتراح أو تجربة؟").font(.subheadline.bold()).foregroundStyle(Brand.ink)
                    Text("اكتب لنا، نقرا كل رسالة ونرد عليك.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private func post(_ u: RemoteUpdate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                OfficialAvatar(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    OfficialName()
                    if let date = ISODate.parse(u.createdAt) {
                        Text(date.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Text(u.title).font(.headline).foregroundStyle(Brand.ink)
            Text(u.body).font(.subheadline).foregroundStyle(Brand.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            Button { commenting = u } label: {
                Label(u.commentCount > 0 ? "\(u.commentCount.formatted()) تعليق" : "علّق", systemImage: "bubble.left")
                    .font(.footnote.bold())
            }
            .buttonStyle(.bordered).tint(Brand.olive)
        }
        .card()
        .padding(.horizontal)
    }

    private func load() async {
        failed = false
        do { updates = try await client.fetchUpdates(accessToken: auth.currentAccessToken()) }
        catch { if updates == nil { failed = true } }
    }
}

/// «تواصل معنا»: send a suggestion, an experience or a problem, and read the team's replies.
@MainActor
struct FeedbackView: View {
    /// Shown as a sheet (from the updates screen) it needs its own close button.
    var showsClose = false
    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind = FeedbackKind.suggestion
    @State private var text = ""
    @State private var sending = false
    @State private var message: String?
    @State private var mine: [RemoteFeedback]?
    @FocusState private var focused: Bool
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                Picker("النوع", selection: $kind) {
                    ForEach(FeedbackKind.allCases) { k in Label(k.nameAr, systemImage: k.symbol).tag(k) }
                }
                .pickerStyle(.segmented)
                TextField(kind.placeholder, text: $text, axis: .vertical)
                    .lineLimit(4...10)
                    .focused($focused)
                    .onChange(of: text) { _, v in if v.count > 2000 { text = String(v.prefix(2000)) } }
            } header: {
                Text("رسالتك لفريق BunnList")
            } footer: {
                Text("نرد عليك هنا ويوصلك إشعار.")
            }

            Section {
                Button {
                    Task { await send() }
                } label: {
                    Label(sending ? "نرسل…" : "أرسل", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Brand.olive)
                .disabled(sending || trimmed.count < 3)
                .listRowBackground(Color.clear)
                if let message { Label(message, systemImage: "info.circle").foregroundStyle(Brand.olive) }
            }

            if let mine, !mine.isEmpty {
                Section("رسائلك") {
                    ForEach(mine) { item in thread(item) }
                }
            }
        }
        .navigationTitle("تواصل معنا")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if showsClose { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } } }
        .task { await loadMine() }
        .refreshable { await loadMine() }
    }

    private func thread(_ f: RemoteFeedback) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(f.feedbackKind.nameAr, systemImage: f.feedbackKind.symbol).font(.caption.bold()).foregroundStyle(Brand.olive)
                Spacer()
                if let date = ISODate.parse(f.createdAt) {
                    Text(date.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(f.body).font(.subheadline)
            if let reply = f.reply {
                HStack(alignment: .top, spacing: 8) {
                    OfficialAvatar(size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        OfficialName(font: .caption.bold())
                        Text(reply).font(.subheadline)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            } else {
                Text("وصلتنا، بنرد عليك قريب").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func send() async {
        guard trimmed.count >= 3 else { return }
        sending = true
        message = nil
        defer { sending = false }
        do {
            let sent = try await auth.withToken { try await client.sendFeedback(kind: kind, body: trimmed, accessToken: $0) }
            Haptics.tap()
            withAnimation { mine = [sent] + (mine ?? []) }
            text = ""
            focused = false
            message = "وصلتنا، شكرًا لك!"
        } catch APIError.rateLimited {
            message = "أرسلت رسائل كثير اليوم، كمّل بكرة."
        } catch {
            message = "ما انرسلت، جرّب مرة ثانية."
        }
    }

    private func loadMine() async {
        guard auth.isSignedIn else { return }
        mine = try? await auth.withToken { try await client.fetchMyFeedback(accessToken: $0) }
    }
}

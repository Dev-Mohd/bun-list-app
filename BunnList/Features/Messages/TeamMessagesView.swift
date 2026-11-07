import BunnListCore
import SwiftUI

/// «رسائل BunnList»: messages from the team, newest first, signed «فريق BunnList». One way:
/// replying goes through «صندوق اقتراحاتك». Opening the screen marks them read.
struct TeamMessagesView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var data: RemoteTeamMessages?
    @State private var failed = false
    var onRead: () -> Void = {}

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        Group {
            if let data {
                if data.messages.isEmpty {
                    ContentUnavailableView("ما فيه رسائل", systemImage: "envelope.open",
                                           description: Text("أي رسالة من فريق BunnList لك بتطلع هنا."))
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(data.messages) { TeamMessageCard(message: $0) }
                            Text("هذي رسائل من طرف واحد. تبي تراسلنا؟ من «صندوق اقتراحاتك» في الإعدادات.")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 6)
                        }
                        .padding()
                    }
                }
            } else if failed {
                ContentUnavailableView("تعذّر التحميل", systemImage: "wifi.exclamationmark")
            } else {
                ProgressView()
            }
        }
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("رسائل BunnList")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            data = try await auth.withToken { try await client.teamMessages(accessToken: $0) }
            if (data?.unread ?? 0) > 0 {
                try? await auth.withToken { try await client.markTeamMessagesRead(accessToken: $0) }
                onRead()
            }
        } catch {
            failed = data == nil
        }
    }
}

struct TeamMessageCard: View {
    let message: RemoteTeamMessage

    private var kind: TeamMessageKind { TeamMessageKind(rawValue: message.kind) ?? .general }
    private var tint: Color {
        switch kind {
        case .warning, .suspension: return Color(red: 0.76, green: 0.35, blue: 0.2)
        case .pointsReset: return Brand.gold
        case .good: return Brand.olive
        case .general: return Brand.brown
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol).font(.headline).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(tint, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(message.title).font(.headline).foregroundStyle(Brand.ink)
                    Text(ISODate.parse(message.createdAt).map { ISODate.ago($0) } ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !message.read { Circle().fill(tint).frame(width: 9, height: 9) }
            }
            Text(message.body).font(.callout).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
            Text("— فريق BunnList").font(.caption.bold()).foregroundStyle(Brand.olive)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

/// Shown at the top of «لك» while there's an unread message from the team.
struct TeamMessagesBanner: View {
    let unread: Int

    var body: some View {
        NavigationLink { TeamMessagesView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "envelope.badge.fill").font(.title3).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(Brand.olive, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(unread == 1 ? "عندك رسالة من فريق BunnList" : "عندك \(unread) رسائل من فريق BunnList").font(.headline).foregroundStyle(Brand.ink)
                    Text("اضغط تقراها").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.backward").font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Brand.olive.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

/// The admin writes to someone: a suggested text for the kind (edited before sending), signed «فريق BunnList».
struct TeamMessageComposer: View {
    let userID: String
    let name: String?
    @State var draft: TeamMessageDraft
    var onSent: () -> Void = {}

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var sending = false
    @State private var error: String?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            Form {
                Section("النوع") {
                    Picker("النوع", selection: Binding(get: { draft.kind }, set: { kind in
                        draft = .suggested(kind, name: name)
                    })) {
                        ForEach(TeamMessageKind.allCases, id: \.self) { Label($0.nameAr, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                Section {
                    TextField("العنوان", text: $draft.title)
                    TextField("الرسالة", text: $draft.body, axis: .vertical).lineLimit(6...14)
                } header: {
                    Text("الرسالة (نص مقترح، عدّله قبل الإرسال)")
                } footer: {
                    Text("توصله باسم «فريق BunnList» مع إشعار، وما يقدر يرد عليها هنا.")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("راسله")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "نرسل…" : "أرسل") { Task { await send() } }
                        .disabled(sending || draft.title.trimmingCharacters(in: .whitespaces).count < 2 || draft.body.trimmingCharacters(in: .whitespaces).count < 3)
                }
            }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            try await auth.withToken { try await client.sendTeamMessage(userID: userID, draft, accessToken: $0) }
            onSent()
            dismiss()
        } catch {
            self.error = "ما انرسلت. حاول مرة ثانية."
        }
    }
}

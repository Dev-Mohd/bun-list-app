import BunnListCore
import SwiftUI

/// The people you blocked, with «إلغاء الحظر» for each.
@MainActor
struct BlockedPeopleView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var people: [RemotePerson]?
    @State private var failed = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        List {
            if let people {
                if people.isEmpty {
                    ContentUnavailableView("ما حظرت أحد", systemImage: "hand.raised",
                                           description: Text("تقدر تحظر أي حساب من ملفه أو من تعليقه."))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(people) { person in
                        HStack(spacing: 12) {
                            AvatarView(url: person.avatarUrl, name: person.displayName ?? person.username, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(person.displayName ?? "@\(person.username)").font(.subheadline.bold())
                                Text("@\(person.username)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("إلغاء الحظر") { Task { await unblock(person) } }
                                .buttonStyle(.bordered).tint(Brand.olive).font(.footnote)
                        }
                    }
                }
            } else if failed {
                Label("ما قدرنا نجيب القائمة. اسحب للتحديث.", systemImage: "wifi.slash").foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("المحظورين")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        failed = false
        do { people = try await auth.withToken { try await client.blockedPeople(accessToken: $0) } }
        catch { if people == nil { failed = true } }
    }

    private func unblock(_ person: RemotePerson) async {
        do {
            _ = try await auth.withToken { try await client.setBlocked(false, username: person.username, accessToken: $0) }
            withAnimation { people?.removeAll { $0.username == person.username } }
        } catch {}
    }
}

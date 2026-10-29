import BunnListCore
import SwiftUI

/// «اكتشف ناس»: search by name or @username; with no search, people whose coffees
/// overlap yours and the week's most active. Each row follows (or asks to) in place.
@MainActor
struct FindPeopleView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var query = ""
    @State private var results: [RemotePersonCard]?
    @State private var suggested: RemoteSuggestedPeople?
    @State private var failed = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())
    private var searching: Bool { query.trimmingCharacters(in: .whitespaces).count >= 2 }

    var body: some View {
        List {
            if searching {
                if let results {
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(results) { PersonRow(person: $0) }
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } else if let suggested {
                if !suggested.similar.isEmpty {
                    Section("ذوقهم قريب من ذوقك") { ForEach(suggested.similar) { PersonRow(person: $0) } }
                }
                if !suggested.active.isEmpty {
                    Section("الأنشط هالأسبوع") { ForEach(suggested.active) { PersonRow(person: $0) } }
                }
                if suggested.similar.isEmpty && suggested.active.isEmpty {
                    ContentUnavailableView("ابحث عن أصحابك", systemImage: "person.2",
                                           description: Text("اكتب اسمهم أو @المعرّف. وكل ما جربت قهاوي أكثر نقترح لك ناس ذوقهم قريب منك."))
                }
            } else if failed {
                ContentUnavailableView("تعذّر التحميل", systemImage: "wifi.exclamationmark")
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("اكتشف ناس")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "ابحث بالاسم أو @المعرّف")
        .task(id: query) {
            guard searching else { results = nil; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = try? await auth.withOptionalToken { try await client.searchPeople(query, accessToken: $0) }
            if results == nil { results = [] }
        }
        .task { await loadSuggestions() }
        .refreshable { await loadSuggestions() }
    }

    private func loadSuggestions() async {
        guard auth.isSignedIn else { suggested = RemoteSuggestedPeople(similar: [], active: []); return }
        do {
            suggested = try await auth.withToken { try await client.suggestedPeople(accessToken: $0) }
            failed = false
        } catch {
            failed = suggested == nil
        }
    }
}

/// A person with a follow button that updates in place (private accounts get a request).
struct PersonRow: View {
    let person: RemotePersonCard

    @EnvironmentObject private var auth: AuthModel
    @State private var state: FollowState?
    @State private var busy = false
    @State private var showSignIn = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var current: FollowState { state ?? person.followState }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink { PublicProfileView(username: person.username) } label: {
                HStack(spacing: 12) {
                    AvatarView(url: person.avatarUrl, name: person.displayName ?? person.username, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(person.displayName ?? person.username).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if person.isPrivate { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                        }
                        Text(person.reasonAr ?? "@\(person.username)")
                            .font(.caption).foregroundStyle(person.reasonAr == nil ? Color.secondary : Brand.olive).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            Button { Task { await toggle() } } label: {
                Text(current == .none ? (person.isPrivate ? "اطلب" : "تابِع") : current == .requested ? "طلبت" : "تتابعه")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(current == .none ? Brand.ink : Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(current == .none ? Brand.background : Brand.ink)
            }
            .buttonStyle(.borderless)
            .disabled(busy)
        }
        .sheet(isPresented: $showSignIn) { SignInView() }
    }

    private func toggle() async {
        guard auth.isSignedIn else { showSignIn = true; return }
        busy = true
        defer { busy = false }
        do {
            state = try await auth.withToken {
                try await client.setFollowing(current == .none, username: person.username, accessToken: $0)
            }
            Haptics.tap()
        } catch {
            // Keeps its state.
        }
    }
}

/// People asking to follow your private account: accept or decline each.
@MainActor
struct FollowRequestsView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var people: [RemotePerson]?
    @State private var failed = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        List {
            if let people {
                if people.isEmpty {
                    ContentUnavailableView("ما فيه طلبات", systemImage: "person.badge.clock",
                                           description: Text("لما أحد يطلب يتابعك بيطلع هنا."))
                }
                ForEach(people) { person in
                    HStack(spacing: 12) {
                        NavigationLink { PublicProfileView(username: person.username) } label: {
                            HStack(spacing: 12) {
                                AvatarView(url: person.avatarUrl, name: person.displayName ?? person.username, size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.displayName ?? person.username).font(.subheadline.weight(.semibold))
                                    Text("@\(person.username)").font(.caption).foregroundStyle(.secondary)
                                        .environment(\.layoutDirection, .leftToRight)
                                }
                            }
                        }
                        Spacer(minLength: 8)
                        Button("قبول") { Task { await answer(person, accept: true) } }
                            .buttonStyle(.borderedProminent).tint(Brand.olive)
                        Button("رفض") { Task { await answer(person, accept: false) } }
                            .buttonStyle(.bordered)
                    }
                    .font(.caption.weight(.semibold))
                }
            } else if failed {
                ContentUnavailableView("تعذّر التحميل", systemImage: "wifi.exclamationmark")
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("طلبات المتابعة")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            people = try await auth.withToken { try await client.followRequests(accessToken: $0) }
            failed = false
        } catch {
            failed = people == nil
        }
    }

    private func answer(_ person: RemotePerson, accept: Bool) async {
        do {
            try await auth.withToken { try await client.answerFollowRequest(username: person.username, accept: accept, accessToken: $0) }
            Haptics.tap()
            people?.removeAll { $0.username == person.username }
        } catch {
            // Stays until it goes through.
        }
    }
}

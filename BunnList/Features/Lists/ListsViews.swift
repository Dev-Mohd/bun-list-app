import BunnListCore
import SwiftUI

// «قوائمي»: named lists of coffees. A strip in «مجموعتي», every list on its own
// screen, a sheet to add a coffee to lists, and shared links that open a list.

/// A list's cover: up to four bags in a 2×2 grid, its emoji when it's empty.
struct ListCover: View {
    let list: RemoteListSummary
    var size: CGFloat = 150

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(Brand.gold.opacity(0.12))
            if list.covers.isEmpty {
                Text(list.emoji ?? "☕").font(.system(size: size * 0.32))
            } else {
                let cell = (size - 18) / 2
                LazyVGrid(columns: [GridItem(.fixed(cell), spacing: 6), GridItem(.fixed(cell), spacing: 6)], spacing: 6) {
                    ForEach(Array(list.covers.prefix(4).enumerated()), id: \.offset) { _, url in
                        AsyncImage(url: URL(string: url)) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                            .frame(width: cell, height: cell)
                            .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(6)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topLeading) {
            if !list.covers.isEmpty, let emoji = list.emoji {
                Text(emoji).font(.title3).padding(6).background(.thinMaterial, in: Circle()).padding(6)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ListTile: View {
    let list: RemoteListSummary
    var size: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ListCover(list: list, size: size)
            HStack(spacing: 4) {
                Text(list.title).font(.subheadline.bold()).foregroundStyle(Brand.ink).lineLimit(1)
                if !list.isPublic { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
            }
            Text(list.countLine).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: size, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(list.title)، \(list.countLine)\(list.isPublic ? "" : "، خاصة")")
    }
}

/// «قوائمي» in the collection: a row of lists with a new-list tile.
@MainActor
struct MyListsStrip: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var lists: [RemoteListSummary]?
    @State private var showEditor = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("قوائمي").font(.headline)
                Spacer()
                if let lists, !lists.isEmpty {
                    NavigationLink { MyListsView() } label: { Text("الكل").font(.subheadline) }
                }
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    Button { showEditor = true } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Brand.olive.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                                .frame(width: 120, height: 120)
                                .overlay(Image(systemName: "plus").font(.title).foregroundStyle(Brand.olive))
                            Text("قائمة جديدة").font(.subheadline.bold()).foregroundStyle(Brand.olive)
                            Text(lists?.isEmpty ?? true ? "مثل «للضيوف»" : " ").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("new-list")
                    ForEach(lists ?? []) { list in
                        NavigationLink { ListDetailView(id: list.id) } label: { ListTile(list: list, size: 120) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .sheet(isPresented: $showEditor) {
            ListEditorSheet(existing: nil) { _ in Task { await load() } }
        }
        .task(id: auth.isSignedIn) { await load() }
    }

    private func load() async {
        guard auth.isSignedIn else { lists = []; return }
        lists = try? await auth.withToken { try await client.fetchMyLists(accessToken: $0) }
    }
}

/// Every list of mine.
@MainActor
struct MyListsView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var lists: [RemoteListSummary]?
    @State private var showEditor = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            if let lists {
                if lists.isEmpty {
                    ContentUnavailableView {
                        Label("ما عندك قوائم", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("سوِّ قائمة مثل «قهاوي الصيف» أو «للضيوف» وشاركها.")
                    } actions: { Button("قائمة جديدة") { showEditor = true }.buttonStyle(.borderedProminent).tint(Brand.olive) }
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(lists) { list in
                            NavigationLink { ListDetailView(id: list.id) } label: {
                                GeometryReader { geo in ListTile(list: list, size: geo.size.width) }
                                    .aspectRatio(0.78, contentMode: .fit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .background(Brand.background.ignoresSafeArea())
        .navigationTitle("قوائمي")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showEditor = true } label: { Image(systemName: "plus") }.accessibilityLabel("قائمة جديدة")
            }
        }
        .sheet(isPresented: $showEditor) { ListEditorSheet(existing: nil) { _ in Task { await load() } } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        lists = (try? await auth.withToken { try await client.fetchMyLists(accessToken: $0) }) ?? lists ?? []
    }
}

/// One list: its coffees with notes; its owner can edit, remove coffees, share or delete it.
@MainActor
struct ListDetailView: View {
    let id: String

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var page: RemoteListPage?
    @State private var failed = false
    @State private var showEditor = false
    @State private var confirmDelete = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            if let page {
                content(page)
            } else if failed {
                ContentUnavailableView("القائمة مو متاحة", systemImage: "lock",
                                       description: Text("ممكن صاحبها حذفها أو خلّاها خاصة."))
                    .padding(.top, 60)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .background(Brand.background.ignoresSafeArea())
        .navigationTitle(page?.list.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let page {
                ToolbarItemGroup(placement: .primaryAction) {
                    if page.list.isPublic {
                        ShareLink(item: SharedLink.listURL(page.list.id),
                                  message: Text("\(page.list.emoji ?? "☕") \(page.list.title) — قائمة قهاوي على BunnList")) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("مشاركة القائمة")
                    }
                    if page.isMine {
                        Menu {
                            Button { showEditor = true } label: { Label("تعديل", systemImage: "pencil") }
                            Button(role: .destructive) { confirmDelete = true } label: { Label("حذف القائمة", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("خيارات القائمة")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let list = page?.list { ListEditorSheet(existing: list) { _ in Task { await load() } } }
        }
        .confirmationDialog("تحذف القائمة؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) { Task { await delete() } }
        } message: { Text("القهاوي نفسها تبقى في مجموعتك.") }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func content(_ page: RemoteListPage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ListCover(list: page.list, size: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.list.title).font(.title2.bold())
                    HStack(spacing: 6) {
                        Text(page.list.countLine)
                        if !page.list.isPublic { Label("خاصة", systemImage: "lock.fill") }
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    if !page.isMine {
                        if let username = page.owner.username {
                            NavigationLink { PublicProfileView(username: username) } label: {
                                Text("من \(page.owner.name)").font(.subheadline.bold()).foregroundStyle(Brand.olive)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("من \(page.owner.name)").font(.subheadline)
                        }
                    }
                }
            }
            if let note = page.list.note, !note.isEmpty {
                Text(note).font(.callout).foregroundStyle(Brand.ink)
            }
            if page.lots.isEmpty {
                ContentUnavailableView {
                    Label("القائمة فاضية", systemImage: "bag")
                } description: {
                    Text(page.isMine ? "من صفحة أي قهوة اضغط ＋ وأضفها هنا." : "ما فيها قهاوي للحين.")
                }
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(page.lots) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            NavigationLink { LiveLotDetailView(slug: item.lot.slug) } label: { LotGridCard(lot: item.lot) }
                                .buttonStyle(.plain)
                            if let note = item.itemNote, !note.isEmpty {
                                Label(note, systemImage: "quote.opening").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .contextMenu {
                            if page.isMine {
                                Button(role: .destructive) { Task { await remove(item.lot.slug) } } label: {
                                    Label("شيلها من القائمة", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func load() async {
        failed = false
        do { page = try await client.fetchList(id: id, accessToken: auth.currentAccessToken()) }
        catch { failed = page == nil }
    }

    private func remove(_ slug: String) async {
        _ = try? await auth.withToken { try await client.setListItem(listID: id, slug: slug, add: false, accessToken: $0) }
        Haptics.tap()
        await load()
    }

    private func delete() async {
        if (try? await auth.withToken { try await client.deleteList(id: id, accessToken: $0) }) != nil {
            dismiss()
        }
    }
}

/// New list or edit one: name, emoji, note, public or private.
@MainActor
struct ListEditorSheet: View {
    let existing: RemoteListSummary?
    var onSaved: (RemoteListSummary) -> Void

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ListDraft()
    @State private var saving = false
    @State private var error: String?

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("اسم القائمة (مثل: قهاوي الصيف)", text: $draft.title)
                        .onChange(of: draft.title) { _, v in if v.count > ListDraft.maxTitle { draft.title = String(v.prefix(ListDraft.maxTitle)) } }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ListDraft.emojis, id: \.self) { e in
                                Button { draft.emoji = e } label: {
                                    Text(e).font(.title2).frame(width: 44, height: 44)
                                        .background(draft.emoji == e ? Brand.olive.opacity(0.18) : Color.clear, in: Circle())
                                        .overlay(Circle().stroke(draft.emoji == e ? Brand.olive : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section("وصف (اختياري)") {
                    TextField("لمن هالقائمة؟ وش يجمعها؟", text: $draft.note, axis: .vertical).lineLimit(2...4)
                }
                Section {
                    Toggle("يشوفها الناس في ملفي", isOn: $draft.isPublic).tint(Brand.olive)
                } footer: {
                    Text(draft.isPublic ? "تطلع في ملفك وتقدر تشاركها برابط." : "خاصة: ما يشوفها غيرك.")
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(existing == nil ? "قائمة جديدة" : "تعديل القائمة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "إنشاء" : "حفظ") { Task { await save() } }
                        .disabled(!draft.isValid || saving)
                }
            }
            .onAppear { if let existing, draft.title.isEmpty { draft = ListDraft(existing) } }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            let saved = try await auth.withToken { token in
                if let existing { return try await client.updateList(id: existing.id, draft, accessToken: token) }
                return try await client.createList(draft, accessToken: token)
            }
            Haptics.tap()
            onSaved(saved)
            dismiss()
        } catch APIError.unprocessable {
            error = "ما انحفظت. يمكن وصلت الحد (٣٠ قائمة)."
        } catch {
            self.error = "ما قدرنا نحفظ. حاول مرة ثانية."
        }
    }
}

/// From a coffee: tick the lists it belongs in, or start a new one with it.
@MainActor
struct AddToListSheet: View {
    let slug: String
    let lotName: String

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var lists: [RemoteListSummary]?
    @State private var busy: Set<String> = []
    @State private var showEditor = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showEditor = true } label: {
                        Label("قائمة جديدة فيها هالقهوة", systemImage: "plus.circle.fill").foregroundStyle(Brand.olive)
                    }
                }
                if let lists {
                    Section {
                        ForEach(lists) { list in
                            Button { Task { await toggle(list) } } label: {
                                HStack(spacing: 12) {
                                    ListCover(list: list, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(list.title).foregroundStyle(Brand.ink)
                                        Text(list.countLine).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if busy.contains(list.id) {
                                        ProgressView()
                                    } else {
                                        Image(systemName: list.hasLot == true ? "checkmark.circle.fill" : "circle")
                                            .font(.title3).foregroundStyle(list.hasLot == true ? Brand.olive : .secondary)
                                    }
                                }
                            }
                            .accessibilityAddTraits(list.hasLot == true ? .isSelected : [])
                        }
                    }
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .navigationTitle("أضف «\(lotName)» لقائمة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
            .sheet(isPresented: $showEditor) {
                ListEditorSheet(existing: nil) { created in
                    Task {
                        _ = try? await auth.withToken { try await client.setListItem(listID: created.id, slug: slug, add: true, accessToken: $0) }
                        await load()
                    }
                }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        lists = (try? await auth.withToken { try await client.fetchMyLists(lotSlug: slug, accessToken: $0) }) ?? lists ?? []
    }

    private func toggle(_ list: RemoteListSummary) async {
        busy.insert(list.id)
        defer { busy.remove(list.id) }
        let add = list.hasLot != true
        if var updated = try? await auth.withToken({ try await client.setListItem(listID: list.id, slug: slug, add: add, accessToken: $0) }) {
            updated.hasLot = add
            if let i = lists?.firstIndex(where: { $0.id == list.id }) { lists?[i] = updated }
            Haptics.tap()
        }
    }
}

/// A person's public lists on their profile.
@MainActor
struct UserListsGrid: View {
    let username: String

    @EnvironmentObject private var auth: AuthModel
    @State private var lists: [RemoteListSummary]?

    private let client = CatalogAPIClient(transport: URLSessionTransport())
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        Group {
            if let lists {
                if lists.isEmpty {
                    Text("ما عنده قوائم للحين.").font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(lists) { list in
                            NavigationLink { ListDetailView(id: list.id) } label: {
                                GeometryReader { geo in ListTile(list: list, size: geo.size.width) }
                                    .aspectRatio(0.78, contentMode: .fit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
            }
        }
        .padding(.horizontal)
        .task { lists = (try? await client.fetchUserLists(username: username, accessToken: auth.currentAccessToken())) ?? [] }
    }
}

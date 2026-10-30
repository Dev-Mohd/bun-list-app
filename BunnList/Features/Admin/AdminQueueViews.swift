import BunnListCore
import SwiftUI

/// «مهامك»: the console's top, counting what needs doing, each opening its list.
@MainActor
struct AdminTasksSection: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var counts: RemoteQueueCounts?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("مهامك").font(.title2.bold())
            NavigationLink { RoasterQueueView(kind: .pending) } label: {
                task(counts?.pending, "اقتراحات تنتظر", detail: "حسب المحمصة، وراجعها وحدة وحدة", color: Brand.gold)
            }
            NavigationLink { RoasterQueueView(kind: .incomplete) } label: {
                task(counts?.incomplete, "قهاوي ناقصة معلومات", detail: counts.map {
                    "منشأ \($0.noOrigin.formatted()) · معالجة \($0.noProcess.formatted()) · نكهات \($0.noNotes.formatted())"
                } ?? "المنشأ والمعالجة والنكهات", color: .red)
            }
            NavigationLink { AdminLotsView(startFilter: .noPhoto) } label: {
                task(counts?.noPhoto, "قهاوي بدون صورة", detail: "أضف صورة الكيس", color: Brand.olive)
            }
            NavigationLink { AdminReportsView() } label: {
                task(counts?.reports, "بلاغات", detail: "مراجعة المحتوى", color: Brand.ink)
            }
        }
        .buttonStyle(.plain)
        // Again on every return, so finished work comes off the counts.
        .onAppear { Task { await load() } }
    }

    func load() async {
        counts = try? await auth.withToken { try await client.queueCounts(accessToken: $0) }
    }

    private func task(_ count: Int?, _ title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(count.map { $0.formatted() } ?? "—")
                .font(.headline.monospacedDigit()).foregroundStyle(.white)
                .frame(minWidth: 52, minHeight: 48)
                .background(color.opacity((count ?? 0) > 0 ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.backward").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// The work of one kind, roaster by roaster: search, sort, and open one.
@MainActor
struct RoasterQueueView: View {
    let kind: QueueKind

    enum Sort: String, CaseIterable { case count, gaps, name }

    @EnvironmentObject private var auth: AuthModel
    @State private var groups: [RemoteRoasterGroup]?
    @State private var failed = false
    @State private var query = ""
    @State private var sort = Sort.count
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var shown: [RemoteRoasterGroup] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = (groups ?? []).filter { q.isEmpty || $0.roaster.localizedCaseInsensitiveContains(q) }
        switch sort {
        case .count: return list.sorted { $0.count > $1.count }
        case .gaps: return list.sorted { $0.gaps > $1.gaps }
        case .name: return list.sorted { $0.roaster.localizedCompare($1.roaster) == .orderedAscending }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("الترتيب", selection: $sort) {
                    Text("الأكثر عددًا").tag(Sort.count)
                    Text("الأكثر نقصًا").tag(Sort.gaps)
                    Text("أبجدي").tag(Sort.name)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            if let groups {
                if groups.isEmpty {
                    ContentUnavailableView(kind == .pending ? "ما فيه اقتراحات تنتظر" : "كل القهاوي مكتملة",
                                           systemImage: "checkmark.seal")
                }
                ForEach(shown) { g in
                    NavigationLink { RoasterQueueDetail(kind: kind, group: g) { Task { await load() } } } label: { row(g) }
                }
            } else if failed {
                Label("ما قدرنا نجيب القائمة", systemImage: "wifi.slash").foregroundStyle(.secondary)
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle(kind == .pending ? "اقتراحات تنتظر" : "قهاوي ناقصة")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "اسم المحمصة")
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ g: RemoteRoasterGroup) -> some View {
        HStack(spacing: 12) {
            AdminPhoto(url: g.imageUrl).frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(g.roaster).font(.subheadline.bold())
                HStack(spacing: 6) {
                    if g.noOrigin > 0 { gap("منشأ \(g.noOrigin.formatted())") }
                    if g.noProcess > 0 { gap("معالجة \(g.noProcess.formatted())") }
                    if g.noNotes > 0 { gap("نكهات \(g.noNotes.formatted())") }
                    if g.noPhoto > 0 { gap("صورة \(g.noPhoto.formatted())") }
                }
            }
            Spacer()
            Text(g.count.formatted()).font(.headline.monospacedDigit())
        }
    }

    private func gap(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.red)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.red.opacity(0.08), in: Capsule())
    }

    private func load() async {
        do {
            groups = try await auth.withToken { try await client.queueRoasters(kind, accessToken: $0) }
            failed = false
        } catch {
            failed = groups == nil
        }
    }
}

/// One roaster: its coffees, review them one by one, or (waiting ones) approve them all.
@MainActor
struct RoasterQueueDetail: View {
    let kind: QueueKind
    let group: RemoteRoasterGroup
    var onChange: () -> Void = {}

    @EnvironmentObject private var auth: AuthModel
    @State private var items: [RemoteQueueCard]?
    @State private var reviewing = false
    @State private var confirmAll = false
    @State private var busy = false
    @State private var message: String?
    @State private var failures: [RemoteBulkReview.Failure] = []
    @State private var editMode = EditMode.inactive
    @State private var selection = Set<String>()
    @State private var bulkEditing = false
    @State private var askCut = false
    @State private var cutProgress: String?
    @State private var askEnglishName = false
    @State private var englishName = ""
    @State private var photoTools: RemoteQueueCard?
    @State private var editedPhotos = Set<String>()
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var selecting: Bool { editMode.isEditing }

    // The screen is built in steps: one long modifier chain is too much for the type checker.
    var body: some View {
        withSheets
            .confirmationDialog("تشيل خلفيات صور \(group.roaster) اللي ما انعدّلت؟", isPresented: $askCut, titleVisibility: .visible) {
                Button("حساسية خفيفة") { Task { await cutAll(sensitivity: 30) } }
                Button("حساسية متوسطة") { Task { await cutAll(sensitivity: 50) } }
                Button("حساسية قوية") { Task { await cutAll(sensitivity: 70) } }
            } message: {
                Text("الصور اللي ما تطلع نظيفة (خلفية فيها رسومات أو ظل) تبقى مثل ما هي، وتقدر تعدّلها وحدة وحدة. الأصل محفوظ وتقدر ترجّعه.")
            }
            .alert("الاسم الإنجليزي لـ\(group.roaster)", isPresented: $askEnglishName) {
                englishNameField
            } message: {
                Text("ينحط على المحمصة وكل قهاويها مرة وحدة.")
            }
            .confirmationDialog("تعتمد \(itemCount.formatted()) قهوة من \(group.roaster)؟", isPresented: $confirmAll, titleVisibility: .visible) {
                Button("اعتمد الكل") { Task { await approveAll() } }
            }
            .task { await load() }
    }

    private var itemCount: Int { (items ?? []).count }

    private var withSheets: some View {
        withBars
            .sheet(isPresented: $bulkEditing) { bulkEditSheet }
            .sheet(item: $photoTools) { card in photoToolsSheet(card) }
            .fullScreenCover(isPresented: $reviewing, onDismiss: { Task { await load(); onChange() } }) {
                NavigationStack { QueueReviewView(kind: kind, cards: items ?? []) }
            }
    }

    private var withBars: some View {
        list
            .toolbar { ToolbarItem(placement: .primaryAction) { toolbarMenu } }
            .safeAreaInset(edge: .bottom) { selectionBar }
    }

    private var list: some View {
        List(selection: $selection) {
            actionsSection
            statusSections
            itemsSection
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle(group.roaster)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
    }

    @ViewBuilder private var actionsSection: some View {
        Section {
            Button { reviewing = true } label: {
                Label("راجعها وحدة وحدة", systemImage: "rectangle.stack.fill").font(.headline)
            }
            .disabled(itemCount == 0)
            if kind == .pending {
                Button { confirmAll = true } label: {
                    if busy { ProgressView() } else {
                        Label("اعتمد الكل (\(itemCount.formatted()))", systemImage: "checkmark.circle.fill")
                    }
                }
                .disabled(itemCount == 0 || busy)
            }
        } footer: {
            if kind == .pending {
                Text("«اعتمد الكل» ينشرها مثل ما هي: اللي بلا منشأ تصير «مزيج» واللي بلا معالجة «أخرى». الأفضل للمحامص اللي بياناتها كاملة.")
            }
        }
    }

    @ViewBuilder private var statusSections: some View {
        if let cutProgress {
            Section { Label(cutProgress, systemImage: "scissors").foregroundStyle(.secondary) }
        }
        if let message {
            Section {
                Label(message, systemImage: "checkmark.circle").foregroundStyle(Brand.olive)
                ForEach(failures) { f in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.name).font(.caption.bold())
                        Text(f.reason).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var itemsSection: some View {
        if let items {
            Section {
                ForEach(items) { item in itemRow(item).tag(item.id) }
            } header: {
                Text("القهاوي")
            } footer: {
                if selecting { Text("حدد القهاوي اللي تبي تعدّلها مرة وحدة.") }
            }
        } else {
            HStack { Spacer(); ProgressView(); Spacer() }
        }
    }

    private func itemRow(_ item: RemoteQueueCard) -> some View {
        HStack(spacing: 10) {
            AdminPhoto(url: item.imageUrl).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.semibold))
                Text(missingLine(item)).font(.caption).foregroundStyle(item.missing.isEmpty ? Brand.olive : .red)
            }
            Spacer()
            if !selecting {
                Button { photoTools = item } label: {
                    Image(systemName: "crop").font(.subheadline).foregroundStyle(Brand.ink)
                        .frame(width: 36, height: 36).background(Color.secondary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("أدوات الصورة")
            }
        }
    }

    private func missingLine(_ item: RemoteQueueCard) -> String {
        item.missing.isEmpty ? "مكتملة" : "ناقص: " + item.missing.map(QueueText.missingAr).joined(separator: "، ")
    }

    @ViewBuilder private var toolbarMenu: some View {
        if selecting {
            Button("تم") { withAnimation { editMode = .inactive; selection = [] } }
        } else {
            Menu {
                Button { withAnimation { editMode = .active } } label: { Label("تعديل جماعي", systemImage: "checklist") }
                if kind == .pending {
                    Button { askCut = true } label: { Label("شيل خلفيات المحمصة كلها", systemImage: "scissors") }
                }
                Button { startEnglishName() } label: { Label("الاسم الإنجليزي للمحمصة", systemImage: "character.book.closed") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(items == nil || busy)
        }
    }

    @ViewBuilder private var selectionBar: some View {
        if selecting {
            let all = selection.count == itemCount
            HStack(spacing: 10) {
                Button(all ? "إلغاء التحديد" : "حدد الكل") { selection = all ? [] : Set((items ?? []).map(\.id)) }
                    .buttonStyle(.bordered).tint(Brand.ink)
                Button { bulkEditing = true } label: {
                    Text("عدّل المحدد (\(selection.count.formatted()))").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(Brand.olive)
                .disabled(selection.isEmpty)
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var bulkEditSheet: some View {
        NavigationStack {
            BulkEditSheet(kind: kind == .pending ? .submission : .lot, ids: Array(selection)) { updated in
                message = "انعدّلت \(updated.formatted()) قهوة"
                failures = []
                editMode = .inactive
                selection = []
                Task { await load(); onChange() }
            }
        }
    }

    private func photoToolsSheet(_ card: RemoteQueueCard) -> some View {
        let hasOriginal = card.hasOriginalPhoto == true || editedPhotos.contains(card.id)
        return NavigationStack {
            PhotoToolsView(card: card, currentURL: card.imageUrl, hasOriginal: hasOriginal) { _ in
                editedPhotos.insert(card.id)
                Task { await load(); onChange() }
            }
        }
    }

    @ViewBuilder private var englishNameField: some View {
        TextField("مثل: Sout Roastery", text: $englishName)
            .textInputAutocapitalization(.words)
        Button("احفظ") { Task { await saveEnglishName() } }
            .disabled(englishName.trimmingCharacters(in: .whitespaces).count < 2)
        Button("إلغاء", role: .cancel) {}
    }

    private func startEnglishName() {
        englishName = items?.first(where: { $0.roasterNameEn != nil })?.roasterNameEn ?? ""
        askEnglishName = true
    }

    private func load() async {
        items = try? await auth.withToken { try await client.queueItems(kind, roaster: group.roaster, accessToken: $0) }
    }

    /// Runs the roaster-wide cut until nothing is left (each run stops before the server's time limit).
    private func cutAll(sensitivity: Double) async {
        busy = true
        defer { busy = false; cutProgress = nil }
        var done = 0
        var failed: [RemoteBulkReview.Failure] = []
        do {
            for _ in 0..<20 {
                cutProgress = "نشيل الخلفيات… انتهى \(done.formatted())"
                let r = try await auth.withToken { try await client.cutRoasterPhotos(group.roaster, sensitivity: sensitivity, accessToken: $0) }
                done += r.done
                failed += r.failed
                if r.remaining == 0 { break }
            }
            message = "انشالت خلفية \(done.formatted()) صورة" + (failed.isEmpty ? "" : " • \(failed.count.formatted()) بقت مثل ما هي:")
        } catch {
            message = "وقفنا بعد \(done.formatted()) صورة. اضغطها مرة ثانية تكمّل."
        }
        failures = failed
        await load()
        onChange()
    }

    private func saveEnglishName() async {
        let name = englishName.trimmingCharacters(in: .whitespaces)
        busy = true
        defer { busy = false }
        do {
            let n = try await auth.withToken { try await client.setRoasterEnglishName(group.roaster, nameEn: name, accessToken: $0) }
            message = "صار اسمها «\(name)» على المحمصة و\(n.formatted()) اقتراح"
            failures = []
            await load()
        } catch {
            message = "ما انحفظ الاسم. حاول مرة ثانية."
        }
    }

    private func approveAll() async {
        let ids = (items ?? []).filter { $0.kind == .submission }.map(\.id)
        guard !ids.isEmpty else { return }
        busy = true
        defer { busy = false }
        var done = 0, left = 0
        do {
            for start in stride(from: 0, to: ids.count, by: 25) {
                let chunk = Array(ids[start..<min(start + 25, ids.count)])
                let r = try await auth.withToken { try await client.bulkReview(ids: chunk, action: .approve, accessToken: $0) }
                done += r.done.count
                left += r.failed.count
            }
        } catch {
            left = ids.count - done
        }
        message = "انعتمد \(done.formatted())" + (left > 0 ? " • باقي \(left.formatted())، اضغط مرة ثانية" : "")
        failures = []
        await load()
        onChange()
    }
}

/// One coffee at a time: its photo and details, what's missing in red, the details
/// its description gives as one-tap answers, then approve / save, skip or reject.
@MainActor
struct QueueReviewView: View {
    let kind: QueueKind
    let cards: [RemoteQueueCard]

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var edit: QueueEdit?
    @State private var suggestion: RemoteDetailSuggestion?
    @State private var suggesting = false
    @State private var newNote = ""
    @State private var busy = false
    @State private var error: String?
    @State private var done = 0
    /// Photos changed in this session, by card (nil: deleted).
    @State private var photos: [String: String?] = [:]
    @State private var photoTools: RemoteQueueCard?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var card: RemoteQueueCard? { cards.indices.contains(index) ? cards[index] : nil }

    private func toolsSheet(_ card: RemoteQueueCard) -> some View {
        let edited = photos.keys.contains(card.id)
        return NavigationStack {
            PhotoToolsView(card: card, currentURL: photoURL(card), hasOriginal: card.hasOriginalPhoto == true || edited) { url in
                photos[card.id] = .some(url)
            }
        }
    }

    private func photoURL(_ card: RemoteQueueCard) -> String? {
        if let changed = photos[card.id] { return changed }
        return card.imageUrl
    }

    var body: some View {
        Group {
            if let card, let binding = Binding($edit) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ProgressView(value: Double(index), total: Double(max(cards.count, 1))).tint(Brand.ink)
                        cardView(card, binding)
                    }
                    .padding()
                }
                .safeAreaInset(edge: .bottom) { actions(card) }
            } else {
                ContentUnavailableView {
                    Label("خلصت", systemImage: "checkmark.seal.fill")
                } description: {
                    Text("راجعت \(done.formatted()) من \(cards.count.formatted()).")
                } actions: {
                    Button("رجوع") { dismiss() }.buttonStyle(.borderedProminent).tint(Brand.olive)
                }
            }
        }
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle(kind == .pending ? "مراجعة" : "إكمال المعلومات")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("إنهاء") { dismiss() } }
            ToolbarItem(placement: .principal) {
                Text("\(min(index + 1, cards.count).formatted()) / \(cards.count.formatted())").font(.subheadline.monospacedDigit())
            }
        }
        .task(id: index) { await open() }
        .sheet(item: $photoTools) { card in toolsSheet(card) }
    }

    // MARK: Card

    private func cardView(_ card: RemoteQueueCard, _ edit: Binding<QueueEdit>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminPhoto(url: photoURL(card))
                .frame(height: 220)
                .overlay(alignment: .topLeading) {
                    if photoURL(card) == nil { badge("بدون صورة") }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button { photoTools = card } label: {
                        Label("أدوات الصورة", systemImage: "crop").font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.white, in: Capsule()).foregroundStyle(Brand.ink)
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name).font(.title3.bold())
                Text(card.roasterName).font(.subheadline).foregroundStyle(.secondary)
            }

            if let s = suggestion, !s.isEmpty {
                Button {
                    withAnimation { edit.wrappedValue.apply(s) }
                    Haptics.tap()
                } label: {
                    Label("خذ كل اقتراحات الوصف", systemImage: "text.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered).tint(Brand.olive)
            } else if suggesting {
                Label("نقرأ الوصف…", systemImage: "text.magnifyingglass").font(.caption).foregroundStyle(.secondary)
            }

            field("المنشأ", missing: edit.wrappedValue.originCode == nil) {
                if let code = suggestion?.originCode, code != edit.wrappedValue.originCode {
                    suggestionChip((ReferenceCodes.country(code)?.nameAr ?? code) + " (من الوصف)") { edit.wrappedValue.setOrigin(code: code) }
                }
                Picker("المنشأ", selection: Binding(get: { edit.wrappedValue.originCode ?? "" },
                                                     set: { edit.wrappedValue.setOrigin(code: $0.isEmpty ? nil : $0) })) {
                    Text("مزيج / غير معروف").tag("")
                    ForEach(ReferenceCodes.countries.filter { $0.code != "XB" }, id: \.code) { Text($0.nameAr).tag($0.code) }
                }
                .pickerStyle(.menu)
            }

            field("المعالجة", missing: edit.wrappedValue.process == nil) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let p = suggestion?.process, p != edit.wrappedValue.process {
                            suggestionChip((ReferenceCodes.process(p)?.nameAr ?? p) + " (من الوصف)") { edit.wrappedValue.process = p }
                        }
                        ForEach(ReferenceCodes.processes.filter { $0.code != "OTHER" }, id: \.code) { p in
                            ChoiceChip(title: p.nameAr, isSelected: edit.wrappedValue.process == p.code) {
                                edit.wrappedValue.process = edit.wrappedValue.process == p.code ? nil : p.code
                            }
                        }
                    }
                }
            }

            field("النكهات", missing: edit.wrappedValue.flavorNotes.isEmpty) {
                if let notes = suggestion?.flavorNotes, !notes.isEmpty, notes != edit.wrappedValue.flavorNotes {
                    suggestionChip(notes.joined(separator: " · ") + " (من الوصف)") { edit.wrappedValue.flavorNotes = notes }
                }
                if !edit.wrappedValue.flavorNotes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(edit.wrappedValue.flavorNotes, id: \.self) { note in
                                Button { edit.wrappedValue.flavorNotes.removeAll { $0 == note } } label: {
                                    Label(note, systemImage: "xmark").labelStyle(.titleAndIcon).font(.caption)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Color.secondary.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                HStack {
                    TextField("أضف نكهة", text: $newNote).textFieldStyle(.roundedBorder).onSubmit { addNote(edit) }
                    Button("إضافة") { addNote(edit) }.disabled(newNote.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            field("التحميص", missing: false) {
                HStack(spacing: 6) {
                    if let r = suggestion?.roastLevel, r != edit.wrappedValue.roastLevel {
                        suggestionChip(r.nameAr + " (من الوصف)") { edit.wrappedValue.roastLevel = r }
                    }
                    ForEach(RoastLevel.allCases, id: \.self) { r in
                        ChoiceChip(title: r.nameAr, isSelected: edit.wrappedValue.roastLevel == r) {
                            edit.wrappedValue.roastLevel = edit.wrappedValue.roastLevel == r ? nil : r
                        }
                    }
                }
            }

            if let description = card.descriptionAr, !description.isEmpty {
                DisclosureGroup("وصف المحمصة") {
                    Text(description).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private func field(_ title: String, missing: Bool, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                if missing { Text("ناقصة").font(.caption.bold()).foregroundStyle(.red) }
            }
            content()
        }
    }

    private func suggestionChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation { action() }; Haptics.tap() } label: {
            Label(title, systemImage: "checkmark").font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Brand.olive.opacity(0.14), in: Capsule())
                .foregroundStyle(Brand.olive)
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.caption2.bold()).foregroundStyle(.red)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.white, in: Capsule()).padding(8)
    }

    // MARK: Actions

    private func actions(_ card: RemoteQueueCard) -> some View {
        HStack(spacing: 10) {
            if kind == .pending {
                actionButton("رفض", icon: "xmark", tint: .red) { await reject(card) }
            }
            actionButton("تخطّي", icon: "arrow.uturn.left", tint: .secondary) { next(counted: false) }
            actionButton(kind == .pending ? "اعتمد" : "احفظ", icon: "checkmark", tint: Brand.olive, prominent: true) { await save(card) }
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(.bar)
        .disabled(busy)
    }

    private func actionButton(_ title: String, icon: String, tint: Color, prominent: Bool = false, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(title, systemImage: icon).font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(prominent ? tint : tint.opacity(0.12), in: Capsule())
                .foregroundStyle(prominent ? Brand.background : tint)
        }
        .buttonStyle(.plain)
    }

    private func addNote(_ edit: Binding<QueueEdit>) {
        let note = newNote.trimmingCharacters(in: .whitespaces)
        guard !note.isEmpty, !edit.wrappedValue.flavorNotes.contains(note) else { return }
        edit.wrappedValue.flavorNotes.append(note)
        newNote = ""
    }

    private func open() async {
        guard let card else { edit = nil; return }
        edit = QueueEdit(card)
        suggestion = nil
        error = nil
        newNote = ""
        guard !card.missing.filter({ $0 != .photo }).isEmpty, card.descriptionAr?.isEmpty == false else { return }
        suggesting = true
        defer { suggesting = false }
        let id = card.id
        let s = try? await auth.withToken { try await client.suggestDetails(for: card, accessToken: $0) }
        if self.card?.id == id { suggestion = s }
    }

    private func next(counted: Bool) {
        if counted { done += 1 }
        withAnimation { index += 1 }
    }

    private func save(_ card: RemoteQueueCard) async {
        guard let edit else { return }
        busy = true
        defer { busy = false }
        do {
            if card.kind == .submission {
                _ = try await auth.withToken { try await client.approve(edit, accessToken: $0) }
            } else {
                let changes = edit.lotChanges()
                if !changes.isEmpty {
                    _ = try await auth.withToken { try await client.updateAdminLot(id: card.id, changes: changes, accessToken: $0) }
                }
            }
            Haptics.tap()
            next(counted: true)
        } catch {
            self.error = "ما انحفظت. حاول مرة ثانية."
        }
    }

    private func reject(_ card: RemoteQueueCard) async {
        busy = true
        defer { busy = false }
        do {
            try await auth.withToken { try await client.rejectSubmission(id: card.id, reason: nil, accessToken: $0) }
            next(counted: true)
        } catch {
            self.error = "ما انرفضت. حاول مرة ثانية."
        }
    }
}

enum QueueText {
    static func missingAr(_ m: RemoteQueueCard.Missing) -> String {
        switch m {
        case .origin: return "المنشأ"
        case .process: return "المعالجة"
        case .notes: return "النكهات"
        case .photo: return "الصورة"
        }
    }
}

/// One coffee's photo: lift the backdrop (with a sensitivity), crop, keep the
/// backdrop, compare before and after, save, bring the original back, or delete.
/// The cut runs on the server with plain pixel arithmetic; nothing is generated.
@MainActor
struct PhotoToolsView: View {
    let card: RemoteQueueCard
    let currentURL: String?
    /// Whether the original is kept to bring back (the card's flag, or edited in this session).
    let hasOriginal: Bool
    /// The new photo's URL (nil when deleted).
    var onSaved: (String?) -> Void

    enum Side: String { case before, after }

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var edit = PhotoEdit()
    @State private var top = 0.0
    @State private var bottom = 0.0
    @State private var left = 0.0
    @State private var right = 0.0
    @State private var side = Side.after
    @State private var preview: RemotePhotoPreview?
    @State private var previewImage: UIImage?
    @State private var loading = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var crop: PhotoCrop { PhotoCrop(top: top, bottom: bottom, leading: left, trailing: right) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $side) {
                    Text("قبل").tag(Side.before)
                    Text("بعد").tag(Side.after)
                }
                .pickerStyle(.segmented)

                photo
                    .frame(height: 320)
                    .frame(maxWidth: .infinity)
                    .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 16))

                if let warning = preview?.warningAr, side == .after {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                }

                backgroundBox
                cropBox
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                buttons
            }
            .padding()
        }
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("أدوات الصورة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
        .confirmationDialog("تحذف صورة «\(card.name)»؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("احذف الصورة", role: .destructive) { Task { await delete() } }
        } message: {
            Text(card.kind == .submission ? "تقدر ترجّع الأصل بعدين." : "القهوة المنشورة تصير بدون صورة.")
        }
        // A new preview a moment after the last change.
        .task(id: PreviewKey(edit: edit, crop: crop)) {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await loadPreview()
        }
    }

    private struct PreviewKey: Equatable { let edit: PhotoEdit; let crop: PhotoCrop }

    private var backgroundBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("شيل الخلفية", isOn: $edit.removeBackground).tint(Brand.olive)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("الحساسية").font(.subheadline.bold())
                    Spacer()
                    Text(Int(edit.sensitivity).formatted()).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $edit.sensitivity, in: 0...100, step: 5) {
                    Text("الحساسية")
                } minimumValueLabel: {
                    Text("أقل").font(.caption)
                } maximumValueLabel: {
                    Text("أكثر").font(.caption)
                }
                .tint(Brand.olive)
                Text("لو أكلت من الكيس خفّفها، ولو بقى شي من الخلفية زِدها.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!edit.removeBackground)
            .opacity(edit.removeBackground ? 1 : 0.4)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var cropBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("القص").font(.subheadline.bold())
                Spacer()
                if top + bottom + left + right > 0 {
                    Button("بدون قص") { top = 0; bottom = 0; left = 0; right = 0 }.font(.caption)
                }
            }
            cropSlider("من فوق", $top)
            cropSlider("من تحت", $bottom)
            cropSlider("من اليمين", $right)
            cropSlider("من اليسار", $left)
            Text("شوف المربع على صورة «قبل»، وخلّ الكيس داخله.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var saveDisabled: Bool { busy || (currentURL == nil && !hasOriginal) }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button { Task { await apply() } } label: {
                Label("احفظ الصورة", systemImage: "checkmark").font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Brand.olive, in: Capsule()).foregroundStyle(Brand.background)
            }
            .buttonStyle(.plain)
            .disabled(saveDisabled)
            HStack(spacing: 10) {
                if card.kind == .submission, hasOriginal {
                    Button { Task { await restore() } } label: {
                        Label("رجّع الأصل", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).tint(Brand.ink)
                }
                if currentURL != nil {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("احذف الصورة", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .disabled(busy)
        }
    }

    @ViewBuilder private var photo: some View {
        switch side {
        case .before:
            if let url = currentURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit().overlay { cropOverlay }
                } placeholder: { ProgressView() }
                .padding(8)
            } else {
                ContentUnavailableView("بدون صورة", systemImage: "photo")
            }
        case .after:
            ZStack {
                if let previewImage {
                    Image(uiImage: previewImage).resizable().scaledToFit().padding(8)
                } else if !loading {
                    ContentUnavailableView("ما فيه معاينة", systemImage: "photo")
                }
                if loading { ProgressView().controlSize(.large) }
            }
        }
    }

    /// The part the crop keeps, drawn over the "before" photo.
    private var cropOverlay: some View {
        GeometryReader { geo in
            let c = crop
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.35)
                    .mask {
                        Rectangle().overlay(alignment: .topLeading) {
                            Rectangle().frame(width: geo.size.width * c.w, height: geo.size.height * c.h)
                                .offset(x: geo.size.width * c.x, y: geo.size.height * c.y)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                Rectangle().stroke(Brand.olive, lineWidth: 2)
                    .frame(width: geo.size.width * c.w, height: geo.size.height * c.h)
                    .offset(x: geo.size.width * c.x, y: geo.size.height * c.y)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .allowsHitTesting(false)
    }

    private func cropSlider(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 70, alignment: .leading)
            Slider(value: value, in: 0...0.45, step: 0.01).tint(Brand.ink)
            Text("\(Int(value.wrappedValue * 100))٪").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36)
        }
    }

    private func current() -> PhotoEdit {
        var e = edit
        e.crop = crop
        return e
    }

    private func loadPreview() async {
        guard currentURL != nil || hasOriginal else { return }
        loading = true
        defer { loading = false }
        do {
            let p = try await auth.withToken { try await client.previewPhoto(card, current(), accessToken: $0) }
            preview = p
            previewImage = p.imageData.flatMap(UIImage.init(data:))
            error = nil
        } catch {
            preview = nil
            previewImage = nil
            self.error = "ما قدرنا نشيل الخلفية بهالإعدادات. جرّب حساسية ثانية أو قص الصورة."
        }
    }

    private func apply() async {
        busy = true
        defer { busy = false }
        do {
            let url = try await auth.withToken { try await client.applyPhoto(card, current(), accessToken: $0) }
            Haptics.tap()
            onSaved(url)
            dismiss()
        } catch {
            self.error = "ما انحفظت الصورة. حاول مرة ثانية."
        }
    }

    private func restore() async {
        busy = true
        defer { busy = false }
        do {
            let url = try await auth.withToken { try await client.restorePhoto(card, accessToken: $0) }
            onSaved(url)
            dismiss()
        } catch {
            self.error = "ما رجعت الصورة الأصلية."
        }
    }

    private func delete() async {
        busy = true
        defer { busy = false }
        do {
            try await auth.withToken { try await client.deletePhoto(card, accessToken: $0) }
            onSaved(nil)
            dismiss()
        } catch {
            self.error = "ما انحذفت الصورة."
        }
    }
}

/// The same origin, process, roast or extra notes for every selected coffee.
@MainActor
struct BulkEditSheet: View {
    let kind: RemoteQueueCard.Kind
    let ids: [String]
    var onDone: (Int) -> Void

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var edit = BulkEdit()
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        Form {
            Section {
                Text("اللي تختاره هنا ينحط على \(ids.count.formatted()) قهوة. اللي تخليه فاضي ما يتغيّر.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("المنشأ") {
                Picker("المنشأ", selection: $edit.originCode) {
                    Text("بدون تغيير").tag(String?.none)
                    ForEach(ReferenceCodes.countries.filter { $0.code != "XB" }, id: \.code) { Text($0.nameAr).tag(String?.some($0.code)) }
                }
            }
            Section("المعالجة") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ReferenceCodes.processes.filter { $0.code != "OTHER" }, id: \.code) { p in
                            ChoiceChip(title: p.nameAr, isSelected: edit.process == p.code) {
                                edit.process = edit.process == p.code ? nil : p.code
                            }
                        }
                    }
                }
            }
            Section("التحميص") {
                HStack(spacing: 6) {
                    ForEach(RoastLevel.allCases, id: \.self) { r in
                        ChoiceChip(title: r.nameAr, isSelected: edit.roastLevel == r) {
                            edit.roastLevel = edit.roastLevel == r ? nil : r
                        }
                    }
                }
            }
            Section {
                ForEach(edit.addNotes, id: \.self) { n in Text(n) }
                    .onDelete { edit.addNotes.remove(atOffsets: $0) }
                HStack {
                    TextField("نكهة", text: $note).onSubmit(addNote)
                    Button("إضافة", action: addNote).disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("أضف نكهات")
            } footer: {
                Text("تنضاف على نكهات كل قهوة، ما تمسح اللي فيها.")
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("تعديل جماعي")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if busy { ProgressView() } else {
                    Button("طبّق") { Task { await save() } }.disabled(edit.isEmpty)
                }
            }
        }
    }

    private func addNote() {
        let n = note.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !edit.addNotes.contains(n), edit.addNotes.count < 6 else { return }
        edit.addNotes.append(n)
        note = ""
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            var updated = 0
            for start in stride(from: 0, to: ids.count, by: 200) {
                let chunk = Array(ids[start..<min(start + 200, ids.count)])
                updated += try await auth.withToken { try await client.bulkEdit(kind, ids: chunk, edit, accessToken: $0) }
            }
            Haptics.tap()
            onDone(updated)
            dismiss()
        } catch {
            self.error = "ما انحفظ التعديل. حاول مرة ثانية."
        }
    }
}

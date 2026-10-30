import BunnListCore
import PhotosUI
import SwiftUI

/// Every coffee in the catalog, hidden ones too: search, filter, open to edit.
@MainActor
struct AdminLotsView: View {
    /// The filter it opens on (the console's «بدون صورة» opens on noPhoto).
    var startFilter: AdminLotFilter = .all

    @EnvironmentObject private var auth: AuthModel
    @State private var query = ""
    @State private var filter: AdminLotFilter = .all
    @State private var appliedStart = false
    @State private var lots: [RemoteAdminLotRow]?
    @State private var failed = false
    /// Bulk delete: tap rows to pick them (the hidden filter is the usual place for it).
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var busy = false
    @State private var confirmDelete = false
    @State private var result: RemoteBulkReview?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        List {
            if let result {
                Section {
                    Label("انحذف \(result.done.count)" + (result.failed.isEmpty ? "" : " • ما انحذف \(result.failed.count)"),
                          systemImage: "trash").foregroundStyle(Brand.olive)
                    ForEach(result.failed) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).font(.subheadline.weight(.semibold))
                            Text(f.reason).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
            Section {
                Picker("التصفية", selection: $filter) {
                    ForEach(AdminLotFilter.allCases, id: \.self) { Text($0.nameAr).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            if let lots {
                if lots.isEmpty {
                    ContentUnavailableView("ما فيه نتائج", systemImage: "magnifyingglass")
                }
                ForEach(lots) { lot in
                    if selecting {
                        Button { toggle(lot.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(lot.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected.contains(lot.id) ? .red : .secondary)
                                AdminLotRow(lot: lot)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(lot.id) ? .isSelected : [])
                    } else {
                        NavigationLink { AdminLotEditView(lotID: lot.id) { Task { await load() } } } label: { AdminLotRow(lot: lot) }
                    }
                }
            } else if failed {
                Label("ما قدرنا نجيب القهوات", systemImage: "wifi.slash").foregroundStyle(.secondary)
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("القهوات")
        .searchable(text: $query, prompt: "اسم القهوة أو المحمصة")
        .onAppear { if !appliedStart { filter = startFilter; appliedStart = true } }
        .task(id: "\(filter.rawValue)|\(query)") {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await load()
        }
        .refreshable { await load() }
        .toolbar {
            if !(lots ?? []).isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(selecting ? "إلغاء" : "تحديد") {
                        selecting.toggle()
                        selected = []
                    }
                }
            }
        }
        // Above the list: the app's floating tab bar would cover a bottom bar.
        .safeAreaInset(edge: .top, spacing: 0) {
            if selecting {
                HStack {
                    Button(selected.count == (lots ?? []).count ? "إلغاء الكل" : "تحديد الكل") {
                        let all = Set((lots ?? []).map(\.id))
                        selected = selected == all ? [] : all
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    if busy {
                        ProgressView()
                    } else {
                        Button("حذف (\(selected.count))", role: .destructive) { confirmDelete = true }
                            .buttonStyle(.borderedProminent).tint(.red)
                            .disabled(selected.isEmpty)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .confirmationDialog("تحذف \(selected.count) قهوة نهائيًا؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) { Task { await deleteSelected() } }
        } message: {
            Text("ما تقدر ترجعها، والاستيراد ما يرجّعها. اللي لها تقييمات أو تحضيرات ما تنحذف.")
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func deleteSelected() async {
        let ids = (lots ?? []).map(\.id).filter(selected.contains)
        guard !ids.isEmpty else { return }
        busy = true
        defer { busy = false }
        var done: [String] = []
        var failures: [RemoteBulkReview.Failure] = []
        do {
            for start in stride(from: 0, to: ids.count, by: 50) {
                let chunk = Array(ids[start..<min(start + 50, ids.count)])
                let r = try await auth.withToken { try await client.bulkDeleteLots(ids: chunk, accessToken: $0) }
                done += r.done
                failures += r.failed
            }
        } catch {
            failures.append(.init(id: "network", name: "انقطع الطلب", reason: "اللي انحذف محفوظ. حدّث القائمة وكمّل الباقي."))
        }
        result = RemoteBulkReview(done: done, failed: failures)
        selected = []
        selecting = false
        await load()
    }

    private func load() async {
        do {
            lots = try await auth.withToken { try await client.adminLots(query: query, filter: filter, accessToken: $0) }
            failed = false
        } catch {
            failed = lots == nil
        }
    }
}

private struct AdminLotRow: View {
    let lot: RemoteAdminLotRow

    var body: some View {
        HStack(spacing: 12) {
            LotPhotoWell(imageUrl: lot.imageUrl, notes: [], roaster: lot.roasterNameAr, name: lot.nameAr,
                         origin: lot.originNameAr, originCode: lot.originCode, padding: 2)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(lot.nameAr).font(.subheadline.bold()).lineLimit(1)
                Text([lot.roasterNameAr, lot.originNameAr].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !lot.published {
                Label("مخفية", systemImage: "eye.slash").font(.caption2.bold()).foregroundStyle(.red)
            }
        }
    }
}

/// Edits one coffee: details, notes, tags, visibility and photo. Saves only what changed.
@MainActor
struct AdminLotEditView: View {
    let lotID: String
    var onSaved: () -> Void = {}

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var lot: RemoteAdminLot?
    @State private var form: AdminLotForm?
    @State private var newNote = ""
    @State private var isSaving = false
    @State private var message: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var trending: String?
    @State private var confirmDelete = false
    @State private var isDeleting = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private static let tagNames: [(String, String)] = [("luxury", "فاخرة"), ("infused", "منقوعة"), ("decaf", "منزوعة الكافيين")]

    var body: some View {
        Group {
            if let lot, let binding = Binding($form) {
                editor(lot, binding)
            } else if message != nil {
                ContentUnavailableView("ما قدرنا نفتح القهوة", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .brandScreen()
        .navigationTitle(lot?.nameAr ?? "قهوة")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: photoItem) { _, item in if let item { Task { await upload(item) } } }
    }

    private func setTrending(_ mode: String) async {
        let previous = trending
        trending = mode
        do {
            try await auth.withToken { try await client.setTrending(lotID: lotID, mode: mode == "auto" ? nil : mode, accessToken: $0) }
            message = mode == "pin" ? "انثبّتت في الترند" : mode == "hide" ? "انخفت من الترند" : "رجعت تلقائي"
        } catch {
            trending = previous
            message = "ما تغيّر الترند. حاول مرة ثانية."
        }
    }

    private func load() async {
        do {
            let fresh = try await auth.withToken { try await client.adminLot(id: lotID, accessToken: $0) }
            lot = fresh
            form = AdminLotForm(fresh)
        } catch {
            message = "تعذّر التحميل"
        }
    }

    private func editor(_ lot: RemoteAdminLot, _ form: Binding<AdminLotForm>) -> some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    LotPhotoWell(imageUrl: lot.imageUrl, notes: form.wrappedValue.flavorNotes, roaster: lot.roasterNameAr,
                                 name: lot.nameAr, origin: lot.originNameAr, originCode: lot.originCode)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(isUploading ? "نرفع الصورة…" : "تغيير الصورة", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(isUploading)
                    Text("نقص الكيس من الخلفية تلقائيًا. صور حقيقية بس.").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            Section {
                Toggle("ظاهرة في التطبيق والموقع", isOn: form.published)
                    .tint(Brand.olive)
            } footer: {
                Text("الإخفاء ما يحذف شي، تقدر ترجعها متى ما بغيت.")
            }

            Section("الاسم") {
                TextField("بالعربي", text: form.nameAr)
                TextField("بالإنجليزي", text: form.name).environment(\.layoutDirection, .leftToRight)
            }

            Section("المنشأ والمعالجة") {
                Picker("المنشأ", selection: Binding(
                    get: { form.wrappedValue.originCode },
                    set: { code in
                        form.wrappedValue.originCode = code
                        if let code, let entry = ReferenceCodes.country(code) { form.wrappedValue.originNameAr = entry.nameAr }
                    }
                )) {
                    ForEach(ReferenceCodes.countries, id: \.code) { Text($0.nameAr).tag(Optional($0.code)) }
                }
                Picker("المعالجة", selection: form.process) {
                    ForEach(ReferenceCodes.processes, id: \.code) { Text($0.nameAr).tag($0.code) }
                }
                TextField("وصف المعالجة (اختياري)", text: form.processLabel)
                TextField("التحميص (فاتح، متوسط...)", text: form.roastLevel)
            }

            Section("النكهات") {
                ForEach(form.wrappedValue.flavorNotes.indices, id: \.self) { i in
                    TextField("نكهة", text: form.flavorNotes[i])
                }
                .onDelete { form.wrappedValue.flavorNotes.remove(atOffsets: $0) }
                .onMove { form.wrappedValue.flavorNotes.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    TextField("أضف نكهة", text: $newNote).onSubmit(addNote)
                    Button("إضافة", action: addNote).disabled(newNote.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("التفاصيل") {
                TextField("المنطقة", text: form.region)
                TextField("السلالة", text: form.variety)
                TextField("الارتفاع بالمتر", text: form.altitude).keyboardType(.numberPad)
                TextField("الوصف", text: form.descriptionAr, axis: .vertical).lineLimit(3...8)
            }

            Section {
                Picker("في الترند", selection: Binding(
                    get: { trending ?? lot.trending ?? "auto" },
                    set: { mode in Task { await setTrending(mode) } }
                )) {
                    Text("تلقائي").tag("auto")
                    Text("مثبّتة").tag("pin")
                    Text("مخفية").tag("hide")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("ترند الواجهة")
            } footer: {
                Text("تلقائي = حسب نشاط الأسبوع. المثبّتة تطلع أول القائمة، والمخفية ما تطلع أبد. يتطبّق فورًا.")
            }

            Section("العلامات") {
                ForEach(Self.tagNames, id: \.0) { tag, name in
                    Toggle(name, isOn: Binding(
                        get: { form.wrappedValue.tags.contains(tag) },
                        set: { on in if on { form.wrappedValue.tags.insert(tag) } else { form.wrappedValue.tags.remove(tag) } }
                    ))
                    .tint(Brand.olive)
                }
            }

            if let message {
                Section { Label(message, systemImage: "info.circle").foregroundStyle(Brand.olive) }
            }

            Section {
                Button(role: .destructive) { confirmDelete = true } label: {
                    if isDeleting { ProgressView() } else { Label("حذف القهوة من الدليل", systemImage: "trash") }
                }
                .disabled(isDeleting)
            } footer: {
                Text("الحذف نهائي، وتنشال من مجموعات الناس. القهوة اللي لها تقييمات أو تحضيرات ما تنحذف، أخفها بدال كذا.")
            }
        }
        .confirmationDialog("تحذف «\(lot.nameAr)» نهائيًا؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) { Task { await delete() } }
        } message: {
            Text("ما تقدر ترجعها بعد الحذف، والاستيراد ما يرجّعها.")
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("حفظ") { Task { await save(lot) } }
                    .disabled(isSaving || form.wrappedValue.changes(from: lot).isEmpty)
            }
        }
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await auth.withToken { try await client.deleteAdminLot(id: lotID, accessToken: $0) }
            onSaved()
            dismiss()
        } catch APIError.conflict {
            message = "ما تنحذف: لها تقييمات أو تحضيرات من الناس. أطفِ «ظاهرة في التطبيق والموقع» عشان تخفيها."
        } catch {
            message = "ما انحذفت. حاول مرة ثانية."
        }
    }

    private func addNote() {
        let note = newNote.trimmingCharacters(in: .whitespaces)
        guard !note.isEmpty else { return }
        form?.flavorNotes.append(note)
        newNote = ""
    }

    private func save(_ original: RemoteAdminLot) async {
        guard let changes = form?.changes(from: original), !changes.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await auth.withToken { try await client.updateAdminLot(id: lotID, changes: changes, accessToken: $0) }
            lot = saved
            form = AdminLotForm(saved)
            message = "انحفظت التعديلات"
            onSaved()
        } catch {
            message = "ما انحفظت التعديلات. تأكد من الحقول وحاول مرة ثانية."
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        defer { isUploading = false; photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            message = "ما قدرنا نقرأ الصورة"
            return
        }
        // The bag on white, like the bundled photos, so the card's flavor wash shows through.
        let card = await BagCutout.process(image, background: .white, enhance: false)?.image ?? image
        guard let jpeg = card.jpegData(compressionQuality: 0.85) else { return }
        do {
            _ = try await auth.withToken { try await client.replaceAdminLotPhoto(id: lotID, jpeg: jpeg, accessToken: $0) }
            await load()
            message = "تغيّرت الصورة"
            onSaved()
        } catch {
            message = "ما قدرنا نرفع الصورة"
        }
    }
}

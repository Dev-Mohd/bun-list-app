import BunnListCore
import PhotosUI
import SwiftUI

/// Every coffee in the catalog, hidden ones too: search, filter, open to edit.
@MainActor
struct AdminLotsView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var query = ""
    @State private var filter: AdminLotFilter = .all
    @State private var lots: [RemoteAdminLotRow]?
    @State private var failed = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        List {
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
                    NavigationLink { AdminLotEditView(lotID: lot.id) { Task { await load() } } } label: { AdminLotRow(lot: lot) }
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
        .task(id: "\(filter.rawValue)|\(query)") {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await load()
        }
        .refreshable { await load() }
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
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("حفظ") { Task { await save(lot) } }
                    .disabled(isSaving || form.wrappedValue.changes(from: lot).isEmpty)
            }
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
        let card = await BagCutout.process(image, background: .white)?.image ?? image
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

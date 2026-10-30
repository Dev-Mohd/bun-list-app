import BunnListCore
import PhotosUI
import SwiftUI

/// Admin: the grinder guide. Add the bundled grinders, then fill each grinder's
/// specs from the maker's own pages (with the link as its source), and its photo.
@MainActor
struct AdminGrindersView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var grinders: [RemoteGrinder]?
    @State private var query = ""
    @State private var onlyMissing = false
    @State private var message: String?
    @State private var isSeeding = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var shown: [RemoteGrinder] {
        (grinders ?? []).filter { $0.matches(query) && (!onlyMissing || !$0.hasSpecs || $0.imageUrl == nil) }
    }

    var body: some View {
        List {
            Section {
                Button { Task { await seed() } } label: {
                    Label(isSeeding ? "نضيف…" : "أضف مطاحن الدليل الناقصة", systemImage: "tray.and.arrow.down.fill")
                }
                .disabled(isSeeding)
                Toggle("الناقصة بس (مواصفات أو صورة)", isOn: $onlyMissing).tint(Brand.olive)
                if let message { Text(message).font(.caption).foregroundStyle(Brand.olive) }
                if let all = grinders {
                    Text("\(all.count) مطحنة · \(all.filter(\.hasSpecs).count) بمواصفات · \(all.filter { $0.imageUrl != nil }.count) بصورة")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(shown) { g in
                NavigationLink { AdminGrinderEditView(grinder: g) { updated in replace(updated) } } label: {
                    HStack(spacing: 12) {
                        GrinderPhoto(grinder: g).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(g.brand) \(g.title)").font(.subheadline.bold()).lineLimit(1)
                            Text(g.categoryAr).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !g.hasSpecs { Image(systemName: "ruler").foregroundStyle(.orange).accessibilityLabel("بلا مواصفات") }
                        if g.imageUrl == nil { Image(systemName: "photo").foregroundStyle(.orange).accessibilityLabel("بلا صورة") }
                        if !g.published { Image(systemName: "eye.slash").foregroundStyle(.red) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("دليل المطاحن")
        .searchable(text: $query, prompt: "ماركة أو موديل")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        grinders = try? await auth.withToken { try await client.adminGrinders(accessToken: $0) }
    }

    private func seed() async {
        isSeeding = true
        defer { isSeeding = false }
        do {
            let result = try await auth.withToken { try await client.seedGrinders(accessToken: $0) }
            message = result.created + result.specs > 0
                ? "انضافت \(result.created) مطحنة، وتعبّت مواصفات \(result.specs)"
                : "كل مطاحن الدليل ومواصفاتها موجودة"
            await load()
            await GrinderCatalog.shared.load(force: true)
        } catch {
            message = "ما قدرنا نضيفها. حاول مرة ثانية."
        }
    }

    private func replace(_ g: RemoteGrinder) {
        if let i = grinders?.firstIndex(where: { $0.id == g.id }) { grinders?[i] = g }
        Task { await GrinderCatalog.shared.load(force: true) }
    }
}

/// Edits one grinder. Every number should come from the maker; add its page as a source.
@MainActor
struct AdminGrinderEditView: View {
    let grinder: RemoteGrinder
    var onSaved: (RemoteGrinder) -> Void

    @EnvironmentObject private var auth: AuthModel
    @State private var adjustment: String?
    @State private var rangeMin = ""
    @State private var rangeMax = ""
    @State private var clicksPerRotation = ""
    @State private var micronsPerStep = ""
    @State private var zeroGuide = ""
    @State private var notes = ""
    @State private var sources: [RemoteGrinder.Source] = []
    @State private var newSourceLabel = ""
    @State private var newSourceURL = ""
    @State private var published = true
    @State private var photoItem: PhotosPickerItem?
    @State private var current: RemoteGrinder?
    @State private var message: String?
    @State private var isSaving = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        Form {
            Section {
                GrinderPhoto(grinder: current ?? grinder).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 14))
                PhotosPicker(selection: $photoItem, matching: .images) { Label("تغيير الصورة", systemImage: "photo") }
            }
            Section("الضبط") {
                Picker("الطريقة", selection: $adjustment) {
                    Text("غير محدد").tag(String?.none)
                    ForEach(RemoteGrinder.adjustments, id: \.self) { Text(RemoteGrinder.adjustmentAr($0)).tag(Optional($0)) }
                }
                HStack {
                    TextField("من", text: $rangeMin).keyboardType(.decimalPad)
                    Text("–")
                    TextField("إلى", text: $rangeMax).keyboardType(.decimalPad)
                }
                TextField("كليكات في اللفة (اختياري)", text: $clicksPerRotation).keyboardType(.numberPad)
                TextField("ميكرون لكل كليك (من الشركة فقط)", text: $micronsPerStep).keyboardType(.decimalPad)
            }
            Section("وين الصفر؟") { TextField("خطوات إيجاد الصفر", text: $zeroGuide, axis: .vertical).lineLimit(2...6) }
            Section("ملاحظات") { TextField("اختياري", text: $notes, axis: .vertical).lineLimit(1...5) }
            Section {
                ForEach(sources, id: \.self) { s in
                    VStack(alignment: .leading) { Text(s.label); Text(s.url).font(.caption2).foregroundStyle(.secondary) }
                }
                .onDelete { sources.remove(atOffsets: $0) }
                TextField("اسم المصدر (مثل: دليل الشركة)", text: $newSourceLabel)
                TextField("https://", text: $newSourceURL).keyboardType(.URL).textInputAutocapitalization(.never)
                Button("أضف المصدر") {
                    sources.append(.init(label: newSourceLabel.trimmingCharacters(in: .whitespaces),
                                         url: newSourceURL.trimmingCharacters(in: .whitespaces)))
                    newSourceLabel = ""; newSourceURL = ""
                }
                .disabled(newSourceLabel.trimmingCharacters(in: .whitespaces).isEmpty || URL(string: newSourceURL)?.scheme?.hasPrefix("http") != true)
            } header: { Text("المصادر") } footer: { Text("كل رقم فوق لازم يكون له مصدر من الشركة أو دليلها.") }
            Section { Toggle("ظاهرة في الدليل", isOn: $published).tint(Brand.olive) }
            if let message { Section { Text(message).foregroundStyle(Brand.olive) } }
        }
        .navigationTitle("\(grinder.brand) \(grinder.title)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("حفظ") { Task { await save() } }.disabled(isSaving) }
        }
        .onAppear(perform: fill)
        .onChange(of: photoItem) { _, item in if let item { Task { await upload(item) } } }
    }

    private func fill() {
        let g = current ?? grinder
        adjustment = g.adjustment
        rangeMin = g.rangeMin.map { Self.text($0) } ?? ""
        rangeMax = g.rangeMax.map { Self.text($0) } ?? ""
        clicksPerRotation = g.clicksPerRotation.map(String.init) ?? ""
        micronsPerStep = g.micronsPerStep.map { Self.text($0) } ?? ""
        zeroGuide = g.zeroGuideAr ?? ""
        notes = g.notesAr ?? ""
        sources = g.sources
        published = g.published
    }

    private static func text(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }

    private static func number(_ s: String) -> Any {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")).map { $0 as Any } ?? NSNull()
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        func text(_ s: String) -> Any { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? NSNull() : s }
        let body: [String: Any] = [
            "adjustment": adjustment.map { $0 as Any } ?? NSNull(),
            "rangeMin": Self.number(rangeMin), "rangeMax": Self.number(rangeMax),
            "clicksPerRotation": Int(clicksPerRotation.trimmingCharacters(in: .whitespaces)).map { $0 as Any } ?? NSNull(),
            "micronsPerStep": Self.number(micronsPerStep),
            "zeroGuideAr": text(zeroGuide), "notesAr": text(notes),
            "sources": sources.map { ["label": $0.label, "url": $0.url] },
            "published": published,
        ]
        do {
            let saved = try await auth.withToken { try await client.updateGrinder(id: grinder.id, changes: body, accessToken: $0) }
            current = saved
            onSaved(saved)
            message = "انحفظت"
        } catch {
            message = "ما انحفظت. تأكد من الأرقام والروابط."
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let card = await BagCutout.process(image, background: .white, enhance: false)?.image ?? image
        guard let jpeg = card.jpegData(compressionQuality: 0.85) else { return }
        do {
            let saved = try await auth.withToken { try await client.replaceGrinderPhoto(id: grinder.id, jpeg: jpeg, accessToken: $0) }
            current = saved
            onSaved(saved)
            message = "تغيّرت الصورة"
        } catch {
            message = "ما قدرنا نرفع الصورة"
        }
    }
}

import BunnListCore
import PhotosUI
import SwiftUI
import UIKit

/// Suggest a brand-new coffee for review (approved mockup): photographing the bag comes first and fills the
/// rest from the label; the roaster is recognised when we have it; «ممكن تقصد…؟» offers the coffee if it's
/// already in the guide (add it with one tap instead); origin, process and flavours are buttons, not typing.
/// Submitted as a pending suggestion.
struct SuggestCoffeeView: View {
    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss

    @State private var suggestion: CoffeeSuggestion
    @State private var flavorText: String
    @State private var photo: UIImage?
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var submitted = false
    @State private var photoMessage: String?
    @State private var photoUploadFailed = false
    @State private var readMessage: String?
    @State private var isReading = false
    @State private var roasters: [RemoteRoasterCard] = []
    @State private var maybe: RemoteLot?
    @State private var addedExisting = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    /// `productPhoto` must already be a background-removed cut-out; raw photos are never uploaded.
    init(prefillName: String = "", scanned: RemoteBagExtraction? = nil, productPhoto: UIImage? = nil) {
        let start = scanned.map(CoffeeSuggestion.init(scanned:)) ?? CoffeeSuggestion(name: prefillName)
        _suggestion = State(initialValue: start)
        _flavorText = State(initialValue: start.flavorNotes.joined(separator: "، "))
        _photo = State(initialValue: productPhoto)
    }

    var body: some View {
        NavigationStack {
            if submitted { successView } else { form }
        }
    }

    private var form: some View {
        Form {
            Section {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFit()
                        .frame(height: 180).frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                    Button("إزالة الصورة", role: .destructive) { self.photo = nil }
                }
                if let photoMessage {
                    Label(photoMessage, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                }
                if isReading {
                    HStack(spacing: 8) { ProgressView(); Text("نقرا الكيس…").font(.caption).foregroundStyle(.secondary) }
                } else if let readMessage {
                    Label(readMessage, systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(Brand.olive)
                }
                Button { showCamera = true } label: { Label("صوّر الكيس ونعبّي الباقي", systemImage: "camera") }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("اختر صورة", systemImage: "photo.on.rectangle")
                }
            } header: {
                Text("ابدأ بصورة الكيس (اختياري)")
            } footer: {
                Text("نقرا الاسم والمحمصة والمنشأ والنكهات من الملصق وانت تراجع. نفصل الكيس عن الخلفية على جوالك ونرفع صورة المنتج فقط.")
            }

            if let maybe {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ممكن تقصد «\(maybe.nameAr)» من \(maybe.roasterNameAr)؟").font(.subheadline.bold()).foregroundStyle(Brand.gold)
                        Text("موجودة في الدليل. أضفها لمجموعتك بدل ما تقترحها من جديد.").font(.caption).foregroundStyle(.secondary)
                        Button(addedExisting ? "انضافت لمجموعتك ✓" : "هي هذي، أضفها") { Task { await addExisting(maybe) } }
                            .buttonStyle(.borderedProminent).tint(Brand.gold).disabled(addedExisting)
                    }
                }
            }

            Section("اسم القهوة") {
                TextField("بالعربي", text: $suggestion.name)
                TextField("بالإنجليزي كما على الكيس", text: $suggestion.nameEn)
                    .environment(\.layoutDirection, .leftToRight)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

            Section {
                TextField("بالعربي", text: $suggestion.roasterName)
                TextField("بالإنجليزي كما على الكيس", text: $suggestion.roasterNameEn)
                    .environment(\.layoutDirection, .leftToRight)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                if let known = knownRoaster {
                    Button { suggestion.roasterName = known.nameAr; if suggestion.roasterNameEn.isEmpty { suggestion.roasterNameEn = known.name } } label: {
                        Label(known.nameAr == suggestion.roasterName.trimmingCharacters(in: .whitespaces) ? "\(known.nameAr) · موجودة عندنا" : "تقصد \(known.nameAr)؟ موجودة عندنا",
                              systemImage: "checkmark.seal.fill")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(Brand.olive)
                }
            } header: {
                Text("المحمصة")
            }

            Section("التفاصيل") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("المنشأ").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Self.origins, id: \.code) { o in
                                chip("\(ReferenceCodes.flag(o.code) ?? "") \(o.nameAr)", on: suggestion.originName == o.nameAr) {
                                    suggestion.originName = suggestion.originName == o.nameAr ? "" : o.nameAr
                                }
                            }
                        }
                    }
                    TextField("أو اكتب المنشأ", text: $suggestion.originName)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("المعالجة").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chip("غير محددة", on: suggestion.process == nil) { suggestion.process = nil }
                            ForEach(ReferenceCodes.processes, id: \.code) { entry in
                                chip(entry.nameAr, on: suggestion.process == entry.code) { suggestion.process = entry.code }
                            }
                        }
                    }
                }
                Picker("التحميص", selection: $suggestion.roastLevel) {
                    Text("غير محدد").tag(RoastLevel?.none)
                    ForEach(RoastLevel.allCases, id: \.self) { Text($0.nameAr).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 6) {
                    Text("النكهات").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Self.commonNotes, id: \.self) { note in
                                let picked = CoffeeSuggestion.notes(from: flavorText).contains(note)
                                chip(note, on: picked) { toggleNote(note) }
                            }
                        }
                    }
                    TextField("أو اكتبها مفصولة بفاصلة", text: $flavorText, axis: .vertical).lineLimit(1...3)
                }
            }

            Section("ملاحظة للمراجعة (اختياري)") {
                TextField("أي تفاصيل تساعد المراجعة…", text: $suggestion.note, axis: .vertical).lineLimit(2...6)
            }

            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
            }

            Section {
                Button("أرسل الاقتراح") { Task { await submit() } }
                    .disabled(!suggestion.isComplete || isBusy)
                    .accessibilityIdentifier("suggest-submit")
            }
        }
        .brandScreen()
        .navigationTitle("اقترح قهوة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
        .disabled(isBusy)
        .overlay { if isBusy { ProgressView() } }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(onImage: { data in
                showCamera = false
                if let image = UIImage(data: data) { Task { await setPhoto(image) } }
            }, onCancel: { showCamera = false })
            .ignoresSafeArea()
        }
        .task { await loadRoasters() }
        // «ممكن تقصد…؟»: once there's a name, look for it in the guide.
        .task(id: suggestion.name + "|" + suggestion.roasterName) { await lookForExisting() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await setPhoto(image)
                }
                photoItem = nil
            }
        }
    }

    private var successView: some View {
        ContentUnavailableView {
            Label("تم إرسال اقتراحك", systemImage: "checkmark.seal.fill")
        } description: {
            Text(photoUploadFailed
                 ? "شكرًا لمساهمتك! وصل الاقتراح لكن الصورة ما انرفعت، تقدر ترسلها لاحقًا."
                 : "شكرًا لمساهمتك! نراجع القهوة ونضيفها للدليل، ويوصلك إشعار لما تنضاف.")
        } actions: {
            Button("تم") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }

    /// Keeps only the bag, lifted out of its background. When that fails the raw photo
    /// is dropped (it may show people or places), and we ask for a cleaner shot.
    private func setPhoto(_ image: UIImage) async {
        photoMessage = nil
        Task { await read(image) }
        if let result = await BagCutout.process(image, enhance: false) {
            photo = result.image
            if !result.issues.isEmpty {
                photoMessage = result.issues.map(\.messageAr).joined(separator: " ") + " تقدر تعيد التصوير أو تكمّل بهذي."
            }
        } else {
            photo = nil
            photoMessage = "ما قدرنا نفصل الكيس عن الخلفية. صوّره على خلفية سادة بإضاءة جيدة، أو أرسل بدون صورة."
        }
    }

    // MARK: Helpers

    private static let origins: [(code: String, nameAr: String)] = [
        ("ET", "إثيوبيا"), ("CO", "كولومبيا"), ("BR", "البرازيل"), ("KE", "كينيا"), ("YE", "اليمن"),
        ("PA", "بنما"), ("CR", "كوستاريكا"), ("SV", "السلفادور"), ("RW", "رواندا"), ("ID", "إندونيسيا"),
    ]
    private static let commonNotes = ["توت", "ياسمين", "حمضيات", "كراميل", "شوكولاتة", "مكسرات", "خوخ", "فواكه استوائية", "عسل", "زهور"]

    private var knownRoaster: RemoteRoasterCard? {
        let typed = suggestion.roasterName.trimmingCharacters(in: .whitespaces)
        let typedEn = suggestion.roasterNameEn.trimmingCharacters(in: .whitespaces).lowercased()
        guard typed.count >= 2 || typedEn.count >= 2 else { return nil }
        func core(_ s: String) -> String { s.replacingOccurrences(of: "محمصة", with: "").trimmingCharacters(in: .whitespaces) }
        return roasters.first { r in
            (typed.count >= 2 && (core(r.nameAr) == core(typed) || r.nameAr.contains(core(typed)) && core(typed).count >= 3))
                || (typedEn.count >= 3 && r.name.lowercased().contains(typedEn))
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(on ? Brand.olive : Brand.background, in: Capsule())
                .foregroundStyle(on ? .white : Brand.ink)
        }
        .buttonStyle(.plain)
    }

    private func toggleNote(_ note: String) {
        var notes = CoffeeSuggestion.notes(from: flavorText)
        if let i = notes.firstIndex(of: note) { notes.remove(at: i) } else { notes.append(note) }
        flavorText = notes.joined(separator: "، ")
    }

    private func loadRoasters() async {
        roasters = (try? await client.fetchRoasters(accessToken: nil))?.roasters ?? []
    }

    /// Reads the label and fills the fields still empty, so nothing typed is overwritten.
    private func read(_ image: UIImage) async {
        guard auth.isSignedIn, let jpeg = AIBagScanView.compressed(image) else { return }
        isReading = true
        defer { isReading = false }
        guard let result = try? await auth.withToken({ try await client.scanBag(jpeg: jpeg, accessToken: $0) }) else { return }
        let read = CoffeeSuggestion(scanned: result.extraction)
        if suggestion.name.isEmpty { suggestion.name = read.name }
        if suggestion.nameEn.isEmpty { suggestion.nameEn = read.nameEn }
        if suggestion.roasterName.isEmpty { suggestion.roasterName = read.roasterName }
        if suggestion.roasterNameEn.isEmpty { suggestion.roasterNameEn = read.roasterNameEn }
        if suggestion.originName.isEmpty { suggestion.originName = read.originName }
        if suggestion.process == nil { suggestion.process = read.process }
        if suggestion.roastLevel == nil { suggestion.roastLevel = read.roastLevel }
        if flavorText.isEmpty { flavorText = read.flavorNotes.joined(separator: "، ") }
        if let match = result.matches.first { maybe = match }
        readMessage = "قرينا الكيس، راجع وعدّل إذا لزم"
    }

    private func lookForExisting() async {
        let name = suggestion.name.trimmingCharacters(in: .whitespaces)
        guard name.count >= 3, maybe == nil || maybe?.nameAr != name else { return }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, let found = try? await client.searchLots(query: name) else { return }
        let roaster = suggestion.roasterName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "محمصة", with: "").trimmingCharacters(in: .whitespaces)
        maybe = found.first { roaster.isEmpty || $0.roasterNameAr.contains(roaster) } ?? maybe
    }

    private func addExisting(_ lot: RemoteLot) async {
        guard auth.isSignedIn else { errorMessage = "سجّل الدخول من «ملفي» لإضافة القهوة."; return }
        do {
            _ = try await auth.withToken {
                try await client.updateCollectionFlags(slug: lot.slug, accessToken: $0, owned: true, favorite: false, wantsToTry: false, tried: false)
            }
            addedExisting = true
            Haptics.tap()
        } catch {
            errorMessage = "تعذّرت الإضافة. حاول مجددًا."
        }
    }

    private func submit() async {
        guard auth.isSignedIn else {
            errorMessage = "سجّل الدخول من «ملفي» لإرسال اقتراح."
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        var toSend = suggestion
        toSend.flavorNotes = CoffeeSuggestion.notes(from: flavorText)
        do {
            let id = try await auth.withToken { try await client.submitCoffee(toSend, accessToken: $0) }
            if let photo, let jpeg = AIBagScanView.compressed(photo) {
                do {
                    try await auth.withToken { try await client.uploadSuggestionPhoto(submissionID: id, jpeg: jpeg, accessToken: $0) }
                } catch {
                    photoUploadFailed = true
                }
            }
            Haptics.tap()
            submitted = true
        } catch APIError.unauthorized {
            errorMessage = "انتهت الجلسة. سجّل الدخول من جديد."
        } catch APIError.unprocessable {
            errorMessage = "تحقّق من البيانات (الاسم والمحمصة بالعربي مطلوبان)."
        } catch {
            errorMessage = "تعذّر الإرسال. حاول مجددًا."
        }
    }
}

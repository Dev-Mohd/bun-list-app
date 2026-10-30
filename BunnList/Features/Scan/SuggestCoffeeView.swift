import BunnListCore
import PhotosUI
import SwiftUI
import UIKit

/// Suggest a brand-new coffee for review: optional photo of the bag, the names in
/// Arabic and as printed in English, origin, process, roast and flavors. A bag
/// scan pre-fills everything. Submitted as a pending suggestion.
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
                Button { showCamera = true } label: { Label("صوّر الكيس", systemImage: "camera") }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("اختر صورة", systemImage: "photo.on.rectangle")
                }
            } header: {
                Text("صورة (اختياري)")
            } footer: {
                Text("نفصل الكيس عن الخلفية على جوالك ونرفع صورة المنتج فقط. صورة المنتج تُستخدم في دليل بُن لست.")
            }

            Section("اسم القهوة") {
                TextField("بالعربي", text: $suggestion.name)
                TextField("بالإنجليزي كما على الكيس", text: $suggestion.nameEn)
                    .environment(\.layoutDirection, .leftToRight)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

            Section("المحمصة") {
                TextField("بالعربي", text: $suggestion.roasterName)
                TextField("بالإنجليزي كما على الكيس", text: $suggestion.roasterNameEn)
                    .environment(\.layoutDirection, .leftToRight)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

            Section("التفاصيل") {
                TextField("المنشأ (اختياري)", text: $suggestion.originName)
                Picker("المعالجة", selection: $suggestion.process) {
                    Text("غير محددة").tag(String?.none)
                    ForEach(ReferenceCodes.processes, id: \.code) { entry in
                        Text(entry.nameEn.map { "\(entry.nameAr) · \($0)" } ?? entry.nameAr).tag(Optional(entry.code))
                    }
                }
                Picker("التحميص", selection: $suggestion.roastLevel) {
                    Text("غير محدد").tag(RoastLevel?.none)
                    ForEach(RoastLevel.allCases, id: \.self) { Text($0.nameAr).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                TextField("النكهات، افصل بفاصلة: شوكولاتة، كراميل", text: $flavorText, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section {
                TextField("وش رأيك فيها؟ وين لقيتها؟", text: $suggestion.publicNote, axis: .vertical).lineLimit(2...5)
                    .onChange(of: suggestion.publicNote) { _, text in
                        if text.count > 280 { suggestion.publicNote = String(text.prefix(280)) }
                    }
            } header: {
                Text("ملاحظة المكتشف (اختياري)")
            } footer: {
                Text("تظهر للجميع تحت اسمك في صفحة القهوة بعد نشرها.")
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
                 : "شكرًا لمساهمتك! سنراجع القهوة ونضيفها للدليل، ويظهر اسمك كمكتشف لها.")
        } actions: {
            Button("تم") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }

    /// Keeps only the bag, lifted out of its background. When that fails the raw photo
    /// is dropped (it may show people or places), and we ask for a cleaner shot.
    private func setPhoto(_ image: UIImage) async {
        photoMessage = nil
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

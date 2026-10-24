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

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    init(prefillName: String = "", scanned: RemoteBagExtraction? = nil, prefillPhoto: UIImage? = nil) {
        let start = scanned.map(CoffeeSuggestion.init(scanned:)) ?? CoffeeSuggestion(name: prefillName)
        _suggestion = State(initialValue: start)
        _flavorText = State(initialValue: start.flavorNotes.joined(separator: "، "))
        _photo = State(initialValue: prefillPhoto)
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
                }
                Button { showCamera = true } label: { Label("صوّر الكيس", systemImage: "camera") }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("اختر صورة", systemImage: "photo.on.rectangle")
                }
            } header: {
                Text("صورة (اختياري)")
            } footer: {
                Text("الصورة تساعد في المراجعة. (تُرفع للخادم في تحديث قادم.)")
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

            Section("ملاحظة (اختياري)") {
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
            Text("شكرًا لمساهمتك! سنراجع القهوة ونضيفها للدليل.")
        } actions: {
            Button("تم") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }

    /// Crops the bag out of a new photo when possible.
    private func setPhoto(_ image: UIImage) async {
        photo = await BagCutout.cardImage(from: image) ?? image
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
            _ = try await auth.withToken { try await client.submitCoffee(toSend, accessToken: $0) }
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

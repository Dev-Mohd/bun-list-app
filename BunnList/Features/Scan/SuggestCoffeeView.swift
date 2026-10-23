import BunnListCore
import PhotosUI
import SwiftUI
import UIKit

/// Suggest a brand-new coffee for review: optional photo of the bag + the basics.
/// Submitted to the server as a pending suggestion. (Image upload is a later step.)
struct SuggestCoffeeView: View {
    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss

    var prefillName: String = ""

    @State private var name = ""
    @State private var roasterName = ""
    @State private var origin = ""
    @State private var note = ""
    @State private var photo: UIImage?
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var submitted = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            if submitted { successView } else { form }
        }
        .onAppear { if name.isEmpty { name = prefillName } }
    }

    private var form: some View {
        Form {
            Section {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(height: 160).frame(maxWidth: .infinity).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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

            Section("البيانات") {
                TextField("اسم القهوة", text: $name)
                TextField("المحمصة", text: $roasterName)
                TextField("المنشأ (اختياري)", text: $origin)
            }

            Section("ملاحظة (اختياري)") {
                TextField("أي تفاصيل تساعد المراجعة…", text: $note, axis: .vertical).lineLimit(2...4)
            }

            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
            }

            Section {
                Button("أرسل الاقتراح") { Task { await submit() } }
                    .disabled(!canSubmit || isBusy)
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
                photo = UIImage(data: data)
            }, onCancel: { showCamera = false })
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self) { photo = UIImage(data: data) }
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

    private var canSubmit: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 2 && roasterName.trimmingCharacters(in: .whitespaces).count >= 2
    }

    private func submit() async {
        guard auth.isSignedIn, let token = auth.currentAccessToken() else {
            errorMessage = "سجّل الدخول من «ملفي» لإرسال اقتراح."
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let o = origin.trimmingCharacters(in: .whitespaces)
        let n = note.trimmingCharacters(in: .whitespaces)
        func send(_ t: String) async throws {
            _ = try await client.submitCoffee(name: name.trimmingCharacters(in: .whitespaces),
                                              roasterName: roasterName.trimmingCharacters(in: .whitespaces),
                                              originName: o.isEmpty ? nil : o,
                                              note: n.isEmpty ? nil : n, accessToken: t)
        }
        do {
            try await send(token)
            Haptics.tap()
            submitted = true
        } catch APIError.unauthorized {
            if let fresh = await auth.refreshAccessToken(), (try? await send(fresh)) != nil {
                submitted = true
            } else {
                errorMessage = "انتهت الجلسة. سجّل الدخول من جديد."
            }
        } catch APIError.unprocessable {
            errorMessage = "تحقّق من البيانات (الاسم والمحمصة مطلوبان)."
        } catch {
            errorMessage = "تعذّر الإرسال. حاول مجددًا."
        }
    }
}

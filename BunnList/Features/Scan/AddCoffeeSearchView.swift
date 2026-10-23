import BunnListCore
import PhotosUI
import SwiftUI
import UIKit

/// Find a real coffee on the server and add it to your collection. Opened from the
/// scan tab. (Suggesting a brand-new coffee is the next step.)
struct AddCoffeeSearchView: View {
    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [RemoteLot] = []
    @State private var searched = false
    @State private var isSearching = false
    @State private var added: Set<String> = []
    @State private var message: String?
    @State private var showSuggest = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var recognizedLines: [String] = []
    @State private var isReading = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            List {
                scanSection
                if let message {
                    Section { Label(message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
                }
                if isSearching {
                    Section { HStack { Spacer(); ProgressView(); Spacer() } }
                } else if searched && results.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("ما لقيناها", systemImage: "magnifyingglass")
                        } description: {
                            Text("جرّب اسمًا آخر، أو اقترحها كقهوة جديدة.")
                        } actions: {
                            Button("اقترح قهوة جديدة") { showSuggest = true }.buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    ForEach(results) { lot in
                        AddLotRow(lot: lot, isAdded: added.contains(lot.slug)) { Task { await add(lot) } }
                    }
                }
            }
            .navigationTitle("أضف قهوة")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "ابحث بالاسم أو المحمصة")
            .onSubmit(of: .search) { Task { await search() } }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView(onImage: { data in
                    showCamera = false
                    Task { await readImage(data) }
                }, onCancel: { showCamera = false })
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    if let data = try? await item.loadTransferable(type: Data.self) { await readImage(data) }
                    photoItem = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showSuggest = true } label: { Label("اقترح", systemImage: "plus") }
                        .accessibilityIdentifier("open-suggest")
                }
            }
            .sheet(isPresented: $showSuggest) {
                SuggestCoffeeView(prefillName: query.trimmingCharacters(in: .whitespacesAndNewlines))
                    .environmentObject(auth)
            }
        }
    }

    private var scanSection: some View {
        Section {
            Button { showCamera = true } label: { Label("صوّر الكيس", systemImage: "camera") }
                .accessibilityIdentifier("add-capture")
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("اختر صورة", systemImage: "photo.on.rectangle")
            }
            if isReading {
                HStack(spacing: 8) { ProgressView(); Text("نقرأ الكيس…").foregroundStyle(.secondary) }
            }
            if !recognizedLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("اضغط على نص لتبحث فيه:").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recognizedLines, id: \.self) { line in
                                Button(line) { query = line; Task { await search() } }
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Brand.olive.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Brand.olive)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("صوّر الكيس")
        } footer: {
            Text("نقرأ النص من صورة الكيس ونبحث فيه. (على المحاكي استخدم «اختر صورة».)")
        }
    }

    private func readImage(_ data: Data) async {
        isReading = true
        message = nil
        defer { isReading = false }
        let lines = await BagTextRecognizer.recognize(data)
        recognizedLines = lines
        if let first = lines.first {
            query = first
            await search()
        } else {
            message = "ما قدرنا نقرأ نصًا واضحًا. جرّب صورة أوضح أو ابحث يدويًا."
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        isSearching = true
        message = nil
        defer { isSearching = false }
        results = (try? await client.searchLots(query: q)) ?? []
        searched = true
    }

    private func add(_ lot: RemoteLot) async {
        guard auth.isSignedIn, let token = auth.currentAccessToken() else {
            message = "سجّل الدخول من «ملفي» لإضافة القهوة إلى مجموعتك."
            return
        }
        func put(_ t: String) async throws {
            _ = try await client.updateCollectionFlags(slug: lot.slug, accessToken: t,
                                                       owned: true, favorite: false, wantsToTry: false, tried: false)
        }
        do {
            try await put(token)
            added.insert(lot.slug)
            Haptics.tap()
        } catch APIError.unauthorized {
            if let fresh = await auth.refreshAccessToken(), (try? await put(fresh)) != nil {
                added.insert(lot.slug)
            } else {
                message = "انتهت الجلسة. سجّل الدخول من جديد."
            }
        } catch {
            message = "تعذّرت الإضافة. حاول مجددًا."
        }
    }
}

private struct AddLotRow: View {
    let lot: RemoteLot
    let isAdded: Bool
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(lot.nameAr).font(.headline)
                Text(lot.roasterNameAr).font(.subheadline).foregroundStyle(.secondary)
                if let origin = lot.originNameAr {
                    Label(origin, systemImage: "globe").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if isAdded {
                Label("أُضيفت", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Brand.olive)
            } else {
                Button("أضف", action: onAdd).buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

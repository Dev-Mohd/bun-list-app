import BunnListCore
import PhotosUI
import SwiftUI
import UIKit

/// Capture or pick → (demo) extraction → editable review → match → choose the season → collect.
struct ScanView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: AuthModel
    @State private var showServerSearch = false
    @State private var flow = ScanFlow()
    @State private var fields = ExtractedBagFields()
    @State private var entryState: ScanEntryState = .noCamera
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingBag: PendingBag?
    @State private var resultMessage: String?
    private let camera = CameraEnvironment.current()

    var body: some View {
        NavigationStack {
            Group {
                switch flow.phase {
                case .idle:
                    startView
                case .extracting:
                    extractingView
                case let .review(_, quality, isSample):
                    reviewView(quality: quality, isSample: isSample)
                case let .results(_, candidates):
                    resultsView(candidates)
                case .notFound:
                    notFoundView
                case .failed:
                    failedView
                }
            }
            .navigationTitle("مسح")
            .navigationDestination(for: ProductID.self) { ProductDetailView(productID: $0) }
            .sheet(isPresented: $showServerSearch) { AddCoffeeSearchView().environmentObject(auth) }
            .onAppear { entryState = camera.entryState }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView(onImage: { data in
                    showCamera = false
                    startExtraction(data)
                }, onCancel: { showCamera = false })
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    if let data = try? await item.loadTransferable(type: Data.self) { startExtraction(data) }
                    photoItem = nil
                }
            }
            .bagDecisionDialog($pendingBag) { finish($0) }
        }
    }

    // MARK: Start

    private var startView: some View {
        List {
            Section {
                Button { showServerSearch = true } label: {
                    Label("ابحث وأضف قهوة من الخادم", systemImage: "plus.magnifyingglass")
                }
                .accessibilityIdentifier("scan-server-search")
            } footer: {
                Text("ابحث في قهوة الخادم الحقيقية وأضفها لمجموعتك.")
            }
            Section {
                SampleBadge(text: "القراءة في هذه النسخة تجريبية: الصورة لا تُرسل ولا تُحفظ، والنتيجة موسومة.")
            }
            if let resultMessage {
                Section {
                    Label(resultMessage, systemImage: "checkmark.seal").foregroundStyle(Brand.olive)
                        .accessibilityIdentifier("scan-result")
                }
            }
            Section {
                cameraSection
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("اختر صورة", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("scan-pick-photo")
                Button {
                    resultMessage = nil
                    fields = ExtractedBagFields()
                    flow.beginManualEntry()
                } label: {
                    Label("إدخال يدوي", systemImage: "keyboard")
                }
                .accessibilityIdentifier("scan-manual")
            }
        }
    }

    @ViewBuilder
    private var cameraSection: some View {
        switch entryState {
        case .noCamera:
            VStack(alignment: .leading, spacing: 4) {
                Label("لا توجد كاميرا متاحة على هذا الجهاز", systemImage: "camera.badge.ellipsis")
                Text("اختر صورة أو أدخل البيانات يدويًا.").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("scan-no-camera")
        case .permissionDenied:
            VStack(alignment: .leading, spacing: 8) {
                Label("لم يُسمح باستخدام الكاميرا", systemImage: "camera.badge.ellipsis")
                Text("يمكنك اختيار صورة أو الإدخال يدويًا، أو السماح بالكاميرا من الإعدادات.")
                    .font(.caption).foregroundStyle(.secondary)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("افتح الإعدادات", destination: url)
                }
            }
            .accessibilityIdentifier("scan-permission-denied")
        case .needsPermission, .ready:
            Button {
                capture()
            } label: {
                Label("صوّر الكيس", systemImage: "camera")
            }
            .accessibilityIdentifier("scan-capture")
        }
    }

    private func capture() {
        resultMessage = nil
        if entryState == .needsPermission {
            Task { @MainActor in
                let granted = await camera.requestAccess()
                entryState = camera.entryState
                if granted, UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
            }
        } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCamera = true
        } else {
            entryState = .noCamera
        }
    }

    private func startExtraction(_ data: Data) {
        guard let catalog = model.catalog else { return }
        resultMessage = nil
        let token = flow.beginExtraction()
        let extractor = SampleBagExtractor(catalog: catalog, productID: ProductID("sample:product/guji"))
        Task { @MainActor in
            let result: Result<ExtractionResult, Error>
            do { result = .success(try await extractor.extract(imageData: data)) } catch { result = .failure(error) }
            if flow.receiveExtraction(result, token: token), case let .review(read, _, _) = flow.phase {
                fields = read
            }
        }
    }

    // MARK: Phases

    private var extractingView: some View {
        VStack(spacing: 16) {
            ProgressView("جارٍ القراءة…")
            Button("إلغاء", role: .cancel) { flow.cancel() }
                .accessibilityIdentifier("scan-cancel")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reviewView(quality: ExtractionQuality, isSample: Bool) -> some View {
        Form {
            if isSample {
                Section { SampleBadge(text: "نتيجة تجريبية — لم تُقرأ الصورة فعليًا. راجع الحقول وعدّلها.") }
            }
            if quality == .weak {
                Section {
                    Label("القراءة ضعيفة. أعد التصوير أو أكمل الحقول يدويًا.", systemImage: "exclamationmark.triangle")
                }
            }
            Section {
                TextField("اسم المحصول", text: $fields.productName)
                    .accessibilityIdentifier("field-product")
                TextField("المحمصة", text: $fields.roasterName)
                    .accessibilityIdentifier("field-roaster")
            } header: {
                Text("مطلوب")
            } footer: {
                Text("الاسم والمحمصة حد أدنى للبحث.")
            }
            Section("اختياري") {
                TextField("المنشأ", text: $fields.originText)
                TextField("المعالجة", text: $fields.processText)
                TextField("الموسم كما يظهر على الكيس", text: $fields.seasonText)
            }
            Section {
                Button("ابحث في الدليل") {
                    if let catalog = model.catalog { try? flow.submitReview(fields, catalog: catalog) }
                }
                .disabled(!fields.hasMinimumFields)
                .accessibilityIdentifier("scan-search")
                Button("إلغاء", role: .cancel) { flow.cancel() }
            }
        }
    }

    private func resultsView(_ candidates: [ProductMatch]) -> some View {
        List {
            Section {
                Text("اختر المحصول المطابق ثم موسمه. إن لم يذكر الكيس الموسم فاختر «الموسم غير معروف».")
                    .font(.callout)
            }
            ForEach(candidates, id: \.product.id) { candidate in
                Section {
                    ForEach(candidate.lots) { lot in
                        Button {
                            collect(lot.id)
                        } label: {
                            HStack {
                                Text(LotText.season(lot))
                                Spacer(minLength: 8)
                                if model.entry(for: lot.id)?.isOwned == true {
                                    Text("في مجموعتك").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("scan-lot-\(lot.id.rawValue)")
                    }
                    NavigationLink("صفحة المحصول", value: candidate.product.id)
                } header: {
                    Text("\(candidate.product.nameAr) · \(model.catalog.map { LotText.roaster(candidate.product, in: $0) } ?? "")")
                }
            }
            Section {
                Button("ليس أيًّا منها — عدّل البيانات") { flow.editAgain(fields) }
                Button("إلغاء", role: .cancel) { flow.cancel() }
            }
        }
    }

    private var notFoundView: some View {
        ContentUnavailableView {
            Label("لم نجده في الدليل التجريبي", systemImage: "magnifyingglass")
        } description: {
            Text("اقتراح محصول جديد للمراجعة يحتاج حسابًا ويُتاح في مرحلة لاحقة. لم يُحفظ شيء.")
        } actions: {
            Button("عدّل البيانات") { flow.editAgain(fields) }.buttonStyle(.borderedProminent)
            Button("ابدأ من جديد") { flow.cancel() }
        }
        .accessibilityIdentifier("scan-not-found")
    }

    private var failedView: some View {
        ContentUnavailableView {
            Label("تعذّرت القراءة", systemImage: "exclamationmark.triangle")
        } description: {
            Text("أعد المحاولة أو أدخل البيانات يدويًا.")
        } actions: {
            Button("إدخال يدوي") { flow.editAgain(fields) }.buttonStyle(.borderedProminent)
            Button("ابدأ من جديد") { flow.cancel() }
        }
    }

    // MARK: Collect

    private func collect(_ lot: LotID) {
        let operationID = ClientID()
        switch model.collect(lot, operationID: operationID) {
        case let .done(outcome): finish(outcome)
        case let .needsDecision(conflict): pendingBag = PendingBag(lot: lot, conflict: conflict, operationID: operationID)
        case .failed: break
        }
    }

    private func finish(_ outcome: CollectOutcome) {
        switch outcome {
        case .collected: resultMessage = "أضيف إلى مجموعتك."
        case .alreadyOwned: resultMessage = "موجود في مجموعتك مسبقًا؛ لم يُضف مرة أخرى."
        case .transferredFromUnknown: resultMessage = "نُقل سجلك إلى الموسم المحدد."
        case .keptKnownSeason: resultMessage = "أبقينا سجلك بالموسم المعلوم."
        }
        flow.cancel()
    }
}

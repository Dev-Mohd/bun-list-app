import BunnListCore
import PhotosUI
import SwiftUI
import UIKit

/// AI bag scan: photograph (or pick) a coffee bag, the server has Claude read the
/// label, and we show what it found with matching coffees. If there is no match,
/// the reading pre-fills a coffee suggestion. The photo is not stored. This is the
/// scan tab; without the bag at hand, people can search by name or suggest a coffee.
@MainActor
struct AIBagScanView: View {
    /// As the scan tab (no close button) rather than a sheet.
    var embedded = false

    private enum Phase {
        case start
        case reading(UIImage)
        case result(UIImage, RemoteBagScanResult)
        case failed(String)
    }

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .start
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var suggestion: BagSuggestion?
    /// The bag lifted out of the photo, when the device could find it.
    @State private var cutout: UIImage?
    @State private var entryState: ScanEntryState = .noCamera
    @State private var showNameSearch = false
    @State private var showSuggestByHand = false
    @State private var showSignIn = false
    private let camera = CameraEnvironment.current()

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .start: startView
                case let .reading(image): readingView(image)
                case let .result(image, result): resultView(image, result)
                case let .failed(message): failedView(message)
                }
            }
            .brandScreen()
            .navigationTitle(embedded ? "مسح" : "امسح الكيس")
            .navigationBarTitleDisplayMode(embedded ? .large : .inline)
            .background(Brand.background.ignoresSafeArea())
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
                }
            }
            .onAppear { entryState = camera.entryState }
            .sheet(isPresented: $showNameSearch) { AddCoffeeSearchView().environmentObject(auth) }
            .sheet(isPresented: $showSuggestByHand) { SuggestCoffeeView().environmentObject(auth) }
            .sheet(isPresented: $showSignIn) { SignInView() }
            .navigationDestination(for: String.self) { LiveLotDetailView(slug: $0) }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView(onImage: { data in
                    showCamera = false
                    if let image = UIImage(data: data) { Task { await read(image) } }
                }, onCancel: { showCamera = false })
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await read(image)
                    }
                    photoItem = nil
                }
            }
            .sheet(item: $suggestion) { s in
                SuggestCoffeeView(scanned: s.extraction, productPhoto: s.photo)
                    .environmentObject(auth)
            }
        }
    }

    // MARK: Phases

    private var startView: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 56, weight: .light)).foregroundStyle(Brand.olive)
                        .frame(width: 110, height: 110)
                        .background(Brand.olive.opacity(0.1), in: Circle())
                    Text("صوّر واجهة الكيس").font(.title2.bold()).foregroundStyle(Brand.ink)
                    Text("نقرأ الاسم والمحمصة والمنشأ والمعالجة والنكهات، ونطلع لك القهوة من الدليل.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if auth.isSignedIn {
                        captureButtons
                    } else {
                        Button { showSignIn = true } label: {
                            Label("سجّل الدخول عشان تمسح", systemImage: "person.crop.circle")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent).tint(Brand.ink).clipShape(Capsule())
                        .accessibilityIdentifier("scan-sign-in")
                    }
                    Text("الصورة تُرسل للقراءة فقط ولا تُحفظ.").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(22)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))

                VStack(spacing: 10) {
                    Text("ما معك الكيس؟").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    otherWay("ابحث بالاسم وأضفها لمجموعتك", icon: "magnifyingglass", id: "scan-search-name") { showNameSearch = true }
                    otherWay("اقترح قهوة مو موجودة", icon: "plus.circle", id: "scan-suggest") {
                        if auth.isSignedIn { showSuggestByHand = true } else { showSignIn = true }
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var captureButtons: some View {
        switch entryState {
        case .needsPermission, .ready:
            Button { capture() } label: {
                Label("صوّر الكيس", systemImage: "camera.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent).tint(Brand.ink).clipShape(Capsule())
            .accessibilityIdentifier("ai-scan-camera")
        case .permissionDenied:
            VStack(spacing: 6) {
                Label("ما سمحت للتطبيق بالكاميرا", systemImage: "camera.badge.ellipsis").font(.subheadline)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("افتح الإعدادات", destination: url).font(.subheadline.bold())
                }
            }
            .accessibilityIdentifier("scan-permission-denied")
        case .noCamera:
            Label("ما فيه كاميرا متاحة، اختر صورة من الألبوم.", systemImage: "camera.badge.ellipsis")
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("scan-no-camera")
        }
        PhotosPicker(selection: $photoItem, matching: .images) {
            Label("اختر صورة من الألبوم", systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.bordered).tint(Brand.olive).clipShape(Capsule())
        .accessibilityIdentifier("scan-pick-photo")
    }

    private func otherWay(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(Brand.olive).frame(width: 30)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Brand.ink)
                Spacer()
                Image(systemName: "chevron.left").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func capture() {
        if entryState == .needsPermission {
            Task {
                let granted = await camera.requestAccess()
                entryState = camera.entryState
                if granted { showCamera = true }
            }
        } else {
            showCamera = true
        }
    }

    private func readingView(_ image: UIImage) -> some View {
        VStack(spacing: 20) {
            Image(uiImage: image).resizable().scaledToFit()
                .frame(maxHeight: 280).clipShape(RoundedRectangle(cornerRadius: 16))
            ProgressView()
            Text("نقرأ الكيس…").font(.headline)
            Text("عادةً تأخذ ثواني قليلة.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private func failedView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("ما قدرنا نقرأ الكيس", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("حاول مرة ثانية") { phase = .start }.buttonStyle(.borderedProminent)
        }
    }

    private func resultView(_ image: UIImage, _ result: RemoteBagScanResult) -> some View {
        let e = result.extraction
        return List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: 88, height: 88)
                        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.displayName ?? "بدون اسم واضح").font(.headline)
                        if let latin = e.name, latin != e.displayName {
                            Text(latin).font(.subheadline).environment(\.layoutDirection, .leftToRight)
                        }
                        if let roaster = e.displayRoaster {
                            Text(roaster).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let latin = e.roaster, latin != e.displayRoaster {
                            Text(latin).font(.caption).foregroundStyle(.secondary)
                        }
                        Label(confidenceText(e.confidence), systemImage: "sparkles")
                            .font(.caption).foregroundStyle(Brand.olive)
                    }
                }
            }

            if !e.isCoffeeBag {
                Section {
                    Label("الصورة ما تبدو كيس قهوة. جرّب تصوّر الواجهة بوضوح.", systemImage: "questionmark.circle")
                }
            } else {
                Section("وش قرأنا") {
                    fact("المنشأ", [e.originCountryAr ?? e.originCountry, e.region].compactMap { $0 }.joined(separator: " · "))
                    fact("المزرعة", e.farm)
                    fact("المنتج", e.producer)
                    fact("الصنف", e.varieties.isEmpty ? nil : e.varieties.joined(separator: "، "))
                    fact("المعالجة", e.process.flatMap { ReferenceCodes.process($0)?.nameAr } ?? e.processLabel)
                    fact("التحميص", e.roastLevel?.nameAr)
                    fact("تاريخ التحميص", e.roastDate.map { date in
                        e.daysSinceRoast().map { "\(date) (قبل \($0.formatted()) يوم)" } ?? date
                    })
                    fact("الارتفاع", e.altitudeMeters.map { "\($0.formatted()) م" })
                    fact("الوزن", e.weightGrams.map { "\($0.formatted()) غ" })
                    if !e.flavorNotesAr.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("النكهات").font(.caption).foregroundStyle(.secondary)
                            Text(e.flavorNotesAr.joined(separator: " • ")).font(.subheadline)
                        }
                    }
                }

                Section(result.matches.isEmpty ? "ما لقيناها في الدليل" : "هل هي وحدة من هذي؟") {
                    ForEach(result.matches) { lot in
                        NavigationLink(value: lot.slug) { LiveLotRow(lot: lot) }
                    }
                    Button {
                        suggestion = BagSuggestion(extraction: e, photo: cutout)
                    } label: {
                        Label(result.matches.isEmpty ? "اقترحها للإضافة" : "مو منهم؟ اقترحها للإضافة",
                              systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("ai-scan-suggest")
                }
            }

            Section {
                Button("امسح كيس ثاني") { phase = .start }
            } footer: {
                Text("باقي لك اليوم \(result.remainingToday.formatted()) مسح. القراءة بالذكاء الاصطناعي وقد تخطئ، راجعها.")
            }
        }
    }

    @ViewBuilder
    private func fact(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label, value: value)
        }
    }

    private func confidenceText(_ confidence: String) -> String {
        switch confidence {
        case "high": return "قراءة واضحة"
        case "medium": return "قراءة جزئية"
        default: return "قراءة ضعيفة، راجع البيانات"
        }
    }

    // MARK: Network

    private func read(_ image: UIImage) async {
        cutout = nil
        phase = .reading(image)
        guard let jpeg = Self.compressed(image) else {
            phase = .failed("تعذّر تجهيز الصورة.")
            return
        }
        do {
            let result = try await auth.withToken { try await client.scanBag(jpeg: jpeg, accessToken: $0) }
            Haptics.tap()
            phase = .result(image, result)
            // Lift the bag out of the photo for a clean card; only the cut-out is ever uploaded.
            if result.extraction.isCoffeeBag, let card = await BagCutout.cardImage(from: image),
               case .result(_, let current) = phase, current == result {
                cutout = card
                phase = .result(card, result)
            }
        } catch APIError.rateLimited {
            phase = .failed("وصلت حد المسح اليومي. جرّب بكرة.")
        } catch APIError.forbidden {
            phase = .failed("المسح الذكي غير مفعّل على الخادم بعد.")
        } catch APIError.unprocessable {
            phase = .failed("الصورة غير واضحة. صوّر الواجهة بإضاءة جيدة وبدون انعكاس.")
        } catch APIError.unauthorized {
            phase = .failed("انتهت الجلسة. سجّل الدخول من جديد.")
        } catch {
            phase = .failed("تعذّر الاتصال. تحقّق من الإنترنت وحاول مجددًا.")
        }
    }

    /// Longest side ≤ 1600 px, JPEG quality 0.8: sharp enough for small label text, small to upload.
    static func compressed(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

/// What the scan pre-fills into a coffee suggestion.
private struct BagSuggestion: Identifiable {
    let id = UUID()
    let extraction: RemoteBagExtraction
    let photo: UIImage?
}

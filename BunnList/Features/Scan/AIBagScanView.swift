import BunnListCore
import PhotosUI
import SwiftUI
import UIKit

/// AI bag scan: photograph (or pick) a coffee bag, the server has Claude read the
/// label, and we show what it found with matching coffees. If there is no match,
/// the reading pre-fills a coffee suggestion. The photo is not stored.
@MainActor
struct AIBagScanView: View {
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
            .navigationTitle("امسح الكيس")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
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
                SuggestCoffeeView(scanned: s.extraction, prefillPhoto: s.photo)
                    .environmentObject(auth)
            }
        }
    }

    // MARK: Phases

    private var startView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 64)).foregroundStyle(Brand.olive)
            Text("صوّر واجهة الكيس").font(.title2.bold())
            Text("يقرأ الذكاء الاصطناعي الاسم والمحمصة والمنشأ والمعالجة والنكهات وتاريخ التحميص، ويدوّر لك القهوة في الدليل.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if auth.isSignedIn {
                Button { showCamera = true } label: {
                    Label("صوّر الكيس", systemImage: "camera.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent).tint(.black)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                .accessibilityIdentifier("ai-scan-camera")
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("اختر صورة من الألبوم", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            } else {
                Text("سجّل الدخول من «ملفي» لاستخدام المسح الذكي.")
                    .font(.callout).foregroundStyle(.orange)
            }
            Text("الصورة تُرسل للقراءة فقط ولا تُحفظ.")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
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
                        suggestion = BagSuggestion(extraction: e, photo: image)
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
        phase = .reading(image)
        guard let jpeg = Self.compressed(image) else {
            phase = .failed("تعذّر تجهيز الصورة.")
            return
        }
        do {
            let result = try await auth.withToken { try await client.scanBag(jpeg: jpeg, accessToken: $0) }
            Haptics.tap()
            phase = .result(image, result)
            // Lift the bag out of the photo for a clean card; keep the original if that fails.
            if result.extraction.isCoffeeBag, let card = await BagCutout.cardImage(from: image),
               case .result(_, let current) = phase, current == result {
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
    let photo: UIImage
}

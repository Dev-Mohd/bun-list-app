import BunnListCore
import SwiftUI

/// Create/update the signed-in user's review for a lot and POST it to the server.
/// On a 401 it transparently refreshes the access token once and retries.
struct ReviewFormView: View {
    let slug: String
    let brewMethods: [String]
    let existing: RemoteMyReview?
    var onSaved: (RemoteReviewResult) -> Void

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss

    @State private var rating: Int
    @State private var brewMethod: String
    @State private var wouldBuyAgain: Bool
    @State private var note: String
    @State private var isBusy = false
    @State private var errorMessage: String?

    private let client = CatalogAPIClient(transport: URLSessionTransport())
    private static let allMethods = ["ESPRESSO", "V60", "CHEMEX", "AEROPRESS", "FRENCH_PRESS", "COLD_BREW", "OTHER"]

    init(slug: String, brewMethods: [String], existing: RemoteMyReview?, onSaved: @escaping (RemoteReviewResult) -> Void) {
        self.slug = slug
        self.brewMethods = brewMethods
        self.existing = existing
        self.onSaved = onSaved
        _rating = State(initialValue: existing?.rating ?? 0)
        _wouldBuyAgain = State(initialValue: existing?.wouldBuyAgain ?? true)
        _note = State(initialValue: existing?.body ?? "")
        let options = brewMethods.isEmpty ? Self.allMethods : brewMethods
        _brewMethod = State(initialValue: existing?.brewMethod ?? options.first ?? "V60")
    }

    private var methodOptions: [String] {
        var options = brewMethods.isEmpty ? Self.allMethods : brewMethods
        if let existingMethod = existing?.brewMethod, !options.contains(existingMethod) { options.insert(existingMethod, at: 0) }
        return options
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("تقييمك") {
                    starPicker
                }
                Section("طريقة التحضير") {
                    Picker("الطريقة", selection: $brewMethod) {
                        ForEach(methodOptions, id: \.self) { Text(LiveLotDetailView.brewLabel($0)).tag($0) }
                    }
                    Toggle("أشتريه مرة ثانية", isOn: $wouldBuyAgain)
                }
                Section("ملاحظة (اختياري)") {
                    TextField("اكتب تجربتك…", text: $note, axis: .vertical).lineLimit(3...6)
                }
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
                }
            }
            .brandScreen()
            .navigationTitle(existing == nil ? "إضافة تقييم" : "تعديل تقييمك")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { Task { await save() } }.disabled(rating < 1 || isBusy)
                }
            }
            .disabled(isBusy)
            .overlay { if isBusy { ProgressView() } }
        }
    }

    private var starPicker: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundStyle(Brand.olive)
                    .onTapGesture { rating = value }
                    .accessibilityIdentifier("review-star-\(value)")
            }
            Spacer()
        }
    }

    private func save() async {
        guard let token = auth.currentAccessToken() else {
            errorMessage = "سجّل الدخول أولًا."
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await submit(with: token, note: trimmed)
            onSaved(result)
            dismiss()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Submits once; on 401 refreshes the token and retries a single time.
    private func submit(with token: String, note: String) async throws -> RemoteReviewResult {
        do {
            return try await client.submitReview(slug: slug, accessToken: token, rating: rating,
                                                 brewMethod: brewMethod, wouldBuyAgain: wouldBuyAgain,
                                                 body: note.isEmpty ? nil : note)
        } catch APIError.unauthorized {
            guard let fresh = await auth.refreshAccessToken() else { throw APIError.unauthorized }
            return try await client.submitReview(slug: slug, accessToken: fresh, rating: rating,
                                                 brewMethod: brewMethod, wouldBuyAgain: wouldBuyAgain,
                                                 body: note.isEmpty ? nil : note)
        }
    }

    private static func message(for error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .unauthorized: return "انتهت الجلسة. سجّل الدخول من جديد ثم أعد المحاولة."
            case .rateLimited: return "محاولات كثيرة. انتظر قليلًا."
            case .unprocessable: return "تحقّق من بيانات التقييم."
            default: return "تعذّر حفظ التقييم. حاول مجددًا."
            }
        }
        return "تعذّر الاتصال بالخادم. تحقّق من اتصالك."
    }
}

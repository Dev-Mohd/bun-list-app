import BunnListCore
import SwiftUI

/// Admin-only review of coffee suggestions: pending first, then approved and
/// rejected. Opening one shows its product photo and an editable form; approving
/// publishes the lot with the author credited as its discoverer.
@MainActor
struct AdminReviewView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var status = "PENDING"
    @State private var items: [RemoteAdminSubmission]?
    @State private var errorMessage: String?

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        List {
            Section {
                Picker("الحالة", selection: $status) {
                    Text("بانتظار المراجعة").tag("PENDING")
                    Text("مقبولة").tag("APPROVED")
                    Text("مرفوضة").tag("REJECTED")
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            if let items {
                if items.isEmpty {
                    ContentUnavailableView("لا يوجد", systemImage: "tray", description: Text("ما فيه اقتراحات بهذي الحالة."))
                }
                ForEach(items) { item in
                    NavigationLink {
                        AdminSubmissionDetailView(submission: item) { Task { await load() } }
                    } label: {
                        AdminSubmissionRow(item: item)
                    }
                }
            } else if errorMessage == nil {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .navigationTitle("مراجعة الاقتراحات")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: status) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        errorMessage = nil
        do {
            items = try await auth.withToken { try await client.adminSubmissions(status: status, accessToken: $0) }
        } catch APIError.forbidden {
            errorMessage = "هذي الشاشة للأدمن فقط."
        } catch {
            errorMessage = "تعذّر تحميل الاقتراحات."
        }
    }
}

private struct AdminSubmissionRow: View {
    let item: RemoteAdminSubmission

    var body: some View {
        HStack(spacing: 12) {
            AdminPhoto(url: item.photoUrl).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.headline)
                Text(item.roasterName).font(.subheadline).foregroundStyle(.secondary)
                Text("من: \(item.authorName ?? "حساب محذوف")").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct AdminPhoto: View {
    let url: String?

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// One suggestion: photo, author, editable fields, approve / reject.
@MainActor
struct AdminSubmissionDetailView: View {
    let submission: RemoteAdminSubmission
    var onReviewed: () -> Void

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var form: ApprovalForm
    @State private var flavorText: String
    @State private var rejectReason = ""
    @State private var confirmReject = false
    @State private var isBusy = false
    @State private var message: String?
    @State private var approvedSlug: String?

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    init(submission: RemoteAdminSubmission, onReviewed: @escaping () -> Void) {
        self.submission = submission
        self.onReviewed = onReviewed
        let form = ApprovalForm(submission)
        _form = State(initialValue: form)
        _flavorText = State(initialValue: form.flavorNotes.joined(separator: "، "))
        _approvedSlug = State(initialValue: submission.approvedLotSlug)
    }

    private var isPending: Bool { submission.status == "PENDING" && approvedSlug == nil }

    var body: some View {
        Form {
            Section {
                AdminPhoto(url: submission.photoUrl).frame(height: 220)
                    .listRowInsets(EdgeInsets())
                LabeledContent("اقترحها", value: submission.authorName ?? "حساب محذوف")
                if let publicNote = submission.publicNote, !publicNote.isEmpty {
                    Label("للعموم: \(publicNote)", systemImage: "quote.bubble").font(.callout)
                }
                if let note = submission.note, !note.isEmpty {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("اسم القهوة") {
                TextField("بالعربي", text: $form.nameAr)
                TextField("بالإنجليزي (يُكتب تلقائيًا لو تركته)", text: $form.name)
                    .environment(\.layoutDirection, .leftToRight)
                    .autocorrectionDisabled()
            }
            Section("المحمصة") {
                TextField("بالعربي", text: $form.roasterNameAr)
                TextField("بالإنجليزي (يُكتب تلقائيًا لو تركته)", text: $form.roasterName)
                    .environment(\.layoutDirection, .leftToRight)
                    .autocorrectionDisabled()
            }
            Section("التفاصيل") {
                Picker("المنشأ", selection: originBinding) {
                    Text("اختر").tag(String?.none)
                    ForEach(ReferenceCodes.countries, id: \.code) { Text($0.nameAr).tag(Optional($0.code)) }
                }
                if form.originCode == nil, let typed = submission.originName, !typed.isEmpty {
                    Text("كتب المستخدم: \(typed)").font(.caption).foregroundStyle(.orange)
                }
                Picker("المعالجة", selection: $form.process) {
                    Text("اختر").tag(String?.none)
                    ForEach(ReferenceCodes.processes, id: \.code) { Text($0.nameAr).tag(Optional($0.code)) }
                }
                Picker("التحميص", selection: $form.roastLevel) {
                    Text("—").tag(RoastLevel?.none)
                    ForEach(RoastLevel.allCases, id: \.self) { Text($0.nameAr).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                TextField("النكهات، افصل بفاصلة", text: $flavorText, axis: .vertical)
                TextField("وصف (اختياري)", text: $form.descriptionAr, axis: .vertical).lineLimit(2...6)
            }

            if let message {
                Section { Text(message).foregroundStyle(approvedSlug == nil ? .red : Brand.olive) }
            }

            if isPending {
                Section {
                    Button {
                        Task { await approve() }
                    } label: {
                        Label("اعتماد ونشر في الدليل", systemImage: "checkmark.seal.fill")
                    }
                    .disabled(!form.missingFields.isEmpty || isBusy)
                    if !form.missingFields.isEmpty {
                        Text("ناقص: \(form.missingFields.joined(separator: "، "))").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("رفض", role: .destructive) { confirmReject = true }.disabled(isBusy)
                }
            } else if let slug = approvedSlug {
                Section {
                    NavigationLink("افتح صفحة القهوة") { LiveLotDetailView(slug: slug) }
                }
            } else if let reason = submission.reviewNote {
                Section("سبب الرفض") { Text(reason) }
            }
        }
        .navigationTitle(submission.name)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isBusy)
        .overlay { if isBusy { ProgressView() } }
        .alert("رفض الاقتراح", isPresented: $confirmReject) {
            TextField("السبب (يظهر للمستخدم)", text: $rejectReason)
            Button("رفض", role: .destructive) { Task { await reject() } }
            Button("إلغاء", role: .cancel) {}
        }
    }

    private var originBinding: Binding<String?> {
        Binding(
            get: { form.originCode },
            set: { code in
                form.originCode = code
                if let code, let entry = ReferenceCodes.country(code) { form.originNameAr = entry.nameAr }
            }
        )
    }

    private func approve() async {
        isBusy = true
        defer { isBusy = false }
        var toSend = form
        toSend.flavorNotes = CoffeeSuggestion.notes(from: flavorText)
        do {
            let slug = try await auth.withToken { try await client.approveSubmission(id: submission.id, form: toSend, accessToken: $0) }
            approvedSlug = slug
            message = "انضافت للدليل ✓"
            Haptics.tap()
            onReviewed()
        } catch APIError.conflict {
            message = "هذا الاقتراح انراجع من قبل."
        } catch APIError.unprocessable {
            message = "راجع الحقول (الأسماء والمنشأ والمعالجة)."
        } catch {
            message = "تعذّر الاعتماد. حاول مجددًا."
        }
    }

    private func reject() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.withToken { try await client.rejectSubmission(id: submission.id, reason: rejectReason, accessToken: $0) }
            onReviewed()
            dismiss()
        } catch {
            message = "تعذّر الرفض. حاول مجددًا."
        }
    }
}

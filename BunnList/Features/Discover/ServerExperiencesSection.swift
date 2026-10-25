import BunnListCore
import SwiftUI

/// "تجاربي" on a server lot: the signed-in user's brew experiences, synced with
/// /api/v1/catalog/lots/[slug]/experiences. Log a new one, edit, repeat a past one,
/// publish / unpublish, or delete (final). Experience stars rate the attempt only.
@MainActor
struct ServerExperiencesSection: View {
    let slug: String
    /// Called after a save, since logging a brew also marks the lot as tried.
    var onSaved: () -> Void = {}

    @EnvironmentObject private var auth: AuthModel
    @State private var experiences: [RemoteExperience] = []
    @State private var editing: ExperienceDraft?
    @State private var pendingDelete: RemoteExperience?
    @State private var errorMessage: String?

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    init(slug: String, onSaved: @escaping () -> Void = {}) {
        self.slug = slug
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                editing = ExperienceDraft()
            } label: {
                Label("سجّل تجربة تحضير", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Brand.olive)
            .accessibilityIdentifier("server-add-experience")

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }

            ForEach(experiences) { experience in
                ServerExperienceRow(experience: experience) {
                    actions(for: experience)
                }
            }
        }
        .task { await load() }
        .sheet(item: $editing) { draft in
            ServerExperienceEditor(draft: draft) { saved in
                upsertLocally(saved)
                onSaved()
            } save: { draft, publish in
                try await withToken { token in
                    try await client.saveExperience(
                        slug: slug, accessToken: token, clientID: draft.clientID,
                        methodCode: draft.methodCode, stars: draft.stars,
                        brewedAt: draft.brewedAt, note: draft.note, publish: publish)
                }
            }
        }
        .confirmationDialog("حذف التجربة؟", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("حذف نهائيًا", role: .destructive) {
                if let target = pendingDelete { Task { await change(target, to: .deleted) } }
            }
        } message: {
            Text("لا يمكن التراجع عن الحذف.")
        }
    }

    @ViewBuilder
    private func actions(for experience: RemoteExperience) -> some View {
        Button { editing = ExperienceDraft(editing: experience) } label: { Label("تعديل", systemImage: "pencil") }
        Button { editing = ExperienceDraft(repeating: experience) } label: { Label("كرّر هذه التجربة", systemImage: "arrow.clockwise") }
        switch experience.state {
        case .draft, .unpublished:
            Button { Task { await change(experience, to: .published) } } label: { Label("نشر", systemImage: "paperplane") }
        case .published:
            Button { Task { await change(experience, to: .unpublished) } } label: { Label("إلغاء النشر", systemImage: "eye.slash") }
        case .deleted:
            EmptyView()
        }
        Button(role: .destructive) { pendingDelete = experience } label: { Label("حذف", systemImage: "trash") }
    }

    private func load() async {
        guard auth.isSignedIn else { experiences = []; return }
        if let list = try? await withToken({ try await client.fetchMyExperiences(slug: slug, accessToken: $0) }) {
            experiences = list
        }
    }

    private func change(_ experience: RemoteExperience, to state: RemoteExperience.State) async {
        errorMessage = nil
        do {
            let updated = try await withToken {
                try await client.changeExperienceState(id: experience.id, to: state, accessToken: $0)
            }
            Haptics.tap()
            if updated.state == .deleted {
                experiences.removeAll { $0.id == updated.id }
            } else {
                upsertLocally(updated)
            }
        } catch {
            errorMessage = "تعذّر تحديث التجربة. حاول مجددًا."
        }
    }

    private func upsertLocally(_ saved: RemoteExperience) {
        if let index = experiences.firstIndex(where: { $0.id == saved.id }) {
            experiences[index] = saved
        } else {
            experiences.insert(saved, at: 0)
        }
        experiences.sort { ($0.brewedDate ?? .distantPast) > ($1.brewedDate ?? .distantPast) }
    }

    /// Runs `call` with the access token; on 401 refreshes once and retries.
    private func withToken<T>(_ call: (String) async throws -> T) async throws -> T {
        guard let token = auth.currentAccessToken() else { throw APIError.unauthorized }
        do {
            return try await call(token)
        } catch APIError.unauthorized {
            guard let fresh = await auth.refreshAccessToken() else { throw APIError.unauthorized }
            return try await call(fresh)
        }
    }
}

/// Editor input. A new or repeated experience gets a fresh clientID (a new record);
/// editing keeps the original clientID so the server updates it in place.
struct ExperienceDraft: Identifiable {
    let id = UUID()
    var clientID = UUID().uuidString
    var methodCode = "V60"
    var stars = 0
    var brewedAt = Date()
    var note = ""
    /// Set when editing an existing experience.
    var existingState: RemoteExperience.State?

    init() {}

    init(editing experience: RemoteExperience) {
        clientID = experience.clientId
        methodCode = experience.methodCode
        stars = experience.stars
        brewedAt = experience.brewedDate ?? Date()
        note = experience.note
        existingState = experience.state
    }

    /// Same method and note as a past brew, dated today, rated afresh.
    init(repeating experience: RemoteExperience) {
        methodCode = experience.methodCode
        note = experience.note
    }
}

private struct ServerExperienceRow<Actions: View>: View {
    let experience: RemoteExperience
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(ReferenceCodes.brewMethod(experience.methodCode)?.nameAr ?? experience.methodCode)
                        .font(.subheadline.weight(.semibold))
                    StarsDisplay(value: experience.stars).font(.caption2)
                }
                HStack(spacing: 6) {
                    if let date = experience.brewedDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                    }
                    Text("· \(stateLabel)")
                }
                .font(.caption).foregroundStyle(.secondary)
                if !experience.note.isEmpty {
                    Text(experience.note).font(.callout)
                }
            }
            Spacer(minLength: 0)
            Menu { actions() } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Brand.olive)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("خيارات التجربة")
            .accessibilityIdentifier("server-experience-menu-\(experience.clientId)")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var stateLabel: String {
        switch experience.state {
        case .draft: return "مسودة"
        case .published: return "منشورة"
        case .unpublished: return "غير منشورة"
        case .deleted: return "محذوفة"
        }
    }
}

/// Sheet to log or edit a server experience: method, the attempt's stars, date, note.
private struct ServerExperienceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExperienceDraft
    @State private var isBusy = false
    @State private var errorMessage: String?
    let onSaved: (RemoteExperience) -> Void
    let save: (ExperienceDraft, Bool) async throws -> RemoteExperience

    init(draft: ExperienceDraft,
         onSaved: @escaping (RemoteExperience) -> Void,
         save: @escaping (ExperienceDraft, Bool) async throws -> RemoteExperience) {
        _draft = State(initialValue: draft)
        self.onSaved = onSaved
        self.save = save
    }

    /// A published or unpublished experience keeps its state on edit.
    private var isDraft: Bool { draft.existingState == nil || draft.existingState == .draft }

    var body: some View {
        NavigationStack {
            Form {
                Section("الطريقة") {
                    Picker("الطريقة", selection: $draft.methodCode) {
                        ForEach(ReferenceCodes.brewMethods, id: \.code) { Text($0.nameAr).tag($0.code) }
                    }
                }
                Section("تقييم هذه التجربة") {
                    StarRatingControl(value: draft.stars, label: "نجوم التجربة") { draft.stars = $0 }
                    Text("نجوم التجربة لهذا التحضير، ولا تدخل في متوسط تقييم المحصول.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Section("التفاصيل") {
                    DatePicker("التاريخ", selection: $draft.brewedAt, in: ...Date(), displayedComponents: .date)
                    TextField("ملاحظة: الطحنة، النسبة، الطعم…", text: $draft.note, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("server-experience-note")
                }
                if isDraft {
                    Section {
                        Button("حفظ كمسودة") { Task { await submit(publish: false) } }
                            .disabled(draft.stars < 1 || isBusy)
                            .accessibilityIdentifier("server-experience-save-draft")
                    } footer: {
                        Text("المسودة تبقى لك وحدك حتى تنشرها.")
                    }
                }
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
                }
            }
            .brandScreen()
            .navigationTitle(draft.existingState == nil ? "تجربة تحضير" : "تعديل التجربة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isDraft ? "نشر" : "حفظ") { Task { await submit(publish: isDraft) } }
                        .disabled(draft.stars < 1 || isBusy)
                        .accessibilityIdentifier("server-experience-publish")
                }
            }
            .disabled(isBusy)
            .overlay { if isBusy { ProgressView() } }
        }
    }

    private func submit(publish: Bool) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        var clean = draft
        clean.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let saved = try await save(clean, publish)
            Haptics.tap()
            onSaved(saved)
            dismiss()
        } catch APIError.unauthorized {
            errorMessage = "انتهت الجلسة. سجّل الدخول من جديد ثم أعد المحاولة."
        } catch APIError.conflict {
            errorMessage = "هذه التجربة حُذفت ولا يمكن تعديلها."
        } catch {
            errorMessage = "تعذّر حفظ التجربة. تحقّق من اتصالك وحاول مجددًا."
        }
    }
}

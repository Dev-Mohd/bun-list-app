import BunnListCore
import SwiftUI

/// Notifications, two ways: «الآن» pushes one to everyone, to recent users, or to
/// your own phone first; «متكرر» keeps a list the server sends one at a time every
/// few days. People who turned off "أخبار التطبيق" get neither.
@MainActor
struct AdminBroadcastView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var title = ""
    @State private var message = ""
    @State private var audience: BroadcastAudience = .test
    @State private var info: RemoteBroadcasts?
    @State private var isSending = false
    @State private var confirm = false
    @State private var result: String?
    @State private var mode = Mode.now

    enum Mode: String, CaseIterable, Identifiable {
        case now, repeating
        var id: String { rawValue }
        var titleAr: String { self == .now ? "الآن" : "متكرر" }
    }
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var ready: Bool {
        title.trimmingCharacters(in: .whitespaces).count >= 2 && message.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("الطريقة", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.titleAr).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.vertical, 8)
            if mode == .now { sendNow } else { AdminRotationView(fill: { t, b in title = t; message = b; mode = .now }) }
        }
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("الإشعارات")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("ترسل لـ\(label(audience))؟", isPresented: $confirm, titleVisibility: .visible) {
            Button("أرسل") { Task { await send() } }
        } message: {
            Text("ما تقدر تتراجع بعد الإرسال. جرّبه على جوالك أول إذا ما جربته.")
        }
    }

    private var sendNow: some View {
        Form {
            Section {
                TextField("العنوان", text: $title).onChange(of: title) { _, v in if v.count > 60 { title = String(v.prefix(60)) } }
                TextField("النص", text: $message, axis: .vertical).lineLimit(2...5)
                    .onChange(of: message) { _, v in if v.count > 200 { message = String(v.prefix(200)) } }
            } footer: {
                Text("\(message.count)/200")
            }

            if ready { Section("كذا بيطلع") { preview } }

            Section("لمين؟") {
                Picker("الجمهور", selection: $audience) {
                    ForEach(BroadcastAudience.allCases) { a in Text(label(a)).tag(a) }
                }
                .pickerStyle(.inline).labelsHidden()
            }

            Section {
                Button {
                    if audience == .test { Task { await send() } } else { confirm = true }
                } label: {
                    Label(isSending ? "نرسل…" : (audience == .test ? "أرسل تجربة لجوالي" : "أرسل"), systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Brand.olive)
                .disabled(!ready || isSending)
                .listRowBackground(Color.clear)
                if let result { Label(result, systemImage: "info.circle").foregroundStyle(Brand.olive) }
            }

            if let history = info?.history, !history.isEmpty {
                Section("المرسلة") {
                    ForEach(history) { h in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.title).font(.subheadline.bold())
                            Text(h.body).font(.caption).foregroundStyle(.secondary)
                            Text("\(BroadcastAudience(rawValue: h.audience)?.nameAr ?? h.audience) · وصل \(h.delivered.formatted()) جهاز · \(AdminUserDetailView.date(h.createdAt))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func label(_ a: BroadcastAudience) -> String {
        switch a {
        case .test: return a.nameAr
        case .active30: return info.map { "\(a.nameAr) (\($0.audiences.active30.formatted()))" } ?? a.nameAr
        case .all: return info.map { "\(a.nameAr) (\($0.audiences.all.formatted()))" } ?? a.nameAr
        }
    }

    private var preview: some View {
        HStack(alignment: .top, spacing: 10) {
            Image("IconPreview-Classic").resizable().scaledToFit().frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(message).font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func load() async {
        info = try? await auth.withToken { try await client.adminBroadcasts(accessToken: $0) }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            let r = try await auth.withToken {
                try await client.sendBroadcast(title: title, body: message, audience: audience, accessToken: $0)
            }
            result = "انرسل لـ\(r.accounts.formatted()) حساب، ووصل \(r.delivered.formatted()) جهاز"
            if audience != .test { title = ""; message = "" }
            await load()
        } catch APIError.forbidden {
            result = "الإشعارات مو مفعّلة في السيرفر (مفاتيح APNs ناقصة في Vercel)"
        } catch {
            result = "ما انرسل. حاول مرة ثانية."
        }
    }
}

/// «متكرر»: the list the server works through, one message every few days, then
/// round again. Edits stay on the phone until «حفظ».
@MainActor
struct AdminRotationView: View {
    /// Copies a message into «الآن» to try it on your own phone.
    var fill: (String, String) -> Void

    @EnvironmentObject private var auth: AuthModel
    @State private var rotation: RemoteRotation?
    @State private var knownIDs: Set<String> = []
    @State private var saved: RemoteRotation?
    @State private var failed = false
    @State private var isSaving = false
    @State private var note: String?
    @State private var editing: RemoteRotation.Item?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var changed: Bool { rotation != saved }

    var body: some View {
        Group {
            if rotation != nil { form } else if failed {
                ContentUnavailableView("ما قدرنا نجيب القائمة", systemImage: "wifi.slash",
                                       description: Text("تأكد أن السيرفر محدّث، واسحب للتحديث."))
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editing) { item in
            RotationItemEditor(item: item) { edited in
                guard var r = rotation else { return }
                if let i = r.items.firstIndex(where: { $0.id == edited.id }) { r.items[i] = edited } else { r.items.append(edited) }
                rotation = r
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                Toggle("شغّال", isOn: Binding(get: { rotation?.enabled ?? false }, set: { rotation?.enabled = $0 })).tint(Brand.olive)
                Stepper(value: Binding(get: { rotation?.everyDays ?? 2 }, set: { rotation?.everyDays = $0 }), in: 1...30) {
                    Text(everyLabel(rotation?.everyDays ?? 2))
                }
                Picker("لمين؟", selection: Binding(get: { rotation?.audience ?? "all" }, set: { rotation?.audience = $0 })) {
                    Text(BroadcastAudience.all.nameAr).tag("all")
                    Text(BroadcastAudience.active30.nameAr).tag("active30")
                }
            } footer: {
                Text(status)
            }

            Section {
                ForEach(rotation?.items ?? []) { item in
                    Button { editing = item } label: { row(item) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button("جرّبه") { fill(item.title, item.body) }.tint(Brand.olive)
                        }
                }
                .onDelete { rotation?.items.remove(atOffsets: $0) }
                .onMove { rotation?.items.move(fromOffsets: $0, toOffset: $1) }
                Button { editing = RemoteRotation.Item(id: "local-\(UUID().uuidString)", title: "", body: "") } label: {
                    Label("رسالة جديدة", systemImage: "plus")
                }
                if rotation?.items.isEmpty == true {
                    Button { addTemplates() } label: { Label("ابدأ بالرسائل الجاهزة", systemImage: "sparkles") }
                }
            } header: {
                HStack {
                    Text("الرسائل بالترتيب")
                    Spacer()
                    if (rotation?.items.count ?? 0) > 1 { EditButton().font(.caption) }
                }
            } footer: {
                Text("اضغط على الرسالة لتعديلها، واسحبها يمين عشان تجرّبها على جوالك من «الآن».")
            }

            if let note { Section { Label(note, systemImage: "info.circle").foregroundStyle(Brand.olive) } }

            Section {
                Button { Task { await save() } } label: {
                    Text(isSaving ? "نحفظ…" : (changed ? "حفظ" : "محفوظ")).font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Brand.olive)
                .disabled(!changed || isSaving)
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ item: RemoteRotation.Item) -> some View {
        let isNext = rotation?.enabled == true && saved?.nextItemId == item.id
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title).font(.subheadline.bold())
                    if isNext {
                        Text("الجاية").font(.caption2.bold()).foregroundStyle(Brand.gold)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Brand.gold.opacity(0.14), in: Capsule())
                    }
                }
                Text(item.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if item.sentCount > 0 {
                    Text("انرسلت \(item.sentCount.formatted()) مرة\(item.lastSentAt.map { " · آخرها " + AdminUserDetailView.date($0) } ?? "")")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if !item.enabled { Image(systemName: "pause.circle.fill").foregroundStyle(.secondary).accessibilityLabel("موقوفة") }
        }
        .opacity(item.enabled ? 1 : 0.55)
        .contentShape(Rectangle())
    }

    private func everyLabel(_ days: Int) -> String {
        switch days {
        case 1: return "كل يوم"
        case 2: return "كل يومين"
        case 3...10: return "كل \(days) أيام"
        default: return "كل \(days) يوم"
        }
    }

    private var status: String {
        guard let saved else { return "" }
        if !saved.enabled { return "موقّف. ما ينرسل شي لين تشغّله وتحفظ." }
        if saved.items.allSatisfy({ !$0.enabled }) { return "شغّال بس القائمة فاضية." }
        let next = saved.nextRunAt.map { AdminUserDetailView.date($0) } ?? "قريب"
        return "الرسالة الجاية: \(next)، حوالي الساعة ٦ المغرب بتوقيت الرياض."
    }

    private func addTemplates() {
        rotation?.items = BroadcastTemplates.all.map { RemoteRotation.Item(id: "local-\(UUID().uuidString)", title: $0.title, body: $0.body) }
    }

    private func load() async {
        do {
            let r = try await auth.withToken { try await client.adminRotation(accessToken: $0) }
            rotation = r
            saved = r
            knownIDs = Set(r.items.map(\.id))
            failed = false
        } catch {
            failed = rotation == nil
        }
    }

    private func save() async {
        guard let rotation else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let r = try await auth.withToken { try await client.saveRotation(rotation, knownIDs: knownIDs, accessToken: $0) }
            self.rotation = r
            saved = r
            knownIDs = Set(r.items.map(\.id))
            note = r.enabled ? "انحفظت، والتكرار شغّال." : "انحفظت. التكرار موقّف."
        } catch {
            note = "ما انحفظت. حاول مرة ثانية."
        }
    }
}

/// One repeating message: title, text, and whether it's in the round.
@MainActor
private struct RotationItemEditor: View {
    @State var item: RemoteRotation.Item
    var onDone: (RemoteRotation.Item) -> Void
    @Environment(\.dismiss) private var dismiss

    private var ready: Bool {
        item.title.trimmingCharacters(in: .whitespaces).count >= 2 && item.body.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("العنوان", text: $item.title)
                        .onChange(of: item.title) { _, v in if v.count > 60 { item.title = String(v.prefix(60)) } }
                    TextField("النص", text: $item.body, axis: .vertical).lineLimit(2...5)
                        .onChange(of: item.body) { _, v in if v.count > 200 { item.body = String(v.prefix(200)) } }
                } footer: {
                    Text("\(item.body.count)/200")
                }
                Section {
                    Toggle("ضمن التكرار", isOn: $item.enabled).tint(Brand.olive)
                } footer: {
                    Text("وقّفها إذا ما تبيها تنرسل الحين، وتبقى في القائمة.")
                }
            }
            .navigationTitle("رسالة متكررة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { onDone(item); dismiss() }.disabled(!ready)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

import SwiftUI
import BunnListCore

/// One coffee's photo: lift the backdrop (with a sensitivity), crop, keep the
/// backdrop, compare before and after, save, bring the original back, or delete.
/// The cut runs on the server with plain pixel arithmetic; nothing is generated.
@MainActor
struct PhotoToolsView: View {
    let card: RemoteQueueCard
    let currentURL: String?
    /// Whether the original is kept to bring back (the card's flag, or edited in this session).
    let hasOriginal: Bool
    /// The new photo's URL (nil when deleted).
    var onSaved: (String?) -> Void

    enum Side: String { case before, after }

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var edit = PhotoEdit()
    @State private var top = 0.0, bottom = 0.0, left = 0.0, right = 0.0
    @State private var side = Side.after
    @State private var preview: RemotePhotoPreview?
    @State private var previewImage: UIImage?
    @State private var loading = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var crop: PhotoCrop { PhotoCrop(top: top, bottom: bottom, leading: left, trailing: right) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $side) {
                    Text("قبل").tag(Side.before)
                    Text("بعد").tag(Side.after)
                }
                .pickerStyle(.segmented)

                photo
                    .frame(height: 320)
                    .frame(maxWidth: .infinity)
                    .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 16))

                if let warning = preview?.warningAr, side == .after {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("شيل الخلفية", isOn: $edit.removeBackground).tint(Brand.olive)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("الحساسية").font(.subheadline.bold())
                            Spacer()
                            Text(Int(edit.sensitivity).formatted()).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Slider(value: $edit.sensitivity, in: 0...100, step: 5) {
                            Text("الحساسية")
                        } minimumValueLabel: {
                            Text("أقل").font(.caption)
                        } maximumValueLabel: {
                            Text("أكثر").font(.caption)
                        }
                        .tint(Brand.olive)
                        Text("لو أكلت من الكيس خفّفها، ولو بقى شي من الخلفية زِدها.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .disabled(!edit.removeBackground)
                    .opacity(edit.removeBackground ? 1 : 0.4)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("القص").font(.subheadline.bold())
                        Spacer()
                        if top + bottom + left + right > 0 {
                            Button("بدون قص") { top = 0; bottom = 0; left = 0; right = 0 }.font(.caption)
                        }
                    }
                    cropSlider("من فوق", $top)
                    cropSlider("من تحت", $bottom)
                    cropSlider("من اليمين", $right)
                    cropSlider("من اليسار", $left)
                    Text("شوف المربع على صورة «قبل»، وخلّ الكيس داخله.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                if let error { Text(error).font(.footnote).foregroundStyle(.red) }

                VStack(spacing: 10) {
                    Button { Task { await apply() } } label: {
                        Label("احفظ الصورة", systemImage: "checkmark").font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Brand.olive, in: Capsule()).foregroundStyle(Brand.background)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || currentURL == nil && !hasOriginal)
                    HStack(spacing: 10) {
                        if card.kind == .submission, hasOriginal {
                            Button { Task { await restore() } } label: {
                                Label("رجّع الأصل", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered).tint(Brand.ink)
                        }
                        if currentURL != nil {
                            Button(role: .destructive) { confirmDelete = true } label: {
                                Label("احذف الصورة", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .disabled(busy)
                }
            }
            .padding()
        }
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("أدوات الصورة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
        .confirmationDialog("تحذف صورة «\(card.name)»؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("احذف الصورة", role: .destructive) { Task { await delete() } }
        } message: {
            Text(card.kind == .submission ? "تقدر ترجّع الأصل بعدين." : "القهوة المنشورة تصير بدون صورة.")
        }
        // A new preview a moment after the last change.
        .task(id: PreviewKey(edit: edit, crop: crop)) {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await loadPreview()
        }
    }

    private struct PreviewKey: Equatable { let edit: PhotoEdit; let crop: PhotoCrop }

    @ViewBuilder private var photo: some View {
        switch side {
        case .before:
            if let url = currentURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit().overlay { cropOverlay }
                } placeholder: { ProgressView() }
                .padding(8)
            } else {
                ContentUnavailableView("بدون صورة", systemImage: "photo")
            }
        case .after:
            ZStack {
                if let previewImage {
                    Image(uiImage: previewImage).resizable().scaledToFit().padding(8)
                } else if !loading {
                    ContentUnavailableView("ما فيه معاينة", systemImage: "photo")
                }
                if loading { ProgressView().controlSize(.large) }
            }
        }
    }

    /// The part the crop keeps, drawn over the "before" photo.
    private var cropOverlay: some View {
        GeometryReader { geo in
            let c = crop
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.35)
                    .mask {
                        Rectangle().overlay(alignment: .topLeading) {
                            Rectangle().frame(width: geo.size.width * c.w, height: geo.size.height * c.h)
                                .offset(x: geo.size.width * c.x, y: geo.size.height * c.y)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                Rectangle().stroke(Brand.olive, lineWidth: 2)
                    .frame(width: geo.size.width * c.w, height: geo.size.height * c.h)
                    .offset(x: geo.size.width * c.x, y: geo.size.height * c.y)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .allowsHitTesting(false)
    }

    private func cropSlider(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 70, alignment: .leading)
            Slider(value: value, in: 0...0.45, step: 0.01).tint(Brand.ink)
            Text("\(Int(value.wrappedValue * 100))٪").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36)
        }
    }

    private func current() -> PhotoEdit {
        var e = edit
        e.crop = crop
        return e
    }

    private func loadPreview() async {
        guard currentURL != nil || hasOriginal else { return }
        loading = true
        defer { loading = false }
        do {
            let p = try await auth.withToken { try await client.previewPhoto(card, current(), accessToken: $0) }
            preview = p
            previewImage = p.imageData.flatMap(UIImage.init(data:))
            error = nil
        } catch {
            preview = nil
            previewImage = nil
            self.error = "ما قدرنا نشيل الخلفية بهالإعدادات. جرّب حساسية ثانية أو قص الصورة."
        }
    }

    private func apply() async {
        busy = true
        defer { busy = false }
        do {
            let url = try await auth.withToken { try await client.applyPhoto(card, current(), accessToken: $0) }
            Haptics.tap()
            onSaved(url)
            dismiss()
        } catch {
            self.error = "ما انحفظت الصورة. حاول مرة ثانية."
        }
    }

    private func restore() async {
        busy = true
        defer { busy = false }
        do {
            let url = try await auth.withToken { try await client.restorePhoto(card, accessToken: $0) }
            onSaved(url)
            dismiss()
        } catch {
            self.error = "ما رجعت الصورة الأصلية."
        }
    }

    private func delete() async {
        busy = true
        defer { busy = false }
        do {
            try await auth.withToken { try await client.deletePhoto(card, accessToken: $0) }
            onSaved(nil)
            dismiss()
        } catch {
            self.error = "ما انحذفت الصورة."
        }
    }
}

/// The same origin, process, roast or extra notes for every selected coffee.
@MainActor
struct BulkEditSheet: View {
    let kind: RemoteQueueCard.Kind
    let ids: [String]
    var onDone: (Int) -> Void

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var edit = BulkEdit()
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        Form {
            Section {
                Text("اللي تختاره هنا ينحط على \(ids.count.formatted()) قهوة. اللي تخليه فاضي ما يتغيّر.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("المنشأ") {
                Picker("المنشأ", selection: $edit.originCode) {
                    Text("بدون تغيير").tag(String?.none)
                    ForEach(ReferenceCodes.countries.filter { $0.code != "XB" }, id: \.code) { Text($0.nameAr).tag(String?.some($0.code)) }
                }
            }
            Section("المعالجة") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ReferenceCodes.processes.filter { $0.code != "OTHER" }, id: \.code) { p in
                            ChoiceChip(title: p.nameAr, isSelected: edit.process == p.code) {
                                edit.process = edit.process == p.code ? nil : p.code
                            }
                        }
                    }
                }
            }
            Section("التحميص") {
                HStack(spacing: 6) {
                    ForEach(RoastLevel.allCases, id: \.self) { r in
                        ChoiceChip(title: r.nameAr, isSelected: edit.roastLevel == r) {
                            edit.roastLevel = edit.roastLevel == r ? nil : r
                        }
                    }
                }
            }
            Section {
                ForEach(edit.addNotes, id: \.self) { n in Text(n) }
                    .onDelete { edit.addNotes.remove(atOffsets: $0) }
                HStack {
                    TextField("نكهة", text: $note).onSubmit(addNote)
                    Button("إضافة", action: addNote).disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("أضف نكهات")
            } footer: {
                Text("تنضاف على نكهات كل قهوة، ما تمسح اللي فيها.")
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("تعديل جماعي")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if busy { ProgressView() } else {
                    Button("طبّق") { Task { await save() } }.disabled(edit.isEmpty)
                }
            }
        }
    }

    private func addNote() {
        let n = note.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !edit.addNotes.contains(n), edit.addNotes.count < 6 else { return }
        edit.addNotes.append(n)
        note = ""
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            var updated = 0
            for start in stride(from: 0, to: ids.count, by: 200) {
                let chunk = Array(ids[start..<min(start + 200, ids.count)])
                updated += try await auth.withToken { try await client.bulkEdit(kind, ids: chunk, edit, accessToken: $0) }
            }
            Haptics.tap()
            onDone(updated)
            dismiss()
        } catch {
            self.error = "ما انحفظ التعديل. حاول مرة ثانية."
        }
    }
}

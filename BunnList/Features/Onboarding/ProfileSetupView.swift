import BunnListCore
import PhotosUI
import SwiftUI

/// Set up (first run) or edit the public profile: picture, name, @username and a
/// short bio. On first run the username comes pre-filled with a free suggestion.
@MainActor
struct ProfileSetupView: View {
    enum Mode { case firstRun, edit }

    let mode: Mode
    var onDone: () -> Void

    @EnvironmentObject private var auth: AuthModel
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var pickedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var check: RemoteUsernameCheck?
    @State private var isChecking = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var loaded = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var candidate: String { UsernameRules.normalize(username) }
    private var currentUsername: String? { profile.me?.username }
    private var usernameProblem: UsernameProblem? {
        if let local = UsernameRules.problem(candidate) { return local }
        if candidate == currentUsername { return nil }
        guard check?.username == candidate else { return nil }
        return check?.available == true ? nil : (check?.problem ?? .taken)
    }
    private var usernameReady: Bool {
        UsernameRules.problem(candidate) == nil && (candidate == currentUsername || (check?.username == candidate && check?.available == true))
    }
    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty && usernameReady && !isSaving
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if mode == .firstRun {
                    VStack(spacing: 8) {
                        Text("خلّنا نجهّز ملفك").font(.title.bold())
                        Text("هذا اللي يشوفه الناس على وصفاتك وتقييماتك والقهوة اللي تكتشفها.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)
                }

                PhotosPicker(selection: $photoItem, matching: .images) {
                    AvatarView(url: profile.me?.avatarUrl, image: pickedImage, name: displayName, size: 112)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.callout).foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Brand.olive, in: Circle())
                                .overlay(Circle().stroke(Brand.background, lineWidth: 3))
                        }
                }
                .accessibilityLabel("اختر صورة الملف")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Brand.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 24))

                field("الاسم") {
                    TextField("اسمك كما تحب يظهر", text: $displayName)
                        .textContentType(.name)
                        .onChange(of: displayName) { _, v in if v.count > ProfileRules.maxDisplayName { displayName = String(v.prefix(ProfileRules.maxDisplayName)) } }
                } footer: {
                    EmptyView()
                }

                field("اسم المستخدم") {
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                        Spacer(minLength: 4)
                        statusIcon
                    }
                    .environment(\.layoutDirection, .leftToRight)
                } footer: {
                    if let usernameProblem {
                        Text(usernameProblem.messageAr).foregroundStyle(.orange)
                    } else if usernameReady && candidate != currentUsername {
                        Text("متاح ✓").foregroundStyle(Brand.olive)
                    } else {
                        Text("حروف إنجليزية صغيرة وأرقام و _ و .").foregroundStyle(.secondary)
                    }
                }

                field("نبذة") {
                    TextField("مثال: أحب الإثيوبي المجفف على V60", text: $bio, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: bio) { _, v in if v.count > ProfileRules.maxBio { bio = String(v.prefix(ProfileRules.maxBio)) } }
                } footer: {
                    Text("\(bio.count.formatted())/\(ProfileRules.maxBio.formatted())").foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
                }
            }
            .padding()
        }
        .background(Brand.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button { Task { await save() } } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text(mode == .firstRun ? "التالي" : "حفظ")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(canSave ? Brand.olive : Color.secondary.opacity(0.4), in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .accessibilityIdentifier("profile-save")
                if mode == .firstRun {
                    Button("لاحقًا") { onDone() }.font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle(mode == .firstRun ? "" : "عدّل ملفك")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode == .edit {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
        }
        .task { await prefill() }
        .task(id: candidate) { await checkAvailability() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    pickedImage = image
                }
                photoItem = nil
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isChecking { ProgressView().controlSize(.small) }
        else if usernameProblem != nil { Image(systemName: "xmark.circle.fill").foregroundStyle(.orange) }
        else if usernameReady { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.olive) }
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View,
                       @ViewBuilder footer: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            footer().font(.caption)
        }
    }

    private func prefill() async {
        guard !loaded else { return }
        loaded = true
        if profile.me == nil { await profile.refresh(auth) }
        displayName = profile.me?.displayName ?? ""
        bio = profile.me?.bio ?? ""
        if let existing = profile.me?.username {
            username = existing
        } else if let suggestion = try? await auth.withToken({ try await client.suggestUsername(accessToken: $0) }) {
            username = suggestion
        }
    }

    private func checkAvailability() async {
        guard UsernameRules.problem(candidate) == nil, candidate != currentUsername else { return }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        isChecking = true
        defer { isChecking = false }
        let name = candidate
        if let result = try? await auth.withToken({ try await client.checkUsername(name, accessToken: $0) }), name == candidate {
            check = result
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if candidate != currentUsername {
                let name = candidate
                _ = try await auth.withToken { try await client.setUsername(name, accessToken: $0) }
            }
            let name = displayName.trimmingCharacters(in: .whitespaces)
            let about = bio.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await auth.withToken { try await client.updateProfile(displayName: name, bio: about, accessToken: $0) }
            if let pickedImage, let jpeg = AvatarImage.jpeg(from: pickedImage) {
                do {
                    _ = try await auth.withToken { try await client.uploadAvatar(jpeg: jpeg, accessToken: $0) }
                } catch {
                    errorMessage = "انحفظ ملفك، لكن الصورة ما انرفعت. جرّب لاحقًا."
                }
            }
            await profile.refresh(auth)
            Haptics.tap()
            if errorMessage == nil {
                if mode == .edit { dismiss() }
                onDone()
            }
        } catch APIError.conflict {
            check = RemoteUsernameCheck(username: candidate, available: false, problem: .taken)
        } catch {
            errorMessage = "تعذّر الحفظ. تحقّق من اتصالك وحاول مجددًا."
        }
    }
}

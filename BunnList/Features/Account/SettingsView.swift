import BunnListCore
import SwiftUI

/// App settings: preferences, session, about, and the danger zone. Reached from the
/// gear button in the profile tab.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthModel
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("continuedAsGuest") private var continuedAsGuest = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section("التفضيلات") {
                    Toggle(isOn: $hapticsEnabled) {
                        Label("الاهتزاز", systemImage: "hand.tap")
                    }
                    LabeledContent {
                        Text("العربية").foregroundStyle(.secondary)
                    } label: {
                        Label("اللغة", systemImage: "globe")
                    }
                }

                if auth.isSignedIn {
                    Section {
                        Toggle(isOn: hideBinding) {
                            Label("اخفني من المتصدرين", systemImage: "eye.slash")
                        }
                    } header: {
                        Text("الخصوصية")
                    } footer: {
                        Text("تبقى نقاطك وسلسلتك لك، بس اسمك ما يطلع في قائمة المتصدرين.")
                    }

                    Section("الحساب") {
                        Button("تسجيل الخروج") { auth.signOut() }
                    }
                }

                Section {
                    Button {
                        auth.signOut()
                        continuedAsGuest = false
                        dismiss()
                    } label: {
                        Label("العودة لشاشة الترحيب", systemImage: "arrow.uturn.backward")
                    }
                } footer: {
                    Text("تخرج من الحساب (إن كنت مسجّلًا) وترجع لشاشة البداية.")
                }

                Section("عن التطبيق") {
                    LabeledContent("الإصدار", value: versionText)
                    Text("بن لست — اكتشف القهوة، بطاقة بطاقة.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                if auth.isSignedIn {
                    Section("منطقة خطر") {
                        Button("حذف الحساب", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("settings-delete")
                    }
                }
            }
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
            .confirmationDialog("حذف الحساب نهائيًا؟", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("حذف الحساب", role: .destructive) { Task { await auth.deleteAccount(); dismiss() } }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("سيُحذف حسابك وبياناته على الخادم نهائيًا. لا يمكن التراجع.")
            }
        }
    }

    private var hideBinding: Binding<Bool> {
        Binding(
            get: { profile.me?.hideFromLeaderboard ?? false },
            set: { hide in
                Task {
                    let client = CatalogAPIClient(transport: URLSessionTransport())
                    _ = try? await auth.withToken {
                        try await client.updateProfile(displayName: nil, bio: nil, hideFromLeaderboard: hide, accessToken: $0)
                    }
                    await profile.refresh(auth)
                }
            }
        )
    }

    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }
}

import SwiftUI

/// App settings: preferences, session, about, and the danger zone. Reached from the
/// gear button in the profile tab.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthModel
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

    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }
}

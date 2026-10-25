import BunnListCore
import SwiftUI

/// "الإشعارات": the iPhone permission, then which notifications to get. Server
/// notifications are per account; the streak reminder lives on this phone.
@MainActor
struct NotificationSettingsView: View {
    @EnvironmentObject private var auth: AuthModel
    @ObservedObject private var push = PushManager.shared
    @AppStorage(PushManager.streakKey) private var streakReminder = false
    @State private var settings: RemoteNotificationSettings?
    @State private var failed = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var allowed: Bool { push.status == .authorized || push.status == .provisional || push.status == .ephemeral }

    var body: some View {
        List {
            Section {
                switch push.status {
                case .notDetermined:
                    Button {
                        Task { await push.requestPermission() }
                    } label: {
                        Label("فعّل الإشعارات", systemImage: "bell.badge")
                    }
                    .accessibilityIdentifier("enable-notifications")
                case .denied:
                    VStack(alignment: .leading, spacing: 6) {
                        Label("الإشعارات مقفلة من إعدادات الجوال", systemImage: "bell.slash")
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("افتح الإعدادات", destination: url).font(.subheadline.bold())
                        }
                    }
                default:
                    Label("الإشعارات مفعّلة", systemImage: "bell.fill").foregroundStyle(Brand.olive)
                }
            } footer: {
                Text("توصلك تحديثات عن رحلتك مع القهوة. تقدر تختار وش يوصلك تحت.")
            }

            if auth.isSignedIn {
                Section("اجتماعي") {
                    toggle("متابع جديد", "أحد صار يتابعك", icon: "person.badge.plus", \.newFollower)
                }
                Section("اقتراحاتك") {
                    toggle("انقبل اقتراحك", "قهوة اقترحتها صارت في الدليل", icon: "checkmark.seal.fill", \.submissionApproved)
                    toggle("ما انقبل اقتراحك", "مع سبب الرفض إن وُجد", icon: "xmark.seal", \.submissionRejected)
                }
                if failed {
                    Section { Label("تعذّر تحميل إعداداتك", systemImage: "wifi.exclamationmark").foregroundStyle(.secondary) }
                }
            } else {
                Section { Text("سجّل الدخول عشان تختار إشعارات حسابك.").foregroundStyle(.secondary) }
            }

            Section {
                Toggle(isOn: $streakReminder) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("تذكير السلسلة")
                            Text("الساعة ٨ مساءً إذا ما فتحت التطبيق ذاك اليوم").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "flame.fill") }
                }
                .disabled(!allowed)
                .onChange(of: streakReminder) { _, _ in push.scheduleStreakReminder() }
            } header: {
                Text("تذكيرات")
            }
        }
        .brandScreen()
        .navigationTitle("الإشعارات")
        .task {
            await push.refreshStatus()
            await load()
        }
    }

    private func toggle(_ title: String, _ subtitle: String, icon: String,
                        _ key: WritableKeyPath<RemoteNotificationSettings, Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { settings?[keyPath: key] ?? true },
            set: { value in
                guard var updated = settings else { return }
                updated[keyPath: key] = value
                settings = updated
                Task { await save(updated) }
            }
        )) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: icon) }
        }
        .disabled(settings == nil || !allowed)
    }

    private func load() async {
        guard auth.isSignedIn else { return }
        do {
            settings = try await auth.withToken { try await client.fetchNotificationSettings(accessToken: $0) }
        } catch {
            failed = true
        }
    }

    private func save(_ updated: RemoteNotificationSettings) async {
        if let saved = try? await auth.withToken({ try await client.saveNotificationSettings(updated, accessToken: $0) }) {
            settings = saved
        } else {
            await load() // back to what the server has
        }
    }
}

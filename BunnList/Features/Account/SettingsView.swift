import BunnListCore
import SwiftUI

/// App settings: preferences, session, about, and the danger zone. Reached from the
/// gear button in the profile tab.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthModel
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var tipsReset = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("appearance") private var appearance = AppAppearance.system
    @AppStorage("continuedAsGuest") private var continuedAsGuest = false
    @State private var confirmDelete = false
    /// Shown right away while the change saves.
    @State private var pendingVisibility: [PrivacyPart: ProfileVisibility] = [:]
    @State private var pendingPrivate: Bool?
    @State private var showRecipes = false

    var body: some View {
        NavigationStack {
            List {
                Section("التفضيلات") {
                    Picker(selection: $appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.nameAr).tag($0) }
                    } label: {
                        Label("المظهر", systemImage: "circle.lefthalf.filled")
                    }
                    .accessibilityIdentifier("settings-appearance")
                    NavigationLink { AppIconPicker() } label: {
                        Label("أيقونة التطبيق", systemImage: "app.badge")
                    }
                    NavigationLink { NotificationSettingsView() } label: {
                        Label("الإشعارات", systemImage: "bell")
                    }
                    .accessibilityIdentifier("settings-notifications")
                    Toggle(isOn: $hapticsEnabled) {
                        Label("الاهتزاز", systemImage: "hand.tap")
                    }
                    Button {
                        AppTips.showAgainNextLaunch()
                        tipsReset = true
                    } label: {
                        Label(tipsReset ? "بتطلع لك من جديد أول ما تفتح التطبيق" : "اعرض التلميحات من جديد", systemImage: "lightbulb")
                    }
                    .disabled(tipsReset)
                    LabeledContent {
                        Text("العربية").foregroundStyle(.secondary)
                    } label: {
                        Label("اللغة", systemImage: "globe")
                    }
                }

                if auth.isSignedIn {
                    Section("أدواتي") {
                        NavigationLink { GrinderGuideView() } label: { Label("مطحنتي", systemImage: "dial.medium.fill") }
                            .accessibilityIdentifier("open-grinders")
                        NavigationLink { TastePrefsView(mode: .settings) } label: { Label("ذوقي", systemImage: "heart.text.square.fill") }
                            .accessibilityIdentifier("open-taste-prefs")
                        NavigationLink { PassportView() } label: { Label("جوازي", systemImage: "globe.europe.africa.fill") }
                            .accessibilityIdentifier("open-passport")
                        // The recipes hub has its own navigation stack, so it opens as a sheet.
                        Button { showRecipes = true } label: { Label("وصفاتي", systemImage: "book.closed.fill") }
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("open-recipes")
                        NavigationLink { MySubmissionsView() } label: { Label("اقتراحاتي", systemImage: "sparkles") }
                            .accessibilityIdentifier("open-my-submissions")
                        if profile.me?.isAdmin == true {
                            NavigationLink { AdminConsoleView() } label: {
                                Label("لوحة التحكم", systemImage: "gauge.with.dots.needle.67percent")
                            }
                            .accessibilityIdentifier("open-admin-review")
                        }
                    }

                    Section {
                        Toggle(isOn: privateBinding) {
                            Label("حساب خاص", systemImage: "lock.fill")
                        }
                        .tint(Brand.olive)
                        .accessibilityIdentifier("privacy-private")
                        if pendingPrivate ?? profile.me?.isPrivate ?? false {
                            NavigationLink { FollowRequestsView() } label: {
                                Label("طلبات المتابعة", systemImage: "person.badge.clock")
                            }
                        }
                        NavigationLink { BlockedPeopleView() } label: {
                            Label("المحظورين", systemImage: "hand.raised.fill")
                        }
                    } footer: {
                        Text("الحساب الخاص: أي أحد يبي يتابعك يرسل طلب وأنت تقبله أو ترفضه، وقهاويك ووصفاتك ونشاطك لمتابعينك بس. اسمك وصورتك ونبذتك تبقى ظاهرة. وإذا طفيته تنقبل الطلبات اللي تنتظر.")
                    }

                    Section {
                        ForEach(PrivacyPart.allCases, id: \.self) { part in
                            Picker(selection: visibilityBinding(part)) {
                                ForEach(ProfileVisibility.allCases, id: \.self) { Text($0.nameAr).tag($0) }
                            } label: {
                                Label(part.titleAr, systemImage: icon(for: part))
                            }
                            .accessibilityIdentifier("privacy-\(part.rawValue)")
                        }
                        Toggle(isOn: hideBinding) {
                            Label("اخفني من المتصدرين", systemImage: "eye.slash")
                        }
                    } header: {
                        Text("الخصوصية")
                    } footer: {
                        Text("«متابعيني» يعني اللي يتابعونك بس. وإذا أخفيت نفسك من المتصدرين، تبقى نقاطك وسلسلتك لك.")
                    }
                }

                if !auth.isSignedIn {
                    // A guest's way to an account: back to the welcome screen's sign-in.
                    Section {
                        Button {
                            continuedAsGuest = false
                            dismiss()
                        } label: {
                            Label("سجّل دخولك أو أنشئ حساب", systemImage: "person.crop.circle.badge.plus")
                        }
                    } footer: {
                        Text("تحفظ مجموعتك وتقييماتك، وتتابع الناس، وتجمع نقاط.")
                    }
                }

                Section {
                    NavigationLink { UpdatesView() } label: { Label("تحديثات BunnList", systemImage: "megaphone.fill") }
                    if auth.isSignedIn {
                        NavigationLink { FeedbackView() } label: { Label("تواصل معنا", systemImage: "envelope.open.fill") }
                    }
                    Link(destination: ServerConfig.baseURL.appendingPathComponent("terms")) {
                        Label("الشروط والأحكام", systemImage: "doc.text.fill")
                    }
                    Link(destination: ServerConfig.baseURL.appendingPathComponent("privacy")) {
                        Label("سياسة الخصوصية", systemImage: "hand.raised.fill")
                    }
                } header: {
                    Text("عن التطبيق")
                } footer: {
                    Text("BunnList \(versionText)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }

                if auth.isSignedIn {
                    // Leaving goes last: sign out, then (apart) deleting the account.
                    Section {
                        Button("تسجيل الخروج") { auth.signOut() }
                            .frame(maxWidth: .infinity)
                    }
                    Section {
                        Button("حذف الحساب", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("settings-delete")
                    } footer: {
                        Text("يحذف حسابك وكل بياناته نهائيًا.")
                    }
                }
            }
            .brandScreen()
            .sheet(isPresented: $showRecipes) { RecipesHubView(startOn: .mine) }
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

    private func icon(for part: PrivacyPart) -> String {
        switch part {
        case .followers: return "person.2"
        case .following: return "person.2.fill"
        case .activity: return "sparkles"
        }
    }

    private func visibilityBinding(_ part: PrivacyPart) -> Binding<ProfileVisibility> {
        Binding(
            get: { pendingVisibility[part] ?? profile.me?.visibility(of: part) ?? .everyone },
            set: { value in
                pendingVisibility[part] = value
                Task {
                    let client = CatalogAPIClient(transport: URLSessionTransport())
                    _ = try? await auth.withToken { try await client.setVisibility(part, to: value, accessToken: $0) }
                    await profile.refresh(auth)
                    pendingVisibility[part] = nil
                }
            }
        )
    }

    private var privateBinding: Binding<Bool> {
        Binding(
            get: { pendingPrivate ?? profile.me?.isPrivate ?? false },
            set: { value in
                pendingPrivate = value
                Task {
                    let client = CatalogAPIClient(transport: URLSessionTransport())
                    _ = try? await auth.withToken { try await client.setPrivate(value, accessToken: $0) }
                    await profile.refresh(auth)
                    pendingPrivate = nil
                }
            }
        )
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

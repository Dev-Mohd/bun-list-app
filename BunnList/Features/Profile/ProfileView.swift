import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    let profileID: String
    @State private var showsSettings = false
    private var isOwner: Bool { profileID == store.state.localUserID }
    var body: some View {
        Group {
            if let profile = store.state.profile(profileID) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        DemoNotice()
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 54)).foregroundStyle(Brand.olive).accessibilityHidden(true)
                        Text(profile.displayName).font(.title2.bold())
                        Text(isOwner ? "حساب تجريبي محلي، دون تسجيل دخول أو مزامنة." : "ملف عام توضيحي محفوظ على هذا الجهاز.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if isOwner { Button("الإعدادات وحدود النسخة", systemImage: "gearshape") { showsSettings = true }.buttonStyle(.bordered) }
                        Text("التجارب العامة · محليًا").font(.headline)
                        ForEach(store.state.experiences.filter { $0.ownerID == profileID }.sorted { $0.createdAt > $1.createdAt }) { experience in
                            NavigationLink { ExperienceDetailView(experienceID: experience.id) } label: {
                                ExperienceCard(experience: experience)
                            }.buttonStyle(.plain)
                        }
                        if !store.state.experiences.contains(where: { $0.ownerID == profileID }) {
                            Text("لا توجد تجارب منشورة لهذا الحساب.").foregroundStyle(.secondary)
                        }
                        Divider()
                        Text("تقييمات المحاصيل العامة · محليًا").font(.headline)
                        ForEach(store.state.ratings.filter { $0.userID == profileID }) { rating in
                            NavigationLink { CoffeeDetailView(coffeeID: rating.coffeeID) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(store.state.coffee(rating.coffeeID)?.name ?? "محصول").foregroundStyle(Brand.ink)
                                    StarsView(value: rating.stars, label: "تقييم المحصول")
                                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                        if !store.state.ratings.contains(where: { $0.userID == profileID }) {
                            Text("لا توجد تقييمات محاصيل لهذا الحساب.").foregroundStyle(.secondary)
                        }
                    }.padding()
                }.background(Brand.background)
            } else { ContentUnavailableView("الملف غير موجود", systemImage: "person.crop.circle") }
        }.navigationTitle(isOwner ? "حسابي" : "ملف الناشر").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsSettings) { LocalSettingsView() }
    }
}

private struct LocalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("النسخة المحلية") {
                    Text("بن لست · BunnList").font(.headline)
                    Text("الحساب والأسماء والمحاصيل أمثلة توضيحية. لا يوجد تسجيل دخول حقيقي.")
                    Text("تُحفظ التجارب والمسودة والتقييمات والمكتبة في مساحة التطبيق على هذا الجهاز. حذف التطبيق يحذف بياناته المحلية؛ لا توجد مزامنة أو نسخة سحابية.")
                }
                Section("الخصوصية") {
                    Text("لا تتصل هذه النسخة بخادم. عبارة النشر للعامة تصف سلوك المنتج المستقبلي؛ لا يخرج محتواك من الجهاز في هذه المرحلة.")
                    Text("المسودة منفصلة عن التجارب المنشورة. لا يحتوي الملف العام على بريد أو أسرار.")
                }
                Section("مؤجل") {
                    Text("الصور، الحسابات الحقيقية، المزامنة، المتابعة والتعليقات والإعجابات، الإبلاغ والحظر وحذف الحساب قبل الإطلاق العام.")
                }
            }.navigationTitle("حول النسخة").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
        }
    }
}

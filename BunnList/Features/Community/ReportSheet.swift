import BunnListCore
import SwiftUI

/// What is being reported: a review, a recipe, a discoverer's note (by lot id) or
/// a profile (by username).
struct ReportRef: Identifiable, Hashable {
    let target: ReportTarget
    let targetID: String
    var id: String { target.rawValue + ":" + targetID }
}

/// "بلّغ": pick a reason, optionally add a line, send. The admin sees it in the console.
@MainActor
struct ReportSheet: View {
    let ref: ReportRef

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .offensive
    @State private var details = ""
    @State private var isSending = false
    @State private var sent = false
    @State private var errorMessage: String?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var subject: String {
        switch ref.target {
        case .review: return "هذا التقييم"
        case .recipe: return "هذي الوصفة"
        case .note: return "ملاحظة المكتشف"
        case .profile: return "هذا الحساب"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sent {
                    ContentUnavailableView {
                        Label("وصلنا بلاغك", systemImage: "checkmark.shield.fill").foregroundStyle(Brand.olive)
                    } description: {
                        Text("شكرًا لك. بنراجعه ونتصرف إذا لزم.")
                    } actions: {
                        Button("تم") { dismiss() }.buttonStyle(.borderedProminent).tint(Brand.olive)
                    }
                } else {
                    Form {
                        Section("وش المشكلة في \(subject)؟") {
                            Picker("السبب", selection: $reason) {
                                ForEach(ReportReason.allCases) { Text($0.nameAr).tag($0) }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                        Section("تفاصيل (اختياري)") {
                            TextField("اكتب وش لاحظت", text: $details, axis: .vertical).lineLimit(2...5)
                        }
                        if let errorMessage {
                            Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                        }
                    }
                }
            }
            .brandScreen()
            .navigationTitle("بلاغ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !sent {
                    ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("إرسال") { Task { await send() } }.disabled(isSending)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            try await auth.withToken {
                try await client.report(ref.target, id: ref.targetID, reason: reason, details: details, accessToken: $0)
            }
            sent = true
        } catch {
            errorMessage = "ما قدرنا نرسل البلاغ. حاول مرة ثانية."
        }
    }
}

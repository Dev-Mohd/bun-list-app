import BunnListCore
import SwiftUI

/// Choose or change the public @username. Format problems show as you type; the
/// server is asked about availability after a short pause.
@MainActor
struct UsernameEditor: View {
    let current: String?
    var onSaved: (String) -> Void

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var check: RemoteUsernameCheck?
    @State private var isChecking = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    init(current: String?, onSaved: @escaping (String) -> Void) {
        self.current = current
        self.onSaved = onSaved
        _text = State(initialValue: current ?? "")
    }

    private var candidate: String { UsernameRules.normalize(text) }
    private var localProblem: UsernameProblem? { UsernameRules.problem(candidate) }
    private var canSave: Bool {
        localProblem == nil && candidate != current && check?.username == candidate && check?.available == true && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("username", text: $text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .accessibilityIdentifier("username-field")
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    status
                } footer: {
                    Text("يظهر للناس بدل معرّف حسابك: في وصفاتك، وتقييماتك، وعلى القهوة اللي تكتشفها. ٣–٢٠ حرف: إنجليزي صغير وأرقام و _ و .")
                }
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .brandScreen()
            .navigationTitle(current == nil ? "اختر اسم مستخدم" : "تغيير اسم المستخدم")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { Task { await save() } }.disabled(!canSave)
                }
            }
            .task(id: candidate) { await checkAvailability() }
        }
    }

    @ViewBuilder
    private var status: some View {
        if candidate.isEmpty {
            EmptyView()
        } else if let localProblem {
            Label(localProblem.messageAr, systemImage: "xmark.circle").font(.caption).foregroundStyle(.orange)
        } else if candidate == current {
            Label("هذا اسمك الحالي", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
        } else if isChecking || check?.username != candidate {
            HStack(spacing: 6) { ProgressView(); Text("نتحقق…").font(.caption) }
        } else if check?.available == true {
            Label("متاح", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Brand.olive)
        } else {
            Label((check?.problem ?? .taken).messageAr, systemImage: "xmark.circle").font(.caption).foregroundStyle(.orange)
        }
    }

    private func checkAvailability() async {
        guard localProblem == nil, candidate != current else { return }
        try? await Task.sleep(nanoseconds: 400_000_000) // let typing settle; a newer value cancels this task
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
        let name = candidate
        do {
            let saved = try await auth.withToken { try await client.setUsername(name, accessToken: $0) }
            Haptics.tap()
            onSaved(saved)
            dismiss()
        } catch APIError.conflict {
            check = RemoteUsernameCheck(username: name, available: false, problem: .taken)
        } catch {
            errorMessage = "تعذّر الحفظ. حاول مجددًا."
        }
    }
}

import BunnListCore
import Foundation
import UIKit

/// Drives email sign-in against the live server and holds the signed-in session.
/// Keeps the UI thin: views call these methods and render `state`.
@MainActor
final class AuthModel: ObservableObject {
    enum State: Equatable {
        case signedOut
        case awaitingCode(email: String)
        case signedIn(accountID: String)
    }

    @Published private(set) var state: State
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    private let client: AuthAPIClient
    private let store: TokenStoring
    private let deviceID: String

    init(client: AuthAPIClient, store: TokenStoring, deviceID: String) {
        self.client = client
        self.store = store
        self.deviceID = deviceID
        if let session = store.load() {
            state = .signedIn(accountID: session.accountID)
        } else {
            state = .signedOut
        }
    }

    /// Production wiring: URLSession transport + Keychain + this device's vendor id.
    static func live() -> AuthModel {
        AuthModel(
            client: AuthAPIClient(transport: URLSessionTransport()),
            store: KeychainTokenStore(),
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        )
    }

    var isSignedIn: Bool { if case .signedIn = state { return true } else { return false } }

    /// The current access token, if signed in.
    func currentAccessToken() -> String? { store.load()?.accessToken }

    /// Rotates the access token using the stored refresh token. Returns a fresh
    /// access token, or nil if refresh failed (in which case the session is cleared).
    func refreshAccessToken() async -> String? {
        guard let session = store.load() else { return nil }
        do {
            let tokens = try await client.refresh(refreshToken: session.refreshToken)
            store.save(StoredSession(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, accountID: tokens.accountID))
            return tokens.accessToken
        } catch {
            signOut()
            return nil
        }
    }

    // MARK: - Actions

    func sendCode(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@") else { errorMessage = "أدخل بريدًا إلكترونيًا صحيحًا."; return }
        await run {
            try await client.requestEmailCode(email: trimmed)
            state = .awaitingCode(email: trimmed)
        }
    }

    func verify(code: String) async {
        guard case let .awaitingCode(email) = state else { return }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6, trimmed.allSatisfy(\.isNumber) else {
            errorMessage = "الرمز يتكوّن من ٦ أرقام."; return
        }
        await run {
            let tokens = try await client.verifyEmailCode(email: email, code: trimmed, deviceID: deviceID)
            store.save(StoredSession(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, accountID: tokens.accountID))
            state = .signedIn(accountID: tokens.accountID)
        }
    }

    func resendCode() async {
        guard case let .awaitingCode(email) = state else { return }
        await run { try await client.requestEmailCode(email: email) }
    }

    func changeEmail() { state = .signedOut }

    func signOut() {
        store.clear()
        state = .signedOut
    }

    func deleteAccount() async {
        await run {
            if let session = store.load() {
                try await client.deleteAccount(accessToken: session.accessToken)
            }
            store.clear()
            state = .signedOut
        }
    }

    // MARK: - Internals

    /// Runs an async action with the busy flag set and a human message mapped from any error.
    private func run(_ action: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await action()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .unauthorized: return "الرمز غير صحيح أو انتهت صلاحيته. أعد المحاولة."
            case .rateLimited: return "محاولات كثيرة. انتظر دقيقة ثم أعد المحاولة."
            case .unprocessable: return "تحقق من صحة البريد والرمز."
            case .forbidden: return "لا تملك صلاحية هذا الإجراء."
            case .conflict: return "حدث تعارض. أعد المحاولة."
            }
        }
        if error is AuthClientError {
            return "تعذّر الاتصال بالخادم. حاول بعد قليل."
        }
        return "تعذّر إكمال الطلب. تحقق من اتصالك بالإنترنت."
    }
}

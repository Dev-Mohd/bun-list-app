import BunnListCore
import SwiftUI
import UIKit
import UserNotifications

/// Push notifications: asks permission (only from the notifications screen),
/// registers the phone with Apple, and hands its token to the server for the
/// signed-in account. Also schedules the local streak reminder.
@MainActor
final class PushManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushManager()
    static let tokenKey = "apnsDeviceToken"
    static let streakKey = "streakReminderEnabled"

    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    weak var auth: AuthModel?

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    #if DEBUG
    private let environment = PushEnvironment.sandbox
    #else
    private let environment = PushEnvironment.production
    #endif

    func start(auth: AuthModel) {
        self.auth = auth
        UNUserNotificationCenter.current().delegate = self
        Task {
            await refreshStatus()
            if status == .authorized || status == .provisional { UIApplication.shared.registerForRemoteNotifications() }
            scheduleStreakReminder()
        }
    }

    func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks once; afterwards the answer lives in the iPhone's Settings.
    @discardableResult
    func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshStatus()
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    func didRegister(token data: Data) {
        let token = CatalogAPIClient.hexToken(data)
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        Task { await uploadToken() }
    }

    /// Sends the stored token for the signed-in account (after sign-in too).
    func uploadToken() async {
        guard let auth, auth.isSignedIn, let token = UserDefaults.standard.string(forKey: Self.tokenKey) else { return }
        _ = try? await auth.withToken { try await client.registerDevice(token: token, environment: environment, accessToken: $0) }
    }

    // MARK: Streak reminder (local, no server)

    /// Tomorrow at 8 pm, replaced every time the app opens: it only fires on a day
    /// the app wasn't opened.
    func scheduleStreakReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["streak"])
        guard UserDefaults.standard.bool(forKey: Self.streakKey), status == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "لا تقطع سلسلتك 🔥"
        content.body = "سجّل تجربة أو قيّم قهوة اليوم وكمّل أيامك المتواصلة."
        content.sound = .default
        var day = Calendar.current.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(86_400))
        day.hour = 20
        center.add(UNNotificationRequest(identifier: "streak", content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: day, repeats: false)))
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Receives the APNs token from UIKit.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushManager.shared.didRegister(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("push registration failed: \(error)")
    }
}

import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import Foundation
import UserNotifications

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var isNotificationsEnabled = false
    private let db = Firestore.firestore()
    private var pendingFCMTokenUpdate: String?

    override private init() {
        super.init()
        registerForPushNotifications()
    }

    func registerForPushNotifications() {
        UNUserNotificationCenter.current().delegate = self

        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { [weak self] granted, _ in
                self?.isNotificationsEnabled = granted
                if granted {
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        )

        Messaging.messaging().delegate = self
    }

    func updateFCMToken(for userId: String) {
        // Store userId for when APNS token is ready
        pendingFCMTokenUpdate = userId

        // If we already have permission, trigger the token refresh
        if isNotificationsEnabled {
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private func saveFCMToken(_ token: String, for userId: String) {
        db.collection("users").document(userId).updateData([
            "fcmToken": token,
        ]) { error in
            if let error = error {
                print("Error saving FCM token: \(error)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Handle notification tap
        if let postId = userInfo["postId"] as? String {
            // TODO: Navigate to the post
            print("Should navigate to post: \(postId)")
        }

        completionHandler()
    }
}

// MARK: - MessagingDelegate

extension NotificationManager: MessagingDelegate {
    func messaging(_: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("FCM token: \(token)")

        // If we have a pending user ID, update their token
        if let userId = pendingFCMTokenUpdate {
            saveFCMToken(token, for: userId)
            pendingFCMTokenUpdate = nil
        }
    }
}

// MARK: - UIApplicationDelegate

extension NotificationManager {
    func application(
        _: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken

        // After APNS token is set, request FCM token if we have a pending update
        if pendingFCMTokenUpdate != nil {
            Messaging.messaging().token { [weak self] token, error in
                if let error = error {
                    print("Error fetching FCM token: \(error)")
                    return
                }

                if let token = token, let userId = self?.pendingFCMTokenUpdate {
                    self?.saveFCMToken(token, for: userId)
                    self?.pendingFCMTokenUpdate = nil
                }
            }
        }
    }

    func application(
        _: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error)")
    }
}

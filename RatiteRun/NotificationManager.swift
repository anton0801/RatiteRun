//
//  NotificationManager.swift
//  RatiteRun
//
//  Real UNUserNotificationCenter scheduling for flock care reminders.
//

import Foundation
import UserNotifications

final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var authorized: Bool = false

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization(_ completion: ((Bool) -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.authorized = granted
                completion?(granted)
            }
        }
    }

    func refreshStatus() {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            }
        }
    }

    private func identifier(_ flockID: UUID, _ reminderID: UUID) -> String {
        "ratiterun.\(flockID.uuidString).\(reminderID.uuidString)"
    }

    /// Schedule (or reschedule) a daily reminder.
    func schedule(_ reminder: FlockReminder, for flock: Flock, completion: (() -> Void)? = nil) {
        let id = identifier(flock.id, reminder.id)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard reminder.enabled else { completion?(); return }

        let content = UNMutableNotificationContent()
        content.title = "\(flock.title) · \(reminder.kind.label)"
        content.body = body(for: reminder.kind, species: flock.species)
        content.sound = .default

        var comps = DateComponents()
        comps.hour = reminder.hour
        comps.minute = reminder.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { _ in DispatchQueue.main.async { completion?() } }
    }

    func cancel(_ reminder: FlockReminder, for flock: Flock) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(flock.id, reminder.id)])
    }

    func cancelAll(for flock: Flock) {
        let ids = flock.reminders.map { identifier(flock.id, $0.id) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelEverything() {
        center.removeAllPendingNotificationRequests()
    }

    /// Fire a one-off test notification so the user sees it work.
    func fireTest() {
        let content = UNMutableNotificationContent()
        content.title = "Ratite Run"
        content.body = "Reminders are working — you'll get nudges for feed, water, fence and leg checks."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        center.add(UNNotificationRequest(identifier: "ratiterun.test", content: content, trigger: trigger))
    }

    private func body(for kind: ReminderKind, species: Species) -> String {
        switch kind {
        case .feedGrit:  return "Feed the \(species.label.lowercased())s and top up digestive grit/stones."
        case .water:     return "Check and refill clean water."
        case .fenceCheck: return "Walk the perimeter — check the tall fence for gaps or damage."
        case .legHealth: return "Inspect legs, joints and general health. Note anything unusual."
        }
    }
}

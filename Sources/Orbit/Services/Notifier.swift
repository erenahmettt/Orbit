import Foundation
import UserNotifications

/// Yerel macOS bildirimleri. Yalnızca .app paketi içinden çalıştırıldığında etkindir.
enum Notifier {
    static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }
    private static var center: UNUserNotificationCenter? { available ? .current() : nil }

    static func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    @MainActor
    static func schedule(task: TaskItem) {
        guard let center else { return }
        cancel(task: task)
        guard !task.isDone, task.deletedAt == nil else { return }
        var requests: [UNNotificationRequest] = []

        if let r = task.reminder, r > Date() {
            let c = UNMutableNotificationContent()
            c.title = "⏰ \(task.title)"
            c.body = task.dueDate.map { "Son teslim: \(Fmt.relative($0))" + (task.hasTime ? " \(Fmt.time.string(from: $0))" : "") } ?? "Görev hatırlatıcısı"
            c.sound = .default
            requests.append(.init(identifier: "task-rem-\(task.id)", content: c, trigger: trigger(r)))
        }
        if let due = task.dueDate {
            // Saatli görevlerde teslim anında, saatsizlerde teslim günü 09:00'da
            let fire = task.hasTime ? due : due.startOfDay.at(hour: 9)
            if fire > Date() {
                let c = UNMutableNotificationContent()
                c.title = "📌 Son teslim: \(task.title)"
                c.body = task.hasTime ? "Şimdi teslim zamanı." : "Bu görevin son günü bugün."
                c.sound = .default
                requests.append(.init(identifier: "task-due-\(task.id)", content: c, trigger: trigger(fire)))
            }
        }
        requests.forEach { center.add($0) }
    }

    @MainActor
    static func cancel(task: TaskItem) {
        center?.removePendingNotificationRequests(withIdentifiers: ["task-rem-\(task.id)", "task-due-\(task.id)"])
    }

    static func scheduleDailyPlanning(enabled: Bool, hour: Int, minute: Int) {
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: ["daily-planning"])
        guard enabled else { return }
        let c = UNMutableNotificationContent()
        c.title = "☀️ Günü planla"
        c.body = "Orbit'i aç ve bugünün odak görevlerini seç."
        c.sound = .default
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = minute
        center.add(.init(identifier: "daily-planning", content: c, trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)))
    }

    private static func trigger(_ date: Date) -> UNCalendarNotificationTrigger {
        let dc = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
    }
}

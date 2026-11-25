import Foundation
import SwiftData
import WidgetKit

/// Uygulama verisinden widget özetini üretir ve widget'ları yeniler.
@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()
    private var container: ModelContainer?
    private var pending: DispatchWorkItem?
    private var timer: Timer?

    func attach(_ container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            Task { @MainActor in WidgetBridge.refreshSoon() }
        }
        // Gece yarısı geçişi ve otomatik kayıt gecikmeleri için periyodik yenileme
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            Task { @MainActor in WidgetBridge.shared.write() }
        }
        write()
    }

    static func refreshSoon() {
        let b = shared
        b.pending?.cancel()
        let item = DispatchWorkItem { Task { @MainActor in b.write() } }
        b.pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
    }

    func write() {
        guard let ctx = container?.mainContext else { return }
        // ORBIT_DATA_DIR ile yapılan test çalıştırmaları gerçek widget verisine dokunmaz
        guard ProcessInfo.processInfo.environment["ORBIT_DATA_DIR"] == nil else { return }
        try? ctx.save()
        let now = Date()
        let horizon = now.startOfDay.adding(days: 2)
        let projects = (try? ctx.fetch(FetchDescriptor<Project>())) ?? []
        let colorOf = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.colorHex) })
        let tasks = ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { t in
            guard t.isLive else { return false }
            if t.isDone { return t.completedAt.map { Calendar.current.isDateInToday($0) } ?? false }
            return (t.dueDate ?? .distantFuture) < horizon
        }
        let events = ((try? ctx.fetch(FetchDescriptor<CalEvent>())) ?? []).filter { $0.deletedAt == nil && $0.end > now && $0.start < now.adding(days: 7) }
        let sessions = (try? ctx.fetch(FetchDescriptor<FocusSession>())) ?? []

        let f = FocusTimer.shared
        let focus: WidgetSnapshot.WFocus? = f.isActive
            ? .init(phase: f.phase.rawValue, end: f.isRunning ? Date().addingTimeInterval(f.remaining) : nil, pausedRemaining: f.isPaused ? f.remaining : nil, duration: f.minutes(for: f.phase) * 60, taskTitle: f.taskTitle)
            : nil

        let d = UserDefaults.standard
        let snap = WidgetSnapshot(
            generated: now,
            userName: d.string(forKey: "userName") ?? "",
            accent: d.string(forKey: "accent") ?? "#6558F5",
            tasks: tasks.map { t in
                .init(id: t.id.uuidString, title: t.title, due: t.dueDate, hasTime: t.hasTime, done: t.isDone, completedAt: t.completedAt, priority: t.priority.rawValue, projectColor: t.projectID.flatMap { colorOf[$0] })
            },
            events: events.map { .init(id: $0.id.uuidString, title: $0.title, start: $0.start, end: $0.end, color: $0.colorHex) },
            focus: focus,
            focusMinutesToday: sessions.filter { Calendar.current.isDateInToday($0.start) }.reduce(0) { $0 + $1.minutes })
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

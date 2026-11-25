import Foundation
import SwiftData
import SwiftUI

/// Model üzerindeki tüm yan etkili işlemler (aktivite kaydı, bildirim planlama, tekrar) buradan geçer.
@MainActor
enum Store {
    // MARK: Activity

    static func log(_ context: ModelContext, _ text: String, icon: String, color: String = "#6558F5", projectID: UUID?) {
        context.insert(Activity(text: text, icon: icon, colorHex: color, projectID: projectID))
    }

    static func projectName(_ context: ModelContext, _ id: UUID?) -> String? {
        guard let id else { return nil }
        let d = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(d).first?.name
    }

    // MARK: Tasks

    @discardableResult
    static func createTask(context: ModelContext, title: String, status: TaskStatus? = nil, priority: TaskPriority = .normal, due: Date? = nil, hasTime: Bool = false, projectID: UUID? = nil, tags: [String] = [], recurrence: Recurrence = Recurrence(), estimate: Int = 0) -> TaskItem {
        // Proje ya da tarih yoksa görev Inbox'a düşer
        let resolved = status ?? ((projectID == nil && due == nil) ? .inbox : .todo)
        let t = TaskItem(title: title, status: resolved, priority: priority, due: due, hasTime: hasTime, projectID: projectID)
        t.tags = tags
        t.recurrence = recurrence
        t.estimateMinutes = estimate
        context.insert(t)
        let where_ = projectName(context, projectID).map { "\($0) projesine" } ?? "Inbox'a"
        log(context, "\(where_) yeni görev eklendi: **\(title)**", icon: "plus.circle.fill", color: "#55A7E8", projectID: projectID)
        Notifier.schedule(task: t)
        return t
    }

    static func toggleComplete(_ task: TaskItem, context: ModelContext, app: AppState? = nil) {
        if task.isDone {
            task.status = .todo
            task.completedAt = nil
            task.updatedAt = Date()
            Notifier.schedule(task: task)
            return
        }
        let previous = task.status
        task.status = .completed
        task.completedAt = Date()
        task.updatedAt = Date()
        Notifier.cancel(task: task)
        log(context, "Görev tamamlandı: **\(task.title)**", icon: "checkmark.circle.fill", color: "#35B88A", projectID: task.projectID)

        var spawned: TaskItem?
        if task.recurrence.isActive {
            let base = task.dueDate ?? Date()
            let next = task.recurrence.next(after: base)
            let n = TaskItem(title: task.title, status: .todo, priority: task.priority, due: next, hasTime: task.hasTime, projectID: task.projectID)
            n.details = task.details
            n.tags = task.tags
            n.estimateMinutes = task.estimateMinutes
            n.recurrence = task.recurrence
            n.subtasks = task.subtasks.map { Subtask(title: $0.title) }
            n.relatedNoteIDs = task.relatedNoteIDs
            if let r = task.reminder, let due = task.dueDate {
                n.reminder = next.addingTimeInterval(r.timeIntervalSince(due))
            }
            context.insert(n)
            Notifier.schedule(task: n)
            spawned = n
        }

        let msg = spawned.map { "Tamamlandı · sonraki: \(Fmt.relative($0.dueDate!))" } ?? "Tamamlandı: \(task.title)"
        app?.show(Toast(text: msg, icon: "checkmark.circle.fill", color: Palette.success, undo: {
            task.status = previous == .completed ? .todo : previous
            task.completedAt = nil
            if let s = spawned { context.delete(s) }
            Notifier.schedule(task: task)
        }))
    }

    static func setStatus(_ task: TaskItem, _ status: TaskStatus, context: ModelContext, app: AppState? = nil) {
        guard task.status != status else { return }
        if status == .completed { toggleComplete(task, context: context, app: app); return }
        task.status = status
        task.completedAt = nil
        task.updatedAt = Date()
        log(context, "**\(task.title)** → \(status.title)", icon: status.icon, color: "#9B78E8", projectID: task.projectID)
    }

    /// Tarihi değiştirir; saat bilgisi varsa korunur.
    static func reschedule(_ task: TaskItem, to day: Date?, time: Date? = nil, context: ModelContext) {
        let cal = Calendar.current
        if let day {
            if let time {
                task.dueDate = time
                task.hasTime = true
            } else if task.hasTime, let old = task.dueDate {
                let c = cal.dateComponents([.hour, .minute], from: old)
                task.dueDate = day.at(hour: c.hour ?? 9, minute: c.minute ?? 0)
            } else {
                task.dueDate = day.startOfDay
            }
            if task.status == .inbox { task.status = .todo }
        } else {
            task.dueDate = nil
            task.hasTime = false
        }
        task.updatedAt = Date()
        let label = task.dueDate.map { Fmt.relative($0) + (task.hasTime ? " " + Fmt.time.string(from: $0) : "") } ?? "tarihsiz"
        log(context, "Görev tarihi değiştirildi: **\(task.title)** → \(label)", icon: "calendar.badge.clock", color: "#F2B84B", projectID: task.projectID)
        Notifier.schedule(task: task)
    }

    /// Bugünden itibaren `days` gün sonrasına taşır (1 = Tomorrow).
    static func snooze(_ task: TaskItem, days: Int, context: ModelContext, app: AppState? = nil) {
        let target = Date().startOfDay.adding(days: days)
        reschedule(task, to: target, context: context)
        app?.show(Toast(text: "Ertelendi → \(Fmt.relative(target))", icon: "moon.zzz.fill", color: Palette.purple))
    }

    static func trash(_ task: TaskItem, context: ModelContext, app: AppState? = nil) {
        task.deletedAt = Date()
        Notifier.cancel(task: task)
        app?.show(Toast(text: "Çöp kutusuna taşındı", icon: "trash.fill", color: Palette.secondary, undo: { task.deletedAt = nil }))
    }

    // MARK: Notes

    @discardableResult
    static func createNote(context: ModelContext, title: String, body: String = "", projectID: UUID? = nil, folderID: UUID? = nil) -> Note {
        let n = Note(title: title, body: body, folderID: folderID, projectID: projectID)
        context.insert(n)
        log(context, "Yeni not oluşturuldu\(title.isEmpty ? "" : ": **\(title)**")", icon: "note.text.badge.plus", color: "#F2B84B", projectID: projectID)
        return n
    }

    // MARK: Projects

    static func progress(of project: Project, tasks: [TaskItem]) -> (done: Int, total: Int, ratio: Double) {
        let pts = tasks.filter { $0.projectID == project.id && $0.isLive }
        let d = pts.filter(\.isDone).count
        return (d, pts.count, pts.isEmpty ? 0 : Double(d) / Double(pts.count))
    }

    // MARK: Journal

    static func journal(for day: Date, context: ModelContext) -> JournalEntry {
        let start = day.startOfDay
        let end = start.adding(days: 1)
        let d = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.day >= start && $0.day < end })
        if let e = try? context.fetch(d).first { return e }
        let e = JournalEntry(day: start)
        context.insert(e)
        return e
    }
}

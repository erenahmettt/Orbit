import Foundation
import SwiftData
import SwiftUI

// MARK: - Enums

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case inbox, todo, inProgress, completed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .completed: "Completed"
        }
    }
    var icon: String {
        switch self {
        case .inbox: "tray"
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .completed: "checkmark.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .inbox: Palette.info
        case .todo: Palette.purple
        case .inProgress: Palette.warning
        case .completed: Palette.success
        }
    }
}

enum TaskPriority: Int, Codable, CaseIterable, Identifiable, Comparable {
    case low = 0, normal = 1, high = 2, urgent = 3
    var id: Int { rawValue }
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    var title: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }
    var color: Color {
        switch self {
        case .low: Palette.info
        case .normal: .secondary
        case .high: Palette.warning
        case .urgent: Palette.secondary
        }
    }
    var flag: String { self == .low || self == .normal ? "flag" : "flag.fill" }
}

enum RecurrenceKind: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekly, monthly, weekdays, interval
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "Tekrarlama yok"
        case .daily: "Her gün"
        case .weekly: "Her hafta"
        case .monthly: "Her ay"
        case .weekdays: "Belirli günlerde"
        case .interval: "Özel aralık"
        }
    }
}

enum IntervalUnit: String, Codable, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var title: String { switch self { case .day: "gün"; case .week: "hafta"; case .month: "ay" } }
    var component: Calendar.Component { switch self { case .day: .day; case .week: .weekOfYear; case .month: .month } }
}

struct Recurrence: Codable, Hashable {
    var kind: RecurrenceKind = .none
    var interval: Int = 1
    var unit: IntervalUnit = .day
    /// 1 = Pazar ... 7 = Cumartesi (Calendar.weekday)
    var weekdays: [Int] = []

    var isActive: Bool { kind != .none }

    var summary: String {
        switch kind {
        case .none: return "Yok"
        case .daily, .weekly, .monthly: return kind.title
        case .interval: return "Her \(interval) \(unit.title)"
        case .weekdays:
            let names = weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { Fmt.weekdaySymbol($0) }
            return names.isEmpty ? "Belirli günlerde" : names.joined(separator: ", ")
        }
    }

    func next(after date: Date) -> Date {
        let cal = Calendar.current
        switch kind {
        case .none: return date
        case .daily: return cal.date(byAdding: .day, value: 1, to: date)!
        case .weekly: return cal.date(byAdding: .day, value: 7, to: date)!
        case .monthly: return cal.date(byAdding: .month, value: 1, to: date)!
        case .interval: return cal.date(byAdding: unit.component, value: max(1, interval), to: date)!
        case .weekdays:
            guard !weekdays.isEmpty else { return cal.date(byAdding: .day, value: 1, to: date)! }
            var d = cal.date(byAdding: .day, value: 1, to: date)!
            for _ in 0..<8 {
                if weekdays.contains(cal.component(.weekday, from: d)) { return d }
                d = cal.date(byAdding: .day, value: 1, to: d)!
            }
            return d
        }
    }
}

struct Subtask: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var done = false
}

struct ProjectResource: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var url: String
    var kind: String = "link" // link | file | ref
}

enum ProjectStatus: String, Codable, CaseIterable, Identifiable {
    case planning, active, paused, completed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .planning: "Planlama"
        case .active: "Aktif"
        case .paused: "Beklemede"
        case .completed: "Tamamlandı"
        }
    }
    var color: Color {
        switch self {
        case .planning: Palette.info
        case .active: Palette.success
        case .paused: Palette.warning
        case .completed: Palette.purple
        }
    }
}

// MARK: - Models

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var summary: String = ""
    var colorHex: String = "#6558F5"
    var icon: String = "folder.fill"
    var startDate: Date?
    var targetDate: Date?
    var statusRaw: String = ProjectStatus.active.rawValue
    var resources: [ProjectResource] = []
    var sortIndex: Int = 0
    var archived: Bool = false
    var deletedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String, summary: String = "", colorHex: String, icon: String, status: ProjectStatus = .active) {
        self.name = name
        self.summary = summary
        self.colorHex = colorHex
        self.icon = icon
        self.statusRaw = status.rawValue
    }

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
    var color: Color { Color(hex: colorHex) }
    var isLive: Bool { !archived && deletedAt == nil }
}

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var statusRaw: String = TaskStatus.inbox.rawValue
    var priorityRaw: Int = TaskPriority.normal.rawValue
    var startDate: Date?
    var dueDate: Date?
    /// Görevin takvimdeki saati varsa true (dueDate saat bilgisini taşır)
    var hasTime: Bool = false
    var estimateMinutes: Int = 0
    /// Pomodoro ile bu göreve harcanan odak süresi (dakika)
    var focusMinutes: Int = 0
    var projectID: UUID?
    var tags: [String] = []
    var subtasks: [Subtask] = []
    var reminder: Date?
    var recurrence: Recurrence = Recurrence()
    var relatedNoteIDs: [UUID] = []
    var completedAt: Date?
    var archived: Bool = false
    var deletedAt: Date?
    /// Yeni görev penceresi açıkken oluşturulan geçici kayıt
    var isDraft: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(title: String, status: TaskStatus = .inbox, priority: TaskPriority = .normal, due: Date? = nil, hasTime: Bool = false, projectID: UUID? = nil) {
        self.title = title
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.dueDate = due
        self.hasTime = hasTime
        self.projectID = projectID
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }
    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }
    var isDone: Bool { status == .completed }
    var isLive: Bool { !archived && deletedAt == nil && !isDraft }
    var isOverdue: Bool {
        guard !isDone, let due = dueDate else { return false }
        return hasTime ? due < Date() : Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: Date())
    }
    var isToday: Bool { dueDate.map { Calendar.current.isDateInToday($0) } ?? false }
    var subtaskProgress: (Int, Int) { (subtasks.filter(\.done).count, subtasks.count) }
}

@Model
final class NoteFolder {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "folder"
    var colorHex: String = "#6558F5"
    var sortIndex: Int = 0
    init(name: String, icon: String, colorHex: String, sortIndex: Int = 0) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }
}

@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var folderID: UUID?
    var projectID: UUID?
    var tags: [String] = []
    var pinned: Bool = false
    var favorite: Bool = false
    var archived: Bool = false
    var deletedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(title: String, body: String = "", folderID: UUID? = nil, projectID: UUID? = nil) {
        self.title = title
        self.body = body
        self.folderID = folderID
        self.projectID = projectID
    }
    var isLive: Bool { !archived && deletedAt == nil }
    /// [[Not Başlığı]] şeklindeki bağlantılar
    var linkedTitles: [String] {
        let pattern = try! NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)
        let ns = body as NSString
        return pattern.matches(in: body, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }
    var preview: String {
        let line = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("```") } ?? ""
        var s = line
        for p in [#"^(- \[[ xX]\] |[-*] |\d+\. |> )"#, #"\*\*|__|`|<\/?u>"#, #"(?<!\w)\*(?!\s)|(?<!\s)\*(?!\w)"#] {
            s = s.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: #"\[\[([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        return String(s.prefix(140))
    }
}

@Model
final class CalEvent {
    var id: UUID = UUID()
    var title: String = ""
    var start: Date = Date()
    var end: Date = Date()
    var allDay: Bool = false
    var colorHex: String = "#55A7E8"
    var projectID: UUID?
    var location: String = ""
    var notes: String = ""
    var deletedAt: Date?
    var createdAt: Date = Date()

    init(title: String, start: Date, end: Date, colorHex: String = "#55A7E8", projectID: UUID? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.colorHex = colorHex
        self.projectID = projectID
    }
    var color: Color { Color(hex: colorHex) }
}

@Model
final class JournalEntry {
    var id: UUID = UUID()
    /// Günün başlangıcı
    var day: Date = Date()
    var goals: String = ""
    var done: String = ""
    var freeText: String = ""
    var review: String = ""
    var tomorrow: String = ""
    var mood: Int = 0
    var habitsDone: [String] = []
    var updatedAt: Date = Date()

    init(day: Date) { self.day = Calendar.current.startOfDay(for: day) }

    var isEmpty: Bool {
        [goals, done, freeText, review, tomorrow].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && habitsDone.isEmpty && mood == 0
    }
}

@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "checkmark"
    var colorHex: String = "#35B88A"
    var sortIndex: Int = 0
    init(name: String, icon: String, colorHex: String, sortIndex: Int) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }
}

@Model
final class Activity {
    var id: UUID = UUID()
    var date: Date = Date()
    var projectID: UUID?
    var icon: String = "sparkles"
    var colorHex: String = "#6558F5"
    var text: String = ""
    init(text: String, icon: String, colorHex: String, projectID: UUID?) {
        self.text = text
        self.icon = icon
        self.colorHex = colorHex
        self.projectID = projectID
    }
}

@Model
final class FocusSession {
    var id: UUID = UUID()
    var start: Date = Date()
    var minutes: Int = 0
    var taskID: UUID?
    var taskTitle: String = ""
    init(start: Date, minutes: Int, taskID: UUID?, taskTitle: String) {
        self.start = start
        self.minutes = minutes
        self.taskID = taskID
        self.taskTitle = taskTitle
    }
}

let allModels: [any PersistentModel.Type] = [Project.self, TaskItem.self, NoteFolder.self, Note.self, CalEvent.self, JournalEntry.self, Habit.self, Activity.self, FocusSession.self]

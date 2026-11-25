import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case home, inbox, today, upcoming, calendar, tasks, projects, notes, journal, focus, archive, trash, settings
    case project(UUID)

    var title: String {
        switch self {
        case .home: "Home"
        case .inbox: "Inbox"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .calendar: "Calendar"
        case .tasks: "Tasks"
        case .projects: "Projects"
        case .notes: "Notes"
        case .journal: "Journal"
        case .focus: "Focus"
        case .archive: "Archive"
        case .trash: "Trash"
        case .settings: "Settings"
        case .project: "Project"
        }
    }
    var icon: String {
        switch self {
        case .home: "house.fill"
        case .inbox: "tray.fill"
        case .today: "sun.max.fill"
        case .upcoming: "calendar.badge.clock"
        case .calendar: "calendar"
        case .tasks: "checkmark.circle.fill"
        case .projects: "square.stack.3d.up.fill"
        case .notes: "note.text"
        case .journal: "book.closed.fill"
        case .focus: "timer"
        case .archive: "archivebox.fill"
        case .trash: "trash.fill"
        case .settings: "gearshape.fill"
        case .project: "folder.fill"
        }
    }
    var color: Color {
        switch self {
        case .home: Palette.primary
        case .inbox: Palette.info
        case .today: Palette.warning
        case .upcoming: Palette.teal
        case .calendar: Palette.blue
        case .tasks: Palette.success
        case .projects: Palette.purple
        case .notes: Palette.warning
        case .journal: Color(hex: "#E86BA8")
        case .focus: Palette.secondary
        case .archive, .trash, .settings: Color(hex: "#8A94A6")
        case .project: Palette.primary
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let icon: String
    let color: Color
    var undo: (() -> Void)? = nil
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selection: SidebarItem? = .home
    @Published var showPalette = false
    @Published var editingTask: TaskItem?
    @Published var newTaskDraft: NewTaskDraft?
    @Published var selectedNoteID: UUID?
    @Published var noteFocusRequest = UUID()
    @Published var toast: Toast?
    @Published var calendarDate = Date()

    func go(_ item: SidebarItem) {
        withAnimation(.snappy(duration: 0.2)) { selection = item }
    }

    func newTask(due: Date? = nil, hasTime: Bool = false, projectID: UUID? = nil, status: TaskStatus? = nil) {
        newTaskDraft = NewTaskDraft(due: due, hasTime: hasTime, projectID: projectID, status: status)
    }

    func newNote(context: ModelContext, projectID: UUID? = nil, folderID: UUID? = nil) {
        let note = Store.createNote(context: context, title: "", projectID: projectID, folderID: folderID)
        selectedNoteID = note.id
        if case .project = selection {} else { go(.notes) }
        noteFocusRequest = UUID()
    }

    func show(_ toast: Toast) {
        withAnimation(.spring(duration: 0.35)) { self.toast = toast }
        let id = toast.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            guard self?.toast?.id == id else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }
}

struct NewTaskDraft: Identifiable {
    let id = UUID()
    var due: Date?
    var hasTime: Bool
    var projectID: UUID?
    var status: TaskStatus?
}

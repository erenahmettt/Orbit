import SwiftUI
import SwiftData

enum TaskScope { case inbox, today, upcoming, all, project(UUID) }

enum TaskViewMode: String, CaseIterable, Identifiable {
    case list, kanban, calendar, priority, project
    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: "List"
        case .kanban: "Kanban"
        case .calendar: "Calendar"
        case .priority: "Priority"
        case .project: "Project"
        }
    }
    var icon: String {
        switch self {
        case .list: "list.bullet"
        case .kanban: "square.split.3x1"
        case .calendar: "calendar"
        case .priority: "flag"
        case .project: "square.stack.3d.up"
        }
    }
}

struct TaskCollectionView: View {
    let scope: TaskScope
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) var context
    @Query var allTasks: [TaskItem]
    @Query(sort: \Project.sortIndex) var projects: [Project]
    @Query(sort: \Note.updatedAt, order: .reverse) var notes: [Note]
    @AppStorage("taskViewMode") var modeRaw = TaskViewMode.list.rawValue
    @AppStorage("showCompleted") var showCompleted = true
    @State private var tagFilter: String?

    var mode: TaskViewMode { TaskViewMode(rawValue: modeRaw) ?? .list }

    var header: (String, String, Color, String) {
        switch scope {
        case .inbox: ("Inbox", "tray.fill", Palette.info, "Henüz kategorize edilmemiş görevler ve notlar")
        case .today: ("Today", "sun.max.fill", Palette.warning, Fmt.longDate.string(from: Date()))
        case .upcoming: ("Upcoming", "calendar.badge.clock", Palette.teal, "Önümüzdeki günler")
        case .all: ("Tasks", "checkmark.circle.fill", Palette.success, "Bütün görevlerin")
        case .project: ("Tasks", "checkmark.circle.fill", Palette.success, "")
        }
    }

    var scoped: [TaskItem] {
        let live = allTasks.filter(\.isLive)
        var r: [TaskItem]
        switch scope {
        case .inbox: r = live.filter { $0.status == .inbox }
        case .today: r = live.filter { (!$0.isDone && ($0.isToday || $0.isOverdue)) || ($0.isDone && ($0.completedAt.map(Calendar.current.isDateInToday) ?? false)) }
        case .upcoming: r = live.filter { !$0.isDone && ($0.dueDate ?? .distantPast) >= Date().startOfDay }
        case .all: r = live
        case .project(let id): r = live.filter { $0.projectID == id }
        }
        if !showCompleted { r = r.filter { !$0.isDone } }
        if let tagFilter { r = r.filter { $0.tags.contains(tagFilter) } }
        return r
    }

    var allTags: [String] { Array(Set(allTasks.filter(\.isLive).flatMap(\.tags))).sorted() }

    var isEmbedded: Bool { if case .project = scope { return true } else { return false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isEmbedded {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: header.1)
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(header.2.gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(header.0).font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(header.3).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    toolbar
                }
                .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 16)
            } else {
                HStack { Spacer(); toolbar }.padding(.bottom, 12)
            }

            QuickTaskField(defaultDue: defaultDue, projectID: projectID, status: { if case .inbox = scope { return .inbox } else { return nil } }())
                .padding(.horizontal, isEmbedded ? 0 : 28)
                .padding(.bottom, 14)

            Group {
                switch mode {
                case .list: listView
                case .kanban: BoardView(columns: TaskStatus.allCases.map { s in
                    BoardColumnModel(id: s.rawValue, title: s.title, icon: s.icon, color: s.color, tasks: scoped.filter { $0.status == s }.sorted(by: TaskSort.byPriorityThenTime)) { t in Store.setStatus(t, s, context: context, app: app) }
                })
                case .priority: BoardView(columns: TaskPriority.allCases.reversed().map { p in
                    BoardColumnModel(id: "\(p.rawValue)", title: p.title, icon: p.flag, color: p == .normal ? Palette.purple : p.color, tasks: scoped.filter { $0.priority == p }.sorted(by: TaskSort.byDue)) { t in t.priority = p; t.updatedAt = Date() }
                })
                case .project: BoardView(columns: [BoardColumnModel(id: "none", title: "Projesiz", icon: "tray", color: .gray, tasks: scoped.filter { $0.projectID == nil }.sorted(by: TaskSort.byDue)) { t in t.projectID = nil }] + projects.filter(\.isLive).map { p in
                    BoardColumnModel(id: p.id.uuidString, title: p.name, icon: p.icon, color: p.color, tasks: scoped.filter { $0.projectID == p.id }.sorted(by: TaskSort.byDue)) { t in
                        t.projectID = p.id
                        if t.status == .inbox { t.status = .todo }
                        Store.log(context, "**\(t.title)** → \(p.name)", icon: "arrow.right.circle.fill", color: p.colorHex, projectID: p.id)
                    }
                })
                case .calendar: TaskWeekBoard(tasks: scoped)
                }
            }
            .padding(.horizontal, isEmbedded ? 0 : 28)
        }
    }

    var defaultDue: Date? {
        switch scope {
        case .today: Date().startOfDay
        case .upcoming: Date().startOfDay.adding(days: 1)
        default: nil
        }
    }
    var projectID: UUID? { if case .project(let id) = scope { return id } else { return nil } }

    var toolbar: some View {
        HStack(spacing: 10) {
            if !allTags.isEmpty {
                Menu {
                    Button("Tüm etiketler") { tagFilter = nil }
                    Divider()
                    ForEach(allTags, id: \.self) { t in Button("#\(t)") { tagFilter = t } }
                } label: {
                    Label(tagFilter.map { "#\($0)" } ?? "Etiket", systemImage: "number")
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            Toggle(isOn: $showCompleted) { Image(systemName: "checkmark.circle") }
                .toggleStyle(.button).help("Tamamlananları göster")
            Picker("", selection: $modeRaw) {
                ForEach(TaskViewMode.allCases) { m in
                    Label(m.title, systemImage: m.icon).tag(m.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    // MARK: List view: tarih gruplarına sürükle-bırak

    struct Group_: Identifiable {
        let id: String; let title: String; let color: Color; let target: Date?; let droppable: Bool; let tasks: [TaskItem]
    }

    var groups: [Group_] {
        let today = Date().startOfDay
        let cal = Calendar.current
        let open = scoped.filter { !$0.isDone }
        let done = scoped.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        var g: [Group_] = []
        let overdue = open.filter(\.isOverdue)
        if !overdue.isEmpty { g.append(.init(id: "overdue", title: "Gecikmiş", color: Palette.secondary, target: nil, droppable: false, tasks: overdue.sorted(by: TaskSort.byDue))) }

        switch scope {
        case .upcoming:
            for i in 0..<14 {
                let d = today.adding(days: i)
                let ts = open.filter { !$0.isOverdue && $0.dueDate.map { cal.isDate($0, inSameDayAs: d) } ?? false }
                g.append(.init(id: "d\(i)", title: "\(Fmt.relative(d)) · \(Fmt.dayMonthWeekday.string(from: d))", color: i == 0 ? Palette.success : Palette.info, target: d, droppable: true, tasks: ts.sorted(by: TaskSort.byDue)))
            }
            let later = open.filter { ($0.dueDate ?? .distantPast) >= today.adding(days: 14) }
            if !later.isEmpty { g.append(.init(id: "later", title: "Daha sonra", color: .secondary, target: nil, droppable: false, tasks: later.sorted(by: TaskSort.byDue))) }
        default:
            let todays = open.filter { !$0.isOverdue && ($0.isToday) }
            let tomorrow = open.filter { $0.dueDate.map(cal.isDateInTomorrow) ?? false }
            let week = open.filter { guard let d = $0.dueDate else { return false }; return d >= today.adding(days: 2) && d < today.adding(days: 7) }
            let later = open.filter { ($0.dueDate ?? .distantPast) >= today.adding(days: 7) }
            let none = open.filter { $0.dueDate == nil }
            g.append(.init(id: "today", title: "Bugün", color: Palette.success, target: today, droppable: true, tasks: todays.sorted(by: TaskSort.byPriorityThenTime)))
            if case .today = scope {} else {
                g.append(.init(id: "tomorrow", title: "Yarın", color: Palette.info, target: today.adding(days: 1), droppable: true, tasks: tomorrow.sorted(by: TaskSort.byPriorityThenTime)))
                g.append(.init(id: "week", title: "Bu hafta", color: Palette.purple, target: today.adding(days: 2), droppable: true, tasks: week.sorted(by: TaskSort.byDue)))
                g.append(.init(id: "later", title: "Daha sonra", color: Palette.warning, target: today.adding(days: 7), droppable: true, tasks: later.sorted(by: TaskSort.byDue)))
                g.append(.init(id: "none", title: "Tarihsiz", color: .secondary, target: nil, droppable: true, tasks: none.sorted(by: TaskSort.byPriorityThenTime)))
            }
        }
        if !done.isEmpty { g.append(.init(id: "done", title: "Tamamlanan", color: Palette.success, target: nil, droppable: false, tasks: done)) }
        return g
    }

    var listView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if case .inbox = scope { inboxNotes }
                if scoped.isEmpty {
                    EmptyState(icon: "checkmark.seal", title: "Burada görev yok", subtitle: "Yukarıdaki alandan hızlıca ekle. Örn: “Rapor yaz yarın 14:00 !high”")
                        .card()
                }
                ForEach(groups) { g in
                    if !g.tasks.isEmpty || (g.droppable && !isEmbeddedEmptyHidden(g)) {
                        DayGroupView(group: g)
                    }
                }
            }
            .padding(.bottom, 30)
        }
    }

    func isEmbeddedEmptyHidden(_ g: Group_) -> Bool {
        // Upcoming'de boş günleri göstermek sürükleme için faydalı; diğerlerinde boş grupları gizle
        if case .upcoming = scope { return false }
        return true
    }

    @ViewBuilder var inboxNotes: some View {
        let inbox = notes.filter { $0.isLive && $0.projectID == nil && $0.folderID == nil }
        if !inbox.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Kategorize edilmemiş notlar", systemImage: "note.text").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.warning)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(inbox) { n in
                            Button { app.selectedNoteID = n.id; app.go(.notes) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(n.title.isEmpty ? "Başlıksız" : n.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(n.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    Spacer(minLength: 0)
                                    Text(Fmt.ago(n.updatedAt)).font(.caption2).foregroundStyle(.tertiary)
                                }
                                .frame(width: 190, height: 80, alignment: .topLeading)
                                .card(padding: 12)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 6).padding(.horizontal, 2)
                }
            }
        }
    }
}

struct DayGroupView: View {
    let group: TaskCollectionView.Group_
    @Environment(\.modelContext) var context
    @Query var tasks: [TaskItem]
    @State private var targeted = false
    @State private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(.snappy) { collapsed.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(collapsed ? 0 : 90)).foregroundStyle(.tertiary)
                    Circle().fill(group.color).frame(width: 8, height: 8)
                    Text(group.title).font(.system(size: 13.5, weight: .semibold))
                    Text("\(group.tasks.count)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)

            if !collapsed {
                VStack(spacing: 2) {
                    ForEach(group.tasks) { TaskRow(task: $0) }
                    if group.tasks.isEmpty {
                        Text(group.droppable ? "Görevi buraya sürükle" : "")
                            .font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(targeted ? group.color.opacity(0.12) : Color.primary.opacity(0.025))
                )
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(targeted ? group.color.opacity(0.6) : .clear, style: StrokeStyle(lineWidth: 1.5, dash: [5])))
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            guard group.droppable else { return false }
            let found = tasks.filter { ids.contains($0.id.uuidString) }
            found.forEach { Store.reschedule($0, to: group.target, context: context) }
            return !found.isEmpty
        } isTargeted: { targeted = $0 && group.droppable }
    }
}

// MARK: - Board

struct BoardColumnModel: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let tasks: [TaskItem]
    let onDrop: (TaskItem) -> Void
}

struct BoardView: View {
    let columns: [BoardColumnModel]
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(columns) { BoardColumn(model: $0) }
            }
            .padding(.bottom, 20)
        }
    }
}

struct BoardColumn: View {
    let model: BoardColumnModel
    @Query var tasks: [TaskItem]
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: model.icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(RoundedRectangle(cornerRadius: 6).fill(model.color.gradient))
                Text(model.title).font(.system(size: 13.5, weight: .semibold))
                Text("\(model.tasks.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.primary.opacity(0.07)))
                Spacer()
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.tasks) { t in
                        TaskRow(task: t)
                            .padding(4)
                            .card(padding: 2)
                    }
                    if model.tasks.isEmpty {
                        Text("Buraya sürükle").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, minHeight: 60)
                    }
                }
                .padding(2)
            }
        }
        .padding(12)
        .frame(width: 290)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(targeted ? model.color.opacity(0.14) : model.color.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(model.color.opacity(targeted ? 0.6 : 0.12), lineWidth: targeted ? 1.5 : 1))
        .dropDestination(for: String.self) { ids, _ in
            let found = tasks.filter { ids.contains($0.id.uuidString) }
            withAnimation(.snappy) { found.forEach(model.onDrop) }
            return !found.isEmpty
        } isTargeted: { targeted = $0 }
    }
}

// MARK: - Task calendar (hafta panosu)

struct TaskWeekBoard: View {
    let tasks: [TaskItem]
    @State private var weekStart = Date().startOfWeek

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Fmt.monthYear.string(from: weekStart).capitalized(with: Fmt.locale)).font(.title3.weight(.semibold))
                Spacer()
                Button { weekStart = weekStart.adding(days: -7) } label: { Image(systemName: "chevron.left") }
                Button("Bugün") { weekStart = Date().startOfWeek }
                Button { weekStart = weekStart.adding(days: 7) } label: { Image(systemName: "chevron.right") }
            }
            BoardView(columns: (0..<7).map { i in
                let d = weekStart.adding(days: i)
                let isToday = Calendar.current.isDateInToday(d)
                return BoardColumnModel(
                    id: "\(i)",
                    title: "\(Fmt.weekdayShort.string(from: d).capitalized(with: Fmt.locale)) \(Calendar.current.component(.day, from: d))",
                    icon: isToday ? "sun.max.fill" : "calendar",
                    color: isToday ? Palette.warning : Palette.info,
                    tasks: tasks.filter { $0.dueDate.map { Calendar.current.isDate($0, inSameDayAs: d) } ?? false }.sorted(by: TaskSort.byDue)
                ) { t in
                    if let ctx = t.modelContext { Store.reschedule(t, to: d, context: ctx) }
                }
            })
        }
    }
}

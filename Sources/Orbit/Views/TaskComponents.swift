import SwiftUI
import SwiftData

/// Tamamlama animasyonlu checkbox: halka dolar, tik çizilir, küçük parçacıklar saçılır.
struct CompletionCheckbox: View {
    let done: Bool
    let color: Color
    var size: CGFloat = 20
    let action: () -> Void
    @State private var burst: Double = 0
    @State private var pressed = false

    var body: some View {
        Button {
            if !done {
                burst = 0
                withAnimation(.easeOut(duration: 0.55)) { burst = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { burst = 0 }
            }
            action()
        } label: {
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    Circle()
                        .fill([Palette.success, Palette.warning, Palette.primary, Palette.info][i % 4])
                        .frame(width: 4, height: 4)
                        .modifier(BurstEffect(progress: burst, distance: size * 0.95))
                        .rotationEffect(.degrees(Double(i) * 45))
                }
                Circle()
                    .strokeBorder(done ? Palette.success : color, lineWidth: 1.6)
                    .background(Circle().fill(done ? Palette.success : color.opacity(0.08)))
                    .frame(width: size, height: size)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .heavy))
                    .foregroundStyle(.white)
                    .scaleEffect(done ? 1 : 0.2)
                    .opacity(done ? 1 : 0)
            }
            .scaleEffect(pressed ? 0.85 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: done)
            .frame(width: size + 4, height: size + 4)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct BurstEffect: ViewModifier, Animatable {
    var progress: Double
    var distance: CGFloat
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content
            .offset(y: -distance * progress)
            .scaleEffect(1 - progress * 0.5)
            .opacity(progress <= 0.001 ? 0 : 1 - progress)
    }
}

struct TaskRow: View {
    @Bindable var task: TaskItem
    var showProject = true
    var compact = false
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) var context
    @Query var projects: [Project]
    @State private var hovering = false

    var project: Project? { projects.first { $0.id == task.projectID } }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CompletionCheckbox(done: task.isDone, color: task.priority.color == .secondary ? .secondary : task.priority.color) {
                Store.toggleComplete(task, context: context, app: app)
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .strikethrough(task.isDone, color: .secondary)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .lineLimit(compact ? 1 : 2)
                    if task.priority >= .high && !task.isDone {
                        Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(task.priority.color)
                    }
                }
                if !compact { meta }
            }
            Spacer(minLength: 4)
            if compact, let due = task.dueDate {
                Text(task.hasTime ? Fmt.time.string(from: due) : Fmt.relative(due))
                    .font(.caption).foregroundStyle(task.isOverdue ? Palette.secondary : .secondary)
            }
            if hovering && !task.isDone {
                Menu {
                    snoozeItems
                } label: {
                    Image(systemName: "moon.zzz").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Ertele")
            }
        }
        .padding(.vertical, compact ? 5 : 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.045) : .clear)
        )
        .overlay(alignment: .leading) {
            if task.isOverdue {
                RoundedRectangle(cornerRadius: 1).fill(Palette.secondary.opacity(0.6)).frame(width: 2).padding(.vertical, 9)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { app.editingTask = task }
        .draggable(task.id.uuidString) {
            Label(task.title, systemImage: "checkmark.circle").padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .contextMenu { contextItems }
        .animation(.easeInOut(duration: 0.25), value: task.isDone)
    }

    @ViewBuilder var meta: some View {
        let items = metaItems
        if !items.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(items.indices, id: \.self) { items[$0].fixedSize() }
            }
        }
    }

    var metaItems: [AnyView] {
        var v: [AnyView] = []
        if let due = task.dueDate {
            let label = Fmt.relative(due) + (task.hasTime ? " · \(Fmt.time.string(from: due))" : "")
            let color: Color = task.isDone ? Palette.success : task.isOverdue ? Palette.secondary : task.isToday ? Palette.success : Palette.info
            v.append(AnyView(Pill(text: label, icon: task.isOverdue ? "exclamationmark.circle" : "calendar", color: color)))
        }
        if task.status == .inProgress { v.append(AnyView(Pill(text: "In Progress", icon: "circle.lefthalf.filled", color: Palette.warning))) }
        if task.recurrence.isActive { v.append(AnyView(Pill(text: task.recurrence.summary, icon: "repeat", color: Palette.purple))) }
        if task.estimateMinutes > 0 { v.append(AnyView(Pill(text: Fmt.duration(task.estimateMinutes), icon: "hourglass"))) }
        if task.focusMinutes > 0 { v.append(AnyView(Pill(text: Fmt.duration(task.focusMinutes), icon: "timer", color: Palette.secondary))) }
        let (d, t) = task.subtaskProgress
        if t > 0 { v.append(AnyView(Pill(text: "\(d)/\(t)", icon: "checklist", color: d == t ? Palette.success : .secondary))) }
        if task.reminder != nil { v.append(AnyView(Image(systemName: "bell.fill").font(.system(size: 9)).foregroundStyle(Palette.warning))) }
        for tag in task.tags.prefix(3) { v.append(AnyView(Text("#\(tag)").font(.system(size: 11)).foregroundStyle(Palette.purple))) }
        if showProject, let p = project {
            v.append(AnyView(HStack(spacing: 4) {
                Circle().fill(p.color).frame(width: 7, height: 7)
                Text(p.name).font(.system(size: 11)).foregroundStyle(.secondary)
            }))
        }
        return v
    }

    @ViewBuilder var snoozeItems: some View {
        Button("Today") { Store.snooze(task, days: 0, context: context, app: app) }
        Button("Tomorrow") { Store.snooze(task, days: 1, context: context, app: app) }
        Button("2 gün sonra") { Store.snooze(task, days: 2, context: context, app: app) }
        Button("Gelecek hafta") { Store.snooze(task, days: 7, context: context, app: app) }
        Button("Tarihi kaldır") { Store.reschedule(task, to: nil, context: context) }
    }

    @ViewBuilder var contextItems: some View {
        Button(task.isDone ? "Tamamlanmadı olarak işaretle" : "Tamamla") { Store.toggleComplete(task, context: context, app: app) }
        Button("Düzenle…") { app.editingTask = task }
        Button("Odaklan (Pomodoro)") {
            FocusTimer.shared.start(task: task)
            app.go(.focus)
        }
        Menu("Ertele") { snoozeItems }
        Menu("Durum") {
            ForEach(TaskStatus.allCases) { s in Button(s.title) { Store.setStatus(task, s, context: context, app: app) } }
        }
        Menu("Öncelik") {
            ForEach(TaskPriority.allCases.reversed()) { p in Button(p.title) { task.priority = p } }
        }
        Menu("Proje") {
            Button("Yok") { task.projectID = nil }
            ForEach(projects.filter(\.isLive)) { p in Button(p.name) { task.projectID = p.id } }
        }
        Divider()
        Button("Arşivle") { task.archived = true }
        Button("Sil", role: .destructive) { Store.trash(task, context: context, app: app) }
    }
}

/// Satır içi hızlı görev ekleme: "Rapor yaz yarın 14:00 !high #proje"
struct QuickTaskField: View {
    var placeholder = "Hızlı görev ekle… (yarın 14:00 !high #proje)"
    var defaultDue: Date? = nil
    var projectID: UUID? = nil
    var status: TaskStatus? = nil
    @State private var text = ""
    @FocusState private var focused: Bool
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) var context
    @Query var projects: [Project]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor).font(.system(size: 17))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(submit)
            if !text.isEmpty {
                Text("↩").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(focused ? 0.07 : 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(focused ? Color.accentColor.opacity(0.5) : .clear))
    }

    func submit() {
        let parsed = QuickParser.parse(text, projects: projects)
        guard !parsed.title.isEmpty else { return }
        let due = parsed.due ?? defaultDue
        Store.createTask(context: context, title: parsed.title, status: status, priority: parsed.priority ?? .normal, due: due, hasTime: parsed.hasTime, projectID: parsed.projectID ?? projectID, tags: parsed.tags)
        app.show(Toast(text: "Görev eklendi", icon: "plus.circle.fill", color: Palette.info))
        text = ""
    }
}

enum QuickParser {
    struct Result { var title: String; var due: Date?; var hasTime: Bool; var priority: TaskPriority?; var projectID: UUID?; var tags: [String] }

    static func parse(_ input: String, projects: [Project]) -> Result {
        var words = input.split(separator: " ").map(String.init)
        var r = Result(title: "", due: nil, hasTime: false, priority: nil, projectID: nil, tags: [])
        var day: Date?
        var time: (Int, Int)?
        let today = Date().startOfDay
        var keep: [String] = []
        let tr = Locale(identifier: "tr_TR")
        for w in words {
            let lw = w.lowercased(with: tr)
            switch lw {
            case "bugün", "today": day = today
            case "yarın", "tomorrow": day = today.adding(days: 1)
            case "haftaya": day = today.adding(days: 7)
            case "!low", "!1": r.priority = .low
            case "!normal", "!2": r.priority = .normal
            case "!high", "!3": r.priority = .high
            case "!urgent", "!4", "!!": r.priority = .urgent
            default:
                if let m = lw.wholeMatch(of: /(\d{1,2})[:.](\d{2})/), let h = Int(m.1), let mi = Int(m.2), h < 24, mi < 60 {
                    time = (h, mi)
                } else if lw.hasPrefix("#"), lw.count > 1 {
                    let key = String(lw.dropFirst())
                    if let p = projects.first(where: { $0.isLive && $0.name.lowercased(with: tr).replacingOccurrences(of: " ", with: "").hasPrefix(key) }) {
                        r.projectID = p.id
                    } else { r.tags.append(key) }
                } else { keep.append(w) }
            }
        }
        words = keep
        r.title = words.joined(separator: " ")
        if let time {
            r.due = (day ?? today).at(hour: time.0, minute: time.1)
            r.hasTime = true
        } else { r.due = day }
        return r
    }
}

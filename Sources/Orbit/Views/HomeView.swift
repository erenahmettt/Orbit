import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) var context
    @Query var tasks: [TaskItem]
    @Query(sort: \Project.updatedAt, order: .reverse) var projects: [Project]
    @Query(sort: \Note.updatedAt, order: .reverse) var notes: [Note]
    @Query(sort: \CalEvent.start) var events: [CalEvent]
    @AppStorage("userName") var userName = ""

    var live: [TaskItem] { tasks.filter(\.isLive) }
    var todayTasks: [TaskItem] {
        live.filter { $0.isToday || ($0.isOverdue) || ($0.isDone && ($0.completedAt.map(Calendar.current.isDateInToday) ?? false)) }
            .sorted(by: TaskSort.byPriorityThenTime)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                WelcomeCard(userName: userName)
                GettingStartedCard()
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], alignment: .leading, spacing: 20) {
                    TodaysFocusCard(tasks: todayTasks)
                    ScheduleCard(events: events.filter { $0.deletedAt == nil }, tasks: live)
                    UpcomingCard(tasks: live)
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 20) {
                    ActiveProjectsCard(projects: projects.filter { $0.isLive && $0.status != .completed }, tasks: live)
                    QuickNotesCard(notes: notes.filter(\.isLive))
                }
            }
            .padding(28)
            .frame(maxWidth: 1500)
            .frame(maxWidth: .infinity)
        }
    }
}

enum TaskSort {
    static func byPriorityThenTime(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        if a.isOverdue != b.isOverdue { return a.isOverdue }
        if a.priority != b.priority { return a.priority > b.priority }
        return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
    }
    static func byDue(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        let da = a.dueDate ?? .distantFuture, db = b.dueDate ?? .distantFuture
        if da != db { return da < db }
        return a.priority > b.priority
    }
}

// MARK: - Welcome

struct WelcomeCard: View {
    let userName: String
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) var context
    @State private var noteText = ""
    @Query var tasks: [TaskItem]

    func greeting(_ d: Date) -> (String, String) {
        let h = Calendar.current.component(.hour, from: d)
        let who = userName.isEmpty ? "" : ", \(userName)"
        switch h {
        case 5..<12: return ("Günaydın\(who)", "sun.horizon.fill")
        case 12..<18: return ("İyi günler\(who)", "sun.max.fill")
        case 18..<22: return ("İyi akşamlar\(who)", "sunset.fill")
        default: return ("İyi geceler\(who)", "moon.stars.fill")
        }
    }

    var body: some View {
        let openToday = tasks.filter { $0.isLive && !$0.isDone && ($0.isToday || $0.isOverdue) }.count
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let (g, icon) = greeting(ctx.date)
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Fmt.longDate.string(from: ctx.date).uppercased(with: Fmt.locale))
                        .font(.system(size: 11.5, weight: .semibold)).kerning(1.2)
                        .foregroundStyle(.white.opacity(0.75))
                    HStack(spacing: 10) {
                        Image(systemName: icon).symbolRenderingMode(.multicolor)
                        Text(g)
                    }
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    Text(openToday == 0 ? "Bugün için açık görev yok. Harika bir gün! ✨" : "Bugün seni bekleyen \(openToday) görev var. Hadi başlayalım.")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.85))
                    HStack(spacing: 10) {
                        QuickTaskField(placeholder: "Hızlı görev… (yarın 14:00 !high)", defaultDue: Date().startOfDay)
                            .colorScheme(.dark)
                        HStack(spacing: 8) {
                            Image(systemName: "note.text").foregroundStyle(Palette.warning)
                            TextField("Hızlı not…", text: $noteText)
                                .textFieldStyle(.plain)
                                .onSubmit(saveNote)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.1)))
                        .colorScheme(.dark)
                    }
                    .padding(.top, 8)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.time.string(from: ctx.date))
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(Calendar.current.component(.second, from: ctx.date).formatted(.number.precision(.integerLength(2))))
                        .font(.system(size: 14, weight: .medium, design: .rounded)).monospacedDigit()
                        .opacity(0.6)
                }
                .foregroundStyle(.white)
            }
            .padding(28)
            .background(
                ZStack {
                    LinearGradient(colors: [Palette.primary, Palette.purple, Color(hex: "#E86BA8")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(Palette.teal.opacity(0.45)).frame(width: 300).blur(radius: 70).offset(x: 380, y: 90)
                    Circle().fill(Palette.info.opacity(0.5)).frame(width: 260).blur(radius: 70).offset(x: -360, y: -110)
                    Ellipse().stroke(.white.opacity(0.13), lineWidth: 1.5).frame(width: 560, height: 160).rotationEffect(.degrees(-12)).offset(x: 300)
                    Ellipse().stroke(.white.opacity(0.08), lineWidth: 1.5).frame(width: 780, height: 220).rotationEffect(.degrees(-12)).offset(x: 300)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Palette.primary.opacity(0.35), radius: 24, y: 12)
        }
    }

    func saveNote() {
        let t = noteText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let title = String(t.prefix(48))
        Store.createNote(context: context, title: title, body: t)
        app.show(Toast(text: "Not Inbox'a eklendi", icon: "note.text.badge.plus", color: Palette.warning))
        noteText = ""
    }
}

// MARK: - Today's focus

struct TodaysFocusCard: View {
    let tasks: [TaskItem]
    @EnvironmentObject var app: AppState

    var body: some View {
        let done = tasks.filter(\.isDone).count
        let total = tasks.count
        let ratio = total == 0 ? 0 : Double(done) / Double(total)
        let priority = tasks.filter { !$0.isDone && $0.priority >= .high }.count
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Today's Focus", icon: "scope", color: Palette.warning, trailing: AnyView(
                Button("Tümü") { app.go(.today) }.buttonStyle(.link).font(.caption)
            ))
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(progress: ratio, lineWidth: 9, color: Palette.success)
                    VStack(spacing: 0) {
                        Text("\(Int(ratio * 100))%").font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("bitti").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 78, height: 78)
                VStack(alignment: .leading, spacing: 8) {
                    stat("\(done)/\(total)", "tamamlandı", Palette.success)
                    stat("\(priority)", "öncelikli görev", Palette.warning)
                }
            }
            Divider().opacity(0.5)
            if tasks.isEmpty {
                EmptyState(icon: "sun.max", title: "Bugün boş", subtitle: "Yukarıdan hızlıca görev ekle.")
            } else {
                VStack(spacing: 2) {
                    ForEach(tasks.prefix(7)) { TaskRow(task: $0, compact: true) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }

    func stat(_ v: String, _ label: String, _ c: Color) -> some View {
        HStack(spacing: 8) {
            Text(v).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(c)
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Schedule

struct ScheduleCard: View {
    let events: [CalEvent]
    let tasks: [TaskItem]
    @EnvironmentObject var app: AppState
    @EnvironmentObject var apple: AppleCalendar

    struct Item: Identifiable {
        let id: String; let title: String; let start: Date; let end: Date; let color: Color; let isTask: Bool
    }

    var items: [Item] {
        let today = Date().startOfDay, tomorrow = today.adding(days: 1)
        var r = events.filter { $0.start >= today && $0.start < tomorrow }
            .map { Item(id: $0.id.uuidString, title: $0.title, start: $0.start, end: $0.end, color: $0.color, isTask: false) }
        r += tasks.filter { $0.hasTime && $0.isToday && !$0.isDone }
            .map { Item(id: $0.id.uuidString, title: $0.title, start: $0.dueDate!, end: $0.dueDate!.adding(minutes: max(15, $0.estimateMinutes)), color: Palette.success, isTask: true) }
        r += apple.events(from: today, to: tomorrow).filter { !$0.allDay }
            .map { Item(id: $0.id, title: $0.title, start: $0.start, end: $0.end, color: $0.color, isTask: false) }
        return r.sorted { $0.start < $1.start }
    }

    var upcoming: [CalEvent] {
        let t = Date().startOfDay.adding(days: 1)
        return events.filter { $0.start >= t }.prefix(3).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Schedule", icon: "clock.fill", color: Palette.info, trailing: AnyView(
                Button("Takvim") { app.go(.calendar) }.buttonStyle(.link).font(.caption)
            ))
            if items.isEmpty {
                EmptyState(icon: "calendar", title: "Bugün etkinlik yok")
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, it in
                            let isNow = it.start <= ctx.date && it.end > ctx.date
                            let past = it.end <= ctx.date
                            HStack(alignment: .top, spacing: 12) {
                                Text(Fmt.time.string(from: it.start))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                                    .foregroundStyle(isNow ? it.color : .secondary)
                                    .frame(width: 40, alignment: .trailing)
                                VStack(spacing: 0) {
                                    Circle().fill(past ? Color.secondary.opacity(0.4) : it.color).frame(width: 9, height: 9)
                                        .overlay(Circle().stroke(it.color.opacity(isNow ? 0.35 : 0), lineWidth: 5))
                                        .padding(.top, 3)
                                    if idx < items.count - 1 {
                                        Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1.5).frame(minHeight: 26)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        if it.isTask { Image(systemName: "checkmark.circle").font(.caption).foregroundStyle(it.color) }
                                        Text(it.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                            .foregroundStyle(past ? .secondary : .primary)
                                    }
                                    Text("\(Fmt.time.string(from: it.start)) – \(Fmt.time.string(from: it.end))" + (isNow ? " · şimdi" : ""))
                                        .font(.caption).foregroundStyle(isNow ? it.color : .secondary)
                                }
                                .padding(.bottom, 10)
                                Spacer()
                            }
                        }
                    }
                }
            }
            if !upcoming.isEmpty {
                Divider().opacity(0.5)
                Text("YAKLAŞAN").font(.system(size: 10.5, weight: .semibold)).kerning(1).foregroundStyle(.tertiary)
                ForEach(upcoming) { e in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 3, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            Text("\(Fmt.relative(e.start)) · \(Fmt.time.string(from: e.start))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }
}

// MARK: - Upcoming

struct UpcomingCard: View {
    let tasks: [TaskItem]
    @EnvironmentObject var app: AppState

    var body: some View {
        let open = tasks.filter { !$0.isDone }
        let overdue = open.filter(\.isOverdue).sorted(by: TaskSort.byDue)
        let tomorrow = Date().startOfDay.adding(days: 1)
        let next = open.filter { ($0.dueDate ?? .distantPast) >= tomorrow && ($0.dueDate ?? .distantFuture) < tomorrow.adding(days: 7) }.sorted(by: TaskSort.byDue)
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Upcoming Tasks", icon: "calendar.badge.clock", color: Palette.teal, trailing: AnyView(
                Button("Tümü") { app.go(.upcoming) }.buttonStyle(.link).font(.caption)
            ))
            if !overdue.isEmpty {
                Label("Gecikmiş · \(overdue.count)", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.secondary)
                VStack(spacing: 2) { ForEach(overdue.prefix(3)) { TaskRow(task: $0, compact: true) } }
            }
            Text("ÖNÜMÜZDEKİ 7 GÜN").font(.system(size: 10.5, weight: .semibold)).kerning(1).foregroundStyle(.tertiary)
            if next.isEmpty {
                Text("Yaklaşan görev yok.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) { ForEach(next.prefix(7)) { TaskRow(task: $0, compact: true) } }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }
}

// MARK: - Projects

struct ActiveProjectsCard: View {
    let projects: [Project]
    let tasks: [TaskItem]
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Active Projects", icon: "square.stack.3d.up.fill", color: Palette.purple, trailing: AnyView(
                Button("Tümü") { app.go(.projects) }.buttonStyle(.link).font(.caption)
            ))
            if projects.isEmpty {
                VStack(spacing: 10) {
                    EmptyState(icon: "square.stack.3d.up", title: "Henüz proje yok", subtitle: "Projeler; görevlerini, notlarını ve etkinliklerini bir arada tutan çalışma alanlarıdır.")
                    Button { app.go(.projects) } label: { Label("Proje oluştur", systemImage: "plus") }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                ForEach(projects.prefix(6)) { p in
                    let prog = Store.progress(of: p, tasks: tasks)
                    Button { app.go(.project(p.id)) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                ProjectBadge(project: p, size: 30)
                                Spacer()
                                Text(Fmt.ago(p.updatedAt)).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text(p.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            ProgressView(value: prog.ratio).tint(p.color)
                            HStack {
                                Text("\(prog.done)/\(prog.total) görev").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(prog.ratio * 100))%").font(.caption.weight(.semibold)).foregroundStyle(p.color)
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.color.opacity(0.09)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.color.opacity(0.18)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}

// MARK: - Quick notes

struct QuickNotesCard: View {
    let notes: [Note]
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) var context
    @AppStorage("scratchpad") var scratch = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Quick Notes", icon: "note.text", color: Palette.warning, trailing: AnyView(
                Button("Nota çevir") {
                    let t = scratch.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    Store.createNote(context: context, title: String(t.split(separator: "\n").first?.prefix(48) ?? "Hızlı not"), body: t)
                    scratch = ""
                    app.show(Toast(text: "Not kaydedildi", icon: "note.text.badge.plus", color: Palette.warning))
                }.buttonStyle(.link).font(.caption)
            ))
            TextEditor(text: $scratch)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 90)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.warning.opacity(0.08)))
                .overlay(alignment: .topLeading) {
                    if scratch.isEmpty {
                        Text("Aklına geleni yaz… (otomatik kaydedilir)").font(.system(size: 13)).foregroundStyle(.tertiary).padding(13).allowsHitTesting(false)
                    }
                }
            let pinned = notes.filter(\.pinned)
            let recent = notes.filter { !$0.pinned }.prefix(4)
            if !pinned.isEmpty {
                Text("SABİTLENMİŞ").font(.system(size: 10.5, weight: .semibold)).kerning(1).foregroundStyle(.tertiary)
                ForEach(pinned.prefix(3)) { noteRow($0, pinned: true) }
            }
            if !recent.isEmpty {
                Text("SON EKLENENLER").font(.system(size: 10.5, weight: .semibold)).kerning(1).foregroundStyle(.tertiary)
                ForEach(Array(recent)) { noteRow($0, pinned: false) }
            }
        }
        .frame(width: 380)
        .card()
    }

    func noteRow(_ n: Note, pinned: Bool) -> some View {
        Button {
            app.selectedNoteID = n.id
            app.go(.notes)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: pinned ? "pin.fill" : "doc.text").font(.caption).foregroundStyle(pinned ? Palette.purple : .secondary).frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(n.title.isEmpty ? "Başlıksız" : n.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    if !n.preview.isEmpty { Text(n.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                Text(Fmt.ago(n.updatedAt)).font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI
import SwiftData

enum CalMode: String, CaseIterable, Identifiable {
    case day, week, month, agenda
    var id: String { rawValue }
    var title: String { switch self { case .day: "Day"; case .week: "Week"; case .month: "Month"; case .agenda: "Agenda" } }
}

/// Takvimde gösterilecek birleşik öğe: etkinlik, saatli görev veya Apple Calendar etkinliği
struct CalItem: Identifiable {
    enum Kind { case event(CalEvent), task(TaskItem), external(ExternalEvent) }
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
    let kind: Kind
    var dragID: String? {
        switch kind {
        case .event(let e): "event:\(e.id.uuidString)"
        case .task(let t): t.id.uuidString
        case .external: nil
        }
    }
    var isTask: Bool { if case .task = kind { true } else { false } }
    var isDone: Bool { if case .task(let t) = kind { t.isDone } else { false } }
}

struct CalendarScreen: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var apple: AppleCalendar
    @Environment(\.modelContext) var context
    @Query(sort: \CalEvent.start) var events: [CalEvent]
    @Query var tasks: [TaskItem]
    @Query var projects: [Project]
    @AppStorage("calMode") var modeRaw = CalMode.week.rawValue
    @State private var editingEvent: CalEvent?
    @State private var projectFilter: UUID?

    var mode: CalMode { CalMode(rawValue: modeRaw) ?? .week }
    var date: Date { app.calendarDate }

    var title: String {
        switch mode {
        case .day: return Fmt.longDate.string(from: date)
        case .week:
            let s = date.startOfWeek, e = s.adding(days: 6)
            return "\(Fmt.dayMonth.string(from: s)) – \(Fmt.dayMonth.string(from: e)) \(Calendar.current.component(.year, from: e))"
        case .month, .agenda: return Fmt.monthYear.string(from: date).capitalized(with: Fmt.locale)
        }
    }

    func items(from start: Date, to end: Date) -> [CalItem] {
        _ = apple.revision
        var r: [CalItem] = events.filter { $0.deletedAt == nil && $0.end > start && $0.start < end && (projectFilter == nil || $0.projectID == projectFilter) }
            .map { CalItem(id: $0.id.uuidString, title: $0.title, start: $0.start, end: $0.end, color: $0.color, kind: .event($0)) }
        r += tasks.filter { $0.isLive && $0.hasTime && ($0.dueDate.map { $0 >= start && $0 < end } ?? false) && (projectFilter == nil || $0.projectID == projectFilter) }
            .map { t in
                let c = projects.first { $0.id == t.projectID }?.color ?? Palette.success
                return CalItem(id: t.id.uuidString, title: t.title, start: t.dueDate!, end: t.dueDate!.adding(minutes: max(30, t.estimateMinutes)), color: t.isDone ? Palette.success : c, kind: .task(t))
            }
        if projectFilter == nil {
            r += apple.events(from: start, to: end).filter { !$0.allDay }
                .map { CalItem(id: $0.id, title: $0.title, start: $0.start, end: $0.end, color: $0.color, kind: .external($0)) }
        }
        return r.sorted { $0.start < $1.start }
    }

    func dayTasks(_ day: Date) -> [TaskItem] {
        tasks.filter { $0.isLive && !$0.hasTime && ($0.dueDate.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false) && (projectFilter == nil || $0.projectID == projectFilter) }
            .sorted(by: TaskSort.byPriorityThenTime)
    }

    func step(_ dir: Int) {
        let cal = Calendar.current
        withAnimation(.snappy) {
            switch mode {
            case .day: app.calendarDate = date.adding(days: dir)
            case .week: app.calendarDate = date.adding(days: 7 * dir)
            case .month, .agenda: app.calendarDate = cal.date(byAdding: .month, value: dir, to: date)!
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "calendar").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.blue.gradient))
                Text(title).font(.system(size: 24, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Spacer()
                Menu {
                    Button("Tüm projeler") { projectFilter = nil }
                    Divider()
                    ForEach(projects.filter(\.isLive)) { p in Button(p.name) { projectFilter = p.id } }
                } label: {
                    Label(projects.first { $0.id == projectFilter }?.name ?? "Tüm projeler", systemImage: "line.3.horizontal.decrease.circle")
                }.menuStyle(.borderlessButton).fixedSize()
                HStack(spacing: 2) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    Button("Bugün") { withAnimation(.snappy) { app.calendarDate = Date() } }
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                }
                Picker("", selection: $modeRaw) {
                    ForEach(CalMode.allCases) { Text($0.title).tag($0.rawValue) }
                }.pickerStyle(.segmented).fixedSize()
                Button { newEvent(at: Date().at(hour: Calendar.current.component(.hour, from: Date()) + 1)) } label: {
                    Label("Etkinlik", systemImage: "plus")
                }.buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 16)

            Group {
                switch mode {
                case .day: TimeGrid(days: [date.startOfDay], screen: self)
                case .week: TimeGrid(days: (0..<7).map { date.startOfWeek.adding(days: $0) }, screen: self)
                case .month: MonthGrid(screen: self)
                case .agenda: AgendaList(screen: self)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 20)
        }
        .sheet(item: $editingEvent) { EventEditor(event: $0) }
    }

    func newEvent(at start: Date) {
        let e = CalEvent(title: "", start: start, end: start.adding(minutes: 60), colorHex: projects.first { $0.id == projectFilter }?.colorHex ?? "#55A7E8", projectID: projectFilter)
        context.insert(e)
        editingEvent = e
    }

    func edit(_ item: CalItem) {
        switch item.kind {
        case .event(let e): editingEvent = e
        case .task(let t): app.editingTask = t
        case .external: break
        }
    }

    /// Sürüklenen öğeyi yeni zamana taşır. time == nil ise yalnızca gün değişir.
    func handleDrop(_ ids: [String], day: Date, time: Date?) -> Bool {
        var ok = false
        for id in ids {
            if id.hasPrefix("event:"), let uuid = UUID(uuidString: String(id.dropFirst(6))), let e = events.first(where: { $0.id == uuid }) {
                let dur = e.end.timeIntervalSince(e.start)
                let newStart = time ?? day.at(hour: Calendar.current.component(.hour, from: e.start), minute: Calendar.current.component(.minute, from: e.start))
                e.start = newStart
                e.end = newStart.addingTimeInterval(dur)
                ok = true
            } else if let t = tasks.first(where: { $0.id.uuidString == id }) {
                Store.reschedule(t, to: day, time: time, context: context)
                ok = true
            }
        }
        return ok
    }
}

// MARK: - Zaman ızgarası (Day / Week)

struct TimeGrid: View {
    let days: [Date]
    let screen: CalendarScreen
    let hourH: CGFloat = 54
    let gutter: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            // Gün başlıkları + saatsiz görevler
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: gutter)
                ForEach(days, id: \.self) { d in
                    AllDayCell(day: d, tasks: screen.dayTasks(d), screen: screen, showHeader: true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d:00", h)).font(.system(size: 10.5, weight: .medium)).monospacedDigit()
                                    .foregroundStyle(.tertiary)
                                    .frame(width: gutter - 8, height: hourH, alignment: .topTrailing)
                                    .offset(y: -6)
                                    .id(h)
                            }
                        }
                        ForEach(days, id: \.self) { d in
                            DayColumn(day: d, items: screen.items(from: d, to: d.adding(days: 1)), screen: screen, hourH: hourH)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(max(0, Calendar.current.component(.hour, from: Date()) - 2), anchor: .top) }
            }
            .card(padding: 0)
        }
    }
}

struct AllDayCell: View {
    let day: Date
    let tasks: [TaskItem]
    let screen: CalendarScreen
    var showHeader: Bool
    @State private var targeted = false

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        VStack(alignment: .leading, spacing: 4) {
            if showHeader {
                HStack(spacing: 6) {
                    Text(Fmt.weekdayShort.string(from: day).capitalized(with: Fmt.locale)).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(isToday ? .white : .primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(isToday ? Color.accentColor : .clear))
                }
            }
            ForEach(tasks.prefix(3)) { t in
                HStack(spacing: 4) {
                    Image(systemName: t.isDone ? "checkmark.circle.fill" : "circle").font(.system(size: 9))
                    Text(t.title).lineLimit(1)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(t.isDone ? Palette.success : (t.isOverdue ? Palette.secondary : .primary))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill((t.isDone ? Palette.success : Palette.info).opacity(0.12)))
                .onTapGesture { screen.app.editingTask = t }
                .draggable(t.id.uuidString)
            }
            if tasks.count > 3 { Text("+\(tasks.count - 3) görev").font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: showHeader ? 44 : 0, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(targeted ? Palette.info.opacity(0.15) : .clear))
        .dropDestination(for: String.self) { ids, _ in screen.handleDrop(ids, day: day, time: nil) } isTargeted: { targeted = $0 }
    }
}

struct DayColumn: View {
    let day: Date
    let items: [CalItem]
    let screen: CalendarScreen
    let hourH: CGFloat

    struct Placed: Identifiable { let item: CalItem; let col: Int; let cols: Int; var id: String { item.id } }

    /// Çakışan öğeleri yan yana sütunlara yerleştirir
    var placed: [Placed] {
        var result: [Placed] = []
        var cluster: [(CalItem, Int)] = []
        var clusterEnd = Date.distantPast
        func flush() {
            let n = (cluster.map(\.1).max() ?? 0) + 1
            result += cluster.map { Placed(item: $0.0, col: $0.1, cols: n) }
            cluster = []
        }
        for it in items {
            if it.start >= clusterEnd { flush(); clusterEnd = .distantPast }
            var used = Set<Int>()
            for (o, c) in cluster where o.end > it.start { used.insert(c) }
            var c = 0
            while used.contains(c) { c += 1 }
            cluster.append((it, c))
            clusterEnd = max(clusterEnd, it.end)
        }
        flush()
        return result
    }

    func timeAt(_ y: CGFloat) -> Date {
        let mins = Int((y / hourH) * 60)
        let snapped = max(0, min(23 * 60 + 45, (mins / 15) * 15))
        return day.at(hour: snapped / 60, minute: snapped % 60)
    }

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // saat çizgileri
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { h in
                        Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: hourH)
                }
                Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1).frame(maxHeight: .infinity)

                if isToday { Rectangle().fill(Color.accentColor.opacity(0.04)) }

                ForEach(placed) { p in
                    let w = (geo.size.width - 6) / CGFloat(p.cols)
                    let top = CGFloat(p.item.start < day ? 0 : p.item.start.minutesIntoDay) / 60 * hourH
                    let endMin = p.item.end >= day.adding(days: 1) ? 24 * 60 : p.item.end.minutesIntoDay
                    let h = max(22, CGFloat(endMin) / 60 * hourH - top)
                    EventBlock(item: p.item, conflict: p.cols > 1)
                        .frame(width: w - 2, height: h - 2)
                        .offset(x: 3 + CGFloat(p.col) * w, y: top + 1)
                        .onTapGesture { screen.edit(p.item) }
                        .modifier(OptionalDraggable(id: p.item.dragID, title: p.item.title))
                }

                if isToday {
                    TimelineView(.periodic(from: .now, by: 60)) { ctx in
                        let y = CGFloat(ctx.date.minutesIntoDay) / 60 * hourH
                        HStack(spacing: 0) {
                            Circle().fill(Color.accentColor).frame(width: 9, height: 9)
                            Rectangle().fill(Color.accentColor).frame(height: 2)
                        }
                        .offset(x: -4, y: y - 4.5)
                    }
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture(count: 2).onEnded { v in screen.newEvent(at: timeAt(v.location.y)) })
            .dropDestination(for: String.self) { ids, loc in
                screen.handleDrop(ids, day: day, time: timeAt(loc.y))
            }
        }
        .frame(height: hourH * 24)
    }
}

struct OptionalDraggable: ViewModifier {
    let id: String?
    let title: String
    func body(content: Content) -> some View {
        if let id {
            content.draggable(id) {
                Text(title).font(.caption.weight(.semibold)).padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        } else { content }
    }
}

struct EventBlock: View {
    let item: CalItem
    var conflict = false
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if item.isTask { Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle").font(.system(size: 9, weight: .bold)) }
                if case .external = item.kind { Image(systemName: "applelogo").font(.system(size: 8)) }
                Text(item.title.isEmpty ? "(Başlıksız)" : item.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(2)
                    .strikethrough(item.isDone)
                Spacer(minLength: 0)
                if conflict { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8)).foregroundStyle(Palette.secondary).help("Çakışan etkinlik") }
            }
            Text("\(Fmt.time.string(from: item.start)) – \(Fmt.time.string(from: item.end))").font(.system(size: 10)).opacity(0.75)
        }
        .foregroundStyle(item.color.mix(with: .primary, by: 0.35))
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(item.color.opacity(item.isTask ? 0.14 : 0.22)))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 3).padding(.vertical, 3) }
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(item.color.opacity(item.isTask ? 0.5 : 0), style: StrokeStyle(lineWidth: 1, dash: [3])))
        .clipped()
    }
}

// MARK: - Month

struct MonthGrid: View {
    let screen: CalendarScreen
    var body: some View {
        let first = screen.date.startOfMonth
        let gridStart = first.startOfWeek
        let weeks = 6
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                    Text(Fmt.weekdaySymbol(wd)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }.padding(.vertical, 8)
            VStack(spacing: 0) {
                ForEach(0..<weeks, id: \.self) { w in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            let d = gridStart.adding(days: w * 7 + i)
                            MonthCell(day: d, inMonth: Calendar.current.isDate(d, equalTo: first, toGranularity: .month), screen: screen)
                        }
                    }
                }
            }
            .card(padding: 0)
        }
    }
}

struct MonthCell: View {
    let day: Date
    let inMonth: Bool
    let screen: CalendarScreen
    @State private var targeted = false

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        let items = screen.items(from: day, to: day.adding(days: 1))
        let tasks = screen.dayTasks(day)
        VStack(alignment: .leading, spacing: 3) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 12.5, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(isToday ? .white : (inMonth ? .primary : .secondary))
                .frame(width: 24, height: 24)
                .background(Circle().fill(isToday ? Color.accentColor : .clear))
            ForEach(items.prefix(3)) { it in
                HStack(spacing: 4) {
                    Circle().fill(it.color).frame(width: 6, height: 6)
                    Text(it.title).lineLimit(1)
                }
                .font(.system(size: 10.5))
                .onTapGesture { screen.edit(it) }
                .modifier(OptionalDraggable(id: it.dragID, title: it.title))
            }
            ForEach(tasks.prefix(max(0, 3 - items.count))) { t in
                HStack(spacing: 4) {
                    Image(systemName: t.isDone ? "checkmark.circle.fill" : "circle").font(.system(size: 8)).foregroundStyle(t.isDone ? Palette.success : .secondary)
                    Text(t.title).lineLimit(1).strikethrough(t.isDone)
                }
                .font(.system(size: 10.5))
                .onTapGesture { screen.app.editingTask = t }
                .draggable(t.id.uuidString)
            }
            let extra = items.count + tasks.count - 3
            if extra > 0 { Text("+\(extra) daha").font(.system(size: 10)).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: .infinity, alignment: .topLeading)
        .background(targeted ? Color.accentColor.opacity(0.12) : (inMonth ? Color.clear : Color.primary.opacity(0.025)))
        .overlay(Rectangle().stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { screen.newEvent(at: day.at(hour: 9)) }
        .onTapGesture { screen.app.calendarDate = day }
        .dropDestination(for: String.self) { ids, _ in screen.handleDrop(ids, day: day, time: nil) } isTargeted: { targeted = $0 }
    }
}

// MARK: - Agenda

struct AgendaList: View {
    let screen: CalendarScreen
    var body: some View {
        let start = Date().startOfDay
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(0..<30, id: \.self) { i in
                    let d = start.adding(days: i)
                    let items = screen.items(from: d, to: d.adding(days: 1))
                    let tasks = screen.dayTasks(d)
                    if !items.isEmpty || !tasks.isEmpty || i == 0 {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(spacing: 0) {
                                Text(Fmt.weekdayShort.string(from: d).uppercased(with: Fmt.locale)).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(i == 0 ? Color.accentColor : .secondary)
                                Text("\(Calendar.current.component(.day, from: d))").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(i == 0 ? Color.accentColor : .primary)
                            }.frame(width: 50)
                            VStack(alignment: .leading, spacing: 6) {
                                if items.isEmpty && tasks.isEmpty { Text("Plan yok").foregroundStyle(.tertiary) }
                                ForEach(items) { it in
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 2).fill(it.color).frame(width: 4, height: 32)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(it.title).font(.system(size: 13.5, weight: .medium)).strikethrough(it.isDone)
                                            Text("\(Fmt.time.string(from: it.start)) – \(Fmt.time.string(from: it.end))").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if it.isTask { Pill(text: "Görev", icon: "checkmark.circle", color: Palette.success) }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { screen.edit(it) }
                                }
                                ForEach(tasks) { TaskRow(task: $0, compact: true) }
                            }
                        }
                        .padding(14)
                        .card(padding: 4)
                        .dropDestination(for: String.self) { ids, _ in screen.handleDrop(ids, day: d, time: nil) }
                    }
                }
            }.padding(.bottom, 20)
        }
    }
}

// MARK: - Event editor

struct EventEditor: View {
    @Bindable var event: CalEvent
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Query(sort: \Project.sortIndex) var projects: [Project]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Circle().fill(event.color).frame(width: 14, height: 14)
                TextField("Etkinlik başlığı", text: $event.title).textFieldStyle(.plain).font(.system(size: 20, weight: .semibold))
            }
            Form {
                Toggle("Tüm gün", isOn: $event.allDay)
                DatePicker("Başlangıç", selection: Binding(get: { event.start }, set: { new in
                    let dur = event.end.timeIntervalSince(event.start)
                    event.start = new
                    event.end = new.addingTimeInterval(dur)
                }), displayedComponents: event.allDay ? [.date] : [.date, .hourAndMinute])
                DatePicker("Bitiş", selection: $event.end, in: event.start..., displayedComponents: event.allDay ? [.date] : [.date, .hourAndMinute])
                Picker("Proje", selection: Binding(get: { event.projectID }, set: { id in
                    event.projectID = id
                    if let p = projects.first(where: { $0.id == id }) { event.colorHex = p.colorHex }
                })) {
                    Text("Yok").tag(UUID?.none)
                    ForEach(projects.filter(\.isLive)) { Text($0.name).tag(Optional($0.id)) }
                }
                LabeledContent("Renk") {
                    HStack(spacing: 6) {
                        ForEach(Palette.projectColors, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                                .overlay(Circle().stroke(.white, lineWidth: event.colorHex == hex ? 2 : 0).padding(2))
                                .onTapGesture { event.colorHex = hex }
                        }
                    }
                }
                TextField("Konum", text: $event.location)
                TextField("Notlar", text: $event.notes, axis: .vertical).lineLimit(3...6)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Button("Sil", role: .destructive) {
                    context.delete(event)
                    dismiss()
                }
                Spacer()
                Button("Kaydet") {
                    if event.title.trimmingCharacters(in: .whitespaces).isEmpty { event.title = "Yeni etkinlik" }
                    if let pid = event.projectID {
                        Store.log(context, "Etkinlik planlandı: **\(event.title)** · \(Fmt.relative(event.start)) \(Fmt.time.string(from: event.start))", icon: "calendar.badge.plus", color: event.colorHex, projectID: pid)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 480, height: 560)
        .onExitCommand {
            if event.title.isEmpty { context.delete(event) }
            dismiss()
        }
    }
}

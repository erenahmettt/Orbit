import SwiftUI
import SwiftData

struct PaletteItem: Identifiable {
    let id: String
    let section: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var shortcut: String = ""
    let run: () -> Void
}

struct CommandPalette: View {
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) var context
    @Query var tasks: [TaskItem]
    @Query(sort: \Note.updatedAt, order: .reverse) var notes: [Note]
    @Query var projects: [Project]
    @Query(sort: \JournalEntry.day, order: .reverse) var journal: [JournalEntry]
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    func close() { app.showPalette = false }

    var commands: [PaletteItem] {
        [
            PaletteItem(id: "c-task", section: "Komutlar", title: "Yeni görev oluştur", subtitle: "", icon: "plus.circle.fill", color: Palette.success, shortcut: "⇧⌘N") { close(); app.newTask() },
            PaletteItem(id: "c-note", section: "Komutlar", title: "Yeni not oluştur", subtitle: "", icon: "square.and.pencil", color: Palette.warning, shortcut: "⌘N") { close(); app.newNote(context: context) },
            PaletteItem(id: "c-cal", section: "Komutlar", title: "Takvimi aç", subtitle: "", icon: "calendar", color: Palette.blue, shortcut: "⌘3") { close(); app.go(.calendar) },
            PaletteItem(id: "c-today", section: "Komutlar", title: "Bugüne git", subtitle: "", icon: "sun.max.fill", color: Palette.warning, shortcut: "⌘2") { close(); app.calendarDate = Date(); app.go(.today) },
            PaletteItem(id: "c-home", section: "Komutlar", title: "Home", subtitle: "", icon: "house.fill", color: Palette.primary, shortcut: "⌘1") { close(); app.go(.home) },
            PaletteItem(id: "c-tasks", section: "Komutlar", title: "Tüm görevler", subtitle: "", icon: "checkmark.circle.fill", color: Palette.success, shortcut: "⌘4") { close(); app.go(.tasks) },
            PaletteItem(id: "c-notes", section: "Komutlar", title: "Notlar", subtitle: "", icon: "note.text", color: Palette.warning, shortcut: "⌘5") { close(); app.go(.notes) },
            PaletteItem(id: "c-journal", section: "Komutlar", title: "Bugünün günlüğü", subtitle: "", icon: "book.closed.fill", color: Color(hex: "#E86BA8"), shortcut: "⌘6") { close(); app.go(.journal) },
            PaletteItem(id: "c-projects", section: "Komutlar", title: "Projeler", subtitle: "", icon: "square.stack.3d.up.fill", color: Palette.purple, shortcut: "⌘7") { close(); app.go(.projects) },
            PaletteItem(id: "c-focus", section: "Komutlar", title: FocusTimer.shared.isRunning ? "Pomodoro'yu duraklat" : "Pomodoro başlat", subtitle: "", icon: "timer", color: Palette.secondary, shortcut: "⇧⌘P") {
                close()
                let f = FocusTimer.shared
                if f.isRunning { f.pause() } else if f.isPaused { f.resume() } else { f.startUpcoming() }
                app.go(.focus)
            },
            PaletteItem(id: "c-inbox", section: "Komutlar", title: "Inbox", subtitle: "", icon: "tray.fill", color: Palette.info) { close(); app.go(.inbox) },
            PaletteItem(id: "c-settings", section: "Komutlar", title: "Ayarları aç", subtitle: "", icon: "gearshape.fill", color: .gray, shortcut: "⌘,") { close(); app.go(.settings) },
        ]
    }

    func matches(_ s: String) -> Bool { s.localizedCaseInsensitiveContains(query) }

    func snippet(_ body: String) -> String {
        guard let r = body.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return "" }
        let start = body.index(r.lowerBound, offsetBy: -30, limitedBy: body.startIndex) ?? body.startIndex
        let end = body.index(r.upperBound, offsetBy: 50, limitedBy: body.endIndex) ?? body.endIndex
        return (start > body.startIndex ? "…" : "") + body[start..<end].replacingOccurrences(of: "\n", with: " ") + (end < body.endIndex ? "…" : "")
    }

    var results: [PaletteItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            let recent = notes.filter(\.isLive).prefix(4).map { n in
                PaletteItem(id: "n-\(n.id)", section: "Son notlar", title: n.title.isEmpty ? "Başlıksız" : n.title, subtitle: n.preview, icon: "doc.text", color: Palette.warning) { close(); app.selectedNoteID = n.id; app.go(.notes) }
            }
            return commands + recent
        }
        var r = commands.filter { matches($0.title) }
        let isTag = q.hasPrefix("#")
        let tagQ = String(q.drop { $0 == "#" }).lowercased()

        r += projects.filter { $0.isLive && (matches($0.name) || matches($0.summary)) }.map { p in
            PaletteItem(id: "p-\(p.id)", section: "Projeler", title: p.name, subtitle: p.summary, icon: p.icon, color: p.color) { close(); app.go(.project(p.id)) }
        }
        r += tasks.filter { $0.isLive && (isTag ? $0.tags.contains { $0.hasPrefix(tagQ) } : (matches($0.title) || matches($0.details) || $0.tags.contains { $0.localizedCaseInsensitiveContains(q) } || $0.subtasks.contains { matches($0.title) })) }
            .sorted(by: TaskSort.byDue).prefix(8).map { t in
                PaletteItem(id: "t-\(t.id)", section: "Görevler", title: t.title, subtitle: [t.status.title, t.dueDate.map { Fmt.relative($0) } ?? "", t.tags.map { "#\($0)" }.joined(separator: " ")].filter { !$0.isEmpty }.joined(separator: " · "), icon: t.isDone ? "checkmark.circle.fill" : "circle", color: t.isDone ? Palette.success : t.priority.color) { close(); app.editingTask = t }
            }
        r += notes.filter { $0.isLive && (isTag ? $0.tags.contains { $0.hasPrefix(tagQ) } : (matches($0.title) || matches($0.body) || $0.tags.contains { $0.localizedCaseInsensitiveContains(q) })) }
            .prefix(8).map { n in
                let snip = snippet(n.body)
                return PaletteItem(id: "n-\(n.id)", section: "Notlar", title: n.title.isEmpty ? "Başlıksız" : n.title, subtitle: snip.isEmpty ? n.preview : snip, icon: "doc.text", color: Palette.warning) { close(); app.selectedNoteID = n.id; app.go(.notes) }
            }
        if isTag || q.count > 1 {
            let tags = Set(tasks.filter(\.isLive).flatMap(\.tags) + notes.filter(\.isLive).flatMap(\.tags)).filter { $0.hasPrefix(tagQ) || $0.localizedCaseInsensitiveContains(tagQ) }
            r += tags.sorted().prefix(5).map { tag in
                PaletteItem(id: "tag-\(tag)", section: "Etiketler", title: "#\(tag)", subtitle: "Bu etiketi taşıyan görev ve notlar", icon: "number", color: Palette.purple) { query = "#\(tag)"; index = 0 }
            }
        }
        if !isTag {
            r += journal.filter { [$0.goals, $0.done, $0.freeText, $0.review, $0.tomorrow].contains(where: matches) }.prefix(5).map { e in
                let all = [e.freeText, e.goals, e.done, e.review, e.tomorrow].joined(separator: " ")
                return PaletteItem(id: "j-\(e.id)", section: "Günlük", title: Fmt.longDate.string(from: e.day), subtitle: snippet(all), icon: "book.closed", color: Color(hex: "#E86BA8")) { close(); app.go(.journal) }
            }
        }
        if r.filter({ $0.section != "Komutlar" }).isEmpty {
            r.append(PaletteItem(id: "create", section: "Oluştur", title: "“\(q)” görevini oluştur", subtitle: "Inbox'a eklenir", icon: "plus.circle.fill", color: Palette.success) {
                let p = QuickParser.parse(q, projects: projects)
                Store.createTask(context: context, title: p.title, priority: p.priority ?? .normal, due: p.due, hasTime: p.hasTime, projectID: p.projectID, tags: p.tags)
                app.show(Toast(text: "Görev eklendi", icon: "plus.circle.fill", color: Palette.info))
                close()
            })
        }
        return r
    }

    var body: some View {
        let items = results
        ZStack(alignment: .top) {
            Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
                    TextField("Görev, not, proje, #etiket veya komut ara…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                        .focused($focused)
                        .onSubmit { if items.indices.contains(index) { items[index].run() } }
                    Text("esc").font(.caption.monospaced()).foregroundStyle(.tertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
                }
                .padding(18)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                                if i == 0 || items[i - 1].section != item.section {
                                    Text(item.section.uppercased(with: Fmt.locale)).font(.system(size: 10.5, weight: .semibold)).kerning(0.8).foregroundStyle(.tertiary)
                                        .padding(.horizontal, 12).padding(.top, i == 0 ? 4 : 12).padding(.bottom, 4)
                                }
                                row(item, selected: i == index)
                                    .id(i)
                                    .onTapGesture { item.run() }
                                    .onHover { if $0 { index = i } }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 420)
                    .onChange(of: index) { proxy.scrollTo(index, anchor: .center) }
                }
            }
            .frame(width: 640)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 20)
            .padding(.top, 110)
        }
        .onAppear {
            focused = true
            index = 0
            UserDefaults.standard.set(true, forKey: "usedPalette")
        }
        .onChange(of: query) { index = 0 }
        .onKeyPress(.downArrow) { index = min(index + 1, max(0, items.count - 1)); return .handled }
        .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
        .onExitCommand { close() }
    }

    func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(item.color.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if !item.shortcut.isEmpty { Text(item.shortcut).font(.caption.monospaced()).foregroundStyle(.tertiary) }
            if selected { Image(systemName: "return").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.accentColor.opacity(0.18) : .clear))
        .contentShape(Rectangle())
    }
}

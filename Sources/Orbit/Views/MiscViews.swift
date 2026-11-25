import SwiftUI
import SwiftData

// MARK: - Archive / Trash

struct ArchiveView: View {
    enum Mode { case archive, trash }
    let mode: Mode
    @Environment(\.modelContext) var context
    @EnvironmentObject var app: AppState
    @Query var tasks: [TaskItem]
    @Query var notes: [Note]
    @Query var projects: [Project]
    @Query var events: [CalEvent]
    @State private var confirmEmpty = false

    var tItems: [TaskItem] { tasks.filter { mode == .archive ? ($0.archived && $0.deletedAt == nil) : $0.deletedAt != nil } }
    var nItems: [Note] { notes.filter { mode == .archive ? ($0.archived && $0.deletedAt == nil) : $0.deletedAt != nil } }
    var pItems: [Project] { projects.filter { mode == .archive ? ($0.archived && $0.deletedAt == nil) : $0.deletedAt != nil } }
    var eItems: [CalEvent] { mode == .trash ? events.filter { $0.deletedAt != nil } : [] }
    var isEmpty: Bool { tItems.isEmpty && nItems.isEmpty && pItems.isEmpty && eItems.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: mode == .archive ? "archivebox.fill" : "trash.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "#8A94A6").gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode == .archive ? "Archive" : "Trash").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(mode == .archive ? "Arşivlenmiş içerikler" : "Silinen içerikler — buradan geri yükleyebilirsin").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if mode == .trash && !isEmpty {
                        Button("Çöpü boşalt", role: .destructive) { confirmEmpty = true }
                    }
                }
                if isEmpty { EmptyState(icon: mode == .archive ? "archivebox" : "trash", title: "Burası boş").card() }
                if !pItems.isEmpty { section("Projeler", pItems.map { p in (p.name, p.icon, { restore(p) }, { context.delete(p) }) }) }
                if !tItems.isEmpty { section("Görevler", tItems.map { t in (t.title, "checkmark.circle", { restore(t) }, { context.delete(t) }) }) }
                if !nItems.isEmpty { section("Notlar", nItems.map { n in (n.title.isEmpty ? "Başlıksız" : n.title, "doc.text", { restore(n) }, { context.delete(n) }) }) }
                if !eItems.isEmpty { section("Etkinlikler", eItems.map { e in (e.title, "calendar", { e.deletedAt = nil }, { context.delete(e) }) }) }
            }
            .padding(28)
        }
        .confirmationDialog("Çöp kutusundaki her şey kalıcı olarak silinecek. Bu işlem geri alınamaz.", isPresented: $confirmEmpty) {
            Button("Kalıcı olarak sil", role: .destructive) {
                tItems.forEach { context.delete($0) }
                nItems.forEach { context.delete($0) }
                pItems.forEach { context.delete($0) }
                eItems.forEach { context.delete($0) }
            }
        }
    }

    func restore(_ t: TaskItem) { t.archived = false; t.deletedAt = nil; Notifier.schedule(task: t) }
    func restore(_ n: Note) { n.archived = false; n.deletedAt = nil }
    func restore(_ p: Project) { p.archived = false; p.deletedAt = nil }

    func section(_ title: String, _ rows: [(String, String, () -> Void, () -> Void)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(rows.indices, id: \.self) { i in
                let r = rows[i]
                HStack {
                    Image(systemName: r.1).foregroundStyle(.secondary).frame(width: 20)
                    Text(r.0)
                    Spacer()
                    Button("Geri yükle", action: r.2)
                    if mode == .trash { Button("Kalıcı sil", role: .destructive, action: r.3) }
                }
                .padding(.vertical, 4)
                if i < rows.count - 1 { Divider() }
            }
        }
        .card()
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("userName") var userName = ""
    @AppStorage("theme") var theme: AppTheme = .system
    @AppStorage("accent") var accent = "#6558F5"
    @AppStorage("showMenuBar") var showMenuBar = true
    @AppStorage("appleCalendarEnabled") var appleCalendar = false
    @AppStorage("dailyPlanningEnabled") var dailyPlanning = true
    @AppStorage("dailyPlanningHour") var planningHour = 9
    @AppStorage("onboarded") var onboarded = true
    @AppStorage("editorFont") var fontRaw = EditorTypography.Family.system.rawValue
    @AppStorage("editorSize") var fontSize = 15.0
    @AppStorage("editorLineHeight") var lineHeight = 1.45
    @AppStorage("editorReadable") var readable = true
    @EnvironmentObject var apple: AppleCalendar
    @Environment(\.modelContext) var context
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "gearshape.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "#8A94A6").gradient))
                    Text("Settings").font(.system(size: 26, weight: .bold, design: .rounded))
                }

                group("Profil", "person.crop.circle.fill", Palette.primary) {
                    LabeledContent("Adın") { TextField("Karşılama mesajında görünür", text: $userName).textFieldStyle(.roundedBorder).frame(width: 260) }
                }

                group("Görünüm", "paintpalette.fill", Palette.purple) {
                    LabeledContent("Tema") {
                        Picker("", selection: $theme) { ForEach(AppTheme.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).fixedSize()
                    }
                    LabeledContent("Vurgu rengi") {
                        HStack(spacing: 8) {
                            ForEach(Palette.accentChoices, id: \.self) { hex in
                                Circle().fill(Color(hex: hex).gradient).frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.7), lineWidth: accent == hex ? 2 : 0).padding(-3))
                                    .onTapGesture { accent = hex }
                            }
                            ColorPicker("", selection: Binding(get: { Color(hex: accent) }, set: { accent = $0.hexString })).labelsHidden()
                        }
                    }
                    Toggle("Menü çubuğu ikonunu göster", isOn: $showMenuBar)
                }

                group("Not editörü", "textformat", Palette.warning) {
                    LabeledContent("Yazı tipi") {
                        Picker("", selection: $fontRaw) {
                            ForEach(EditorTypography.Family.allCases) { Text($0.title).tag($0.rawValue) }
                        }.labelsHidden().fixedSize()
                    }
                    LabeledContent("Boyut: \(Int(fontSize)) pt") {
                        Slider(value: $fontSize, in: 12...24, step: 1).frame(width: 220)
                    }
                    LabeledContent("Satır aralığı") {
                        Picker("", selection: $lineHeight) {
                            Text("Sıkı").tag(1.2)
                            Text("Normal").tag(1.45)
                            Text("Rahat").tag(1.7)
                        }.pickerStyle(.segmented).fixedSize()
                    }
                    Toggle("Okunabilir genişlik (metni ortala, ~760 pt)", isOn: $readable)
                    let t = EditorTypography(family: .init(rawValue: fontRaw) ?? .system, size: fontSize, lineHeight: lineHeight)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Önizleme").font(.system(size: t.headingSize(2), weight: .bold, design: t.family.design))
                        Text("Hızlı kahverengi tilki tembel köpeğin üzerinden atlar. Bu paragraf seçtiğin yazı tipini, boyutu ve satır aralığını gösterir.")
                            .font(.system(size: t.size, design: t.family.design)).lineSpacing(t.lineSpacing)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                }

                group("Bildirimler", "bell.badge.fill", Palette.warning) {
                    Toggle("Günlük planlama hatırlatması", isOn: $dailyPlanning)
                    if dailyPlanning {
                        Stepper("Saat: \(String(format: "%02d:00", planningHour))", value: $planningHour, in: 5...12)
                    }
                    Text(Notifier.available ? "Görev hatırlatıcıları ve son teslim bildirimleri macOS Bildirim Merkezi'ne gönderilir." : "Bildirimler yalnızca Orbit.app paketi olarak çalıştırıldığında aktiftir (./build.sh).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .onChange(of: dailyPlanning) { Notifier.scheduleDailyPlanning(enabled: dailyPlanning, hour: planningHour, minute: 0) }
                .onChange(of: planningHour) { Notifier.scheduleDailyPlanning(enabled: dailyPlanning, hour: planningHour, minute: 0) }

                group("Apple Calendar", "calendar", Palette.blue) {
                    Toggle("Mac takvimindeki etkinlikleri göster", isOn: $appleCalendar)
                        .onChange(of: appleCalendar) { if appleCalendar && !apple.authorized { apple.requestAccess() } }
                    if appleCalendar && !apple.authorized {
                        HStack {
                            Text("Takvim erişimi verilmedi.").foregroundStyle(Palette.secondary)
                            Button("Erişim iste") { apple.requestAccess() }
                        }.font(.callout)
                    }
                    Text("Salt-okunur: Apple Calendar etkinlikleri takvim ve Schedule kartında görünür.").font(.caption).foregroundStyle(.secondary)
                }

                group("Veri", "externaldrive.fill", Palette.info) {
                    Text("Tüm veriler yerel olarak saklanır: ~/Library/Application Support/Orbit").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Klasörü Finder'da göster") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL.applicationSupportDirectory.appending(path: "Orbit")])
                        }
                        Button("Karşılama ekranını göster") { onboarded = false }
                        Spacer()
                        Button("Tüm verileri sil…", role: .destructive) { confirmReset = true }
                    }
                }

                group("Klavye kısayolları", "command", Palette.success) {
                    ForEach([("⌘N", "Yeni not"), ("⇧⌘N", "Yeni görev"), ("⌘K", "Arama / komut paleti"), ("⌘1", "Home"), ("⌘2", "Today"), ("⌘3", "Calendar"), ("⌘4", "Tasks"), ("⌘5", "Notes"), ("⌘6", "Journal"), ("⌘7", "Projects"), ("⌘8", "Focus"), ("⇧⌘P", "Pomodoro başlat / duraklat"), ("Esc", "Pencere / modal kapat")], id: \.0) { k, v in
                        HStack {
                            Text(k).font(.system(.callout, design: .monospaced).weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.07)))
                                .frame(width: 80, alignment: .leading)
                            Text(v)
                        }
                    }
                    Text("Hızlı görev sözdizimi: “Rapor yaz yarın 14:00 !high #software”  (!low / !normal / !high / !urgent, #proje veya #etiket)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .confirmationDialog("Tüm görevler, notlar, projeler, etkinlikler ve günlükler kalıcı olarak silinecek. Bu işlem geri alınamaz.", isPresented: $confirmReset) {
            Button("Hepsini kalıcı olarak sil", role: .destructive) { Seed.wipe(context) }
        }
    }

    func group<C: View>(_ title: String, _ icon: String, _ color: Color, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, icon: icon, color: color)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

extension Color {
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var focus: FocusTimer
    @Environment(\.modelContext) var context
    @Environment(\.openWindow) var openWindow
    @Query var tasks: [TaskItem]
    @State private var taskText = ""
    @State private var noteText = ""
    @Query var projects: [Project]

    var today: [TaskItem] { tasks.filter { $0.isLive && !$0.isDone && ($0.isToday || $0.isOverdue) }.sorted(by: TaskSort.byPriorityThenTime) }
    var doneToday: Int { tasks.filter { $0.isLive && $0.isDone && ($0.completedAt.map(Calendar.current.isDateInToday) ?? false) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                OrbitLogo().frame(width: 22, height: 22)
                Text("Orbit").font(.headline)
                Spacer()
                Text("\(today.count) açık · \(doneToday) bitti").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: "checkmark.circle").foregroundStyle(Palette.success)
                TextField("Hızlı görev (bugün)", text: $taskText).textFieldStyle(.plain).onSubmit {
                    let p = QuickParser.parse(taskText, projects: projects)
                    guard !p.title.isEmpty else { return }
                    Store.createTask(context: context, title: p.title, priority: p.priority ?? .normal, due: p.due ?? Date().startOfDay, hasTime: p.hasTime, projectID: p.projectID, tags: p.tags)
                    taskText = ""
                }
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            HStack {
                Image(systemName: "note.text").foregroundStyle(Palette.warning)
                TextField("Hızlı not", text: $noteText).textFieldStyle(.plain).onSubmit {
                    let t = noteText.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    Store.createNote(context: context, title: String(t.prefix(48)), body: t)
                    noteText = ""
                }
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))

            HStack(spacing: 10) {
                Image(systemName: focus.isActive ? focus.phase.icon : "timer").foregroundStyle(focus.isActive ? focus.phase.color : Palette.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(focus.isActive ? "\(focus.phase.title) · \(focus.remainingText)" : "Pomodoro").font(.callout.weight(.semibold)).monospacedDigit()
                    if !focus.taskTitle.isEmpty { Text(focus.taskTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                if focus.isActive {
                    Button { focus.isRunning ? focus.pause() : focus.resume() } label: { Image(systemName: focus.isRunning ? "pause.fill" : "play.fill") }
                    Button { focus.stop() } label: { Image(systemName: "stop.fill") }
                } else {
                    Button("Başlat") { focus.startUpcoming() }
                }
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Palette.secondary.opacity(0.08)))
            Text("BUGÜN").font(.system(size: 10, weight: .semibold)).kerning(0.8).foregroundStyle(.secondary)
            if today.isEmpty { Text("Bugün için açık görev yok 🎉").font(.callout).foregroundStyle(.secondary) }
            ForEach(today.prefix(6)) { t in
                HStack(spacing: 8) {
                    CompletionCheckbox(done: t.isDone, color: t.priority.color, size: 15) { Store.toggleComplete(t, context: context) }
                    Text(t.title).lineLimit(1).font(.callout)
                    Spacer()
                    if let d = t.dueDate, t.hasTime { Text(Fmt.time.string(from: d)).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Divider()
            HStack {
                Button("Orbit'i aç") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Çık") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

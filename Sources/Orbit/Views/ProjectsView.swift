import SwiftUI
import SwiftData

struct ProjectsView: View {
    @EnvironmentObject var app: AppState
    @Query(sort: \Project.sortIndex) var projects: [Project]
    @Query var tasks: [TaskItem]
    @Query var notes: [Note]
    @State private var showNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.purple.gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Projects").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Her proje kendi çalışma alanı").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showNew = true } label: { Label("Yeni proje", systemImage: "plus") }.buttonStyle(.borderedProminent)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18)], spacing: 18) {
                    ForEach(projects.filter(\.isLive)) { p in
                        ProjectCard(project: p, tasks: tasks, noteCount: notes.filter { $0.isLive && $0.projectID == p.id }.count)
                    }
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $showNew) { ProjectEditor(project: nil) }
    }
}

struct ProjectCard: View {
    let project: Project
    let tasks: [TaskItem]
    let noteCount: Int
    @EnvironmentObject var app: AppState
    @State private var hover = false

    var body: some View {
        let prog = Store.progress(of: project, tasks: tasks)
        Button { app.go(.project(project.id)) } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    ProjectBadge(project: project, size: 44)
                    Spacer()
                    Pill(text: project.status.title, color: project.status.color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).font(.system(size: 17, weight: .bold))
                    Text(project.summary.isEmpty ? "Açıklama yok" : project.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                ProgressView(value: prog.ratio).tint(project.color)
                HStack(spacing: 14) {
                    Label("\(prog.done)/\(prog.total)", systemImage: "checkmark.circle")
                    Label("\(noteCount)", systemImage: "doc.text")
                    if let t = project.targetDate { Label(Fmt.dayMonth.string(from: t), systemImage: "flag.checkered") }
                    Spacer()
                    Text("\(Int(prog.ratio * 100))%").fontWeight(.semibold).foregroundStyle(project.color)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .background(
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.background.opacity(0.6))
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LinearGradient(colors: [project.color.opacity(0.18), project.color.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle().fill(project.color.opacity(0.25)).frame(width: 120).blur(radius: 40).offset(x: 30, y: -30)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(project.color.opacity(hover ? 0.5 : 0.2)))
            .shadow(color: project.color.opacity(hover ? 0.25 : 0.08), radius: hover ? 18 : 10, y: 6)
            .scaleEffect(hover ? 1.012 : 1)
            .animation(.snappy(duration: 0.2), value: hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

enum ProjectTab: String, CaseIterable, Identifiable {
    case overview, tasks, notes, activity, resources
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .tasks: "checkmark.circle"
        case .notes: "doc.text"
        case .activity: "bubble.left.and.text.bubble.right"
        case .resources: "link"
        }
    }
}

struct ProjectDetailView: View {
    let projectID: UUID
    @Query var projects: [Project]
    var body: some View {
        if let p = projects.first(where: { $0.id == projectID }) {
            ProjectDetail(project: p)
        } else {
            EmptyState(icon: "questionmark.folder", title: "Proje bulunamadı")
        }
    }
}

struct ProjectDetail: View {
    @Bindable var project: Project
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) var context
    @Query var tasks: [TaskItem]
    @Query(sort: \Note.updatedAt, order: .reverse) var notes: [Note]
    @Query(sort: \Activity.date, order: .reverse) var activity: [Activity]
    @Query(sort: \CalEvent.start) var events: [CalEvent]
    @State private var tab: ProjectTab = .overview
    @State private var editing = false

    var pTasks: [TaskItem] { tasks.filter { $0.isLive && $0.projectID == project.id } }
    var pNotes: [Note] { notes.filter { $0.isLive && $0.projectID == project.id } }
    var pActivity: [Activity] { activity.filter { $0.projectID == project.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Başlık
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    ProjectBadge(project: project, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Text(project.name).font(.system(size: 28, weight: .bold, design: .rounded))
                            Menu {
                                ForEach(ProjectStatus.allCases) { s in Button(s.title) {
                                    project.status = s
                                    Store.log(context, "Proje durumu: **\(s.title)**", icon: "flag.fill", color: project.colorHex, projectID: project.id)
                                } }
                            } label: { Pill(text: project.status.title, color: project.status.color) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        }
                        Text(project.summary.isEmpty ? "Açıklama ekle…" : project.summary).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { editing = true } label: { Image(systemName: "slider.horizontal.3") }.help("Projeyi düzenle")
                    Menu {
                        Button("Arşivle") { project.archived = true; app.go(.projects) }
                        Button("Çöpe taşı", role: .destructive) { project.deletedAt = Date(); app.go(.projects) }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                }
                HStack(spacing: 4) {
                    ForEach(ProjectTab.allCases) { t in
                        Button { withAnimation(.snappy(duration: 0.2)) { tab = t } } label: {
                            Label(t.title, systemImage: t.icon)
                                .font(.system(size: 13, weight: tab == t ? .semibold : .regular))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundStyle(tab == t ? project.color : .secondary)
                                .background(Capsule().fill(tab == t ? project.color.opacity(0.14) : .clear))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 14)
            .background(LinearGradient(colors: [project.color.opacity(0.13), .clear], startPoint: .top, endPoint: .bottom))

            Group {
                switch tab {
                case .overview: overview
                case .tasks: TaskCollectionView(scope: .project(project.id)).padding(.horizontal, 28)
                case .notes: projectNotes
                case .activity: ActivityFeed(items: pActivity, project: project)
                case .resources: ResourcesView(project: project)
                }
            }
            .padding(.top, 10)
        }
        .sheet(isPresented: $editing) { ProjectEditor(project: project) }
    }

    var overview: some View {
        let prog = Store.progress(of: project, tasks: tasks)
        let open = pTasks.filter { !$0.isDone }.sorted(by: TaskSort.byPriorityThenTime)
        return ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    stat("İlerleme", "\(Int(prog.ratio * 100))%", project.color, ring: prog.ratio)
                    stat("Açık görev", "\(open.count)", Palette.info)
                    stat("Gecikmiş", "\(open.filter(\.isOverdue).count)", Palette.secondary)
                    stat("Not", "\(pNotes.count)", Palette.warning)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ZAMAN ÇİZELGESİ").font(.system(size: 10.5, weight: .semibold)).kerning(0.8).foregroundStyle(.secondary)
                        Label(project.startDate.map { Fmt.dayMonth.string(from: $0) } ?? "—", systemImage: "play.circle").font(.callout)
                        Label(project.targetDate.map { Fmt.dayMonth.string(from: $0) } ?? "—", systemImage: "flag.checkered").font(.callout)
                        if let t = project.targetDate {
                            let days = Calendar.current.dateComponents([.day], from: Date().startOfDay, to: t.startOfDay).day ?? 0
                            Text(days >= 0 ? "\(days) gün kaldı" : "\(-days) gün geçti").font(.caption).foregroundStyle(days >= 0 ? Palette.success : Palette.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).card()
                }
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Sıradaki görevler", icon: "checkmark.circle.fill", color: project.color)
                        QuickTaskField(projectID: project.id)
                        if open.isEmpty { Text("Açık görev yok 🎉").foregroundStyle(.secondary) }
                        ForEach(open.prefix(8)) { TaskRow(task: $0, showProject: false) }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading).card()
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Son aktivite", icon: "bubble.left.fill", color: Palette.purple)
                            ForEach(pActivity.prefix(5)) { ActivityRow(activity: $0, compact: true) }
                            if pActivity.isEmpty { Text("Henüz aktivite yok").foregroundStyle(.secondary) }
                        }
                        .card()
                        let upcoming = events.filter { $0.deletedAt == nil && $0.projectID == project.id && $0.end >= Date() }.prefix(4)
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Etkinlikler", icon: "calendar", color: Palette.blue)
                            if upcoming.isEmpty { Text("Planlı etkinlik yok").foregroundStyle(.secondary) }
                            ForEach(Array(upcoming)) { e in
                                HStack {
                                    RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 3, height: 28)
                                    VStack(alignment: .leading) {
                                        Text(e.title).font(.callout.weight(.medium))
                                        Text("\(Fmt.relative(e.start)) · \(Fmt.time.string(from: e.start))").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .card()
                    }
                    .frame(width: 360)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 28)
        }
    }

    func stat(_ label: String, _ value: String, _ color: Color, ring: Double? = nil) -> some View {
        HStack(spacing: 12) {
            if let ring { ProgressRing(progress: ring, lineWidth: 6, color: color).frame(width: 40, height: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(color)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    var projectNotes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(pNotes.count) not").foregroundStyle(.secondary)
                    Spacer()
                    Button { app.newNote(context: context, projectID: project.id); app.go(.notes) } label: { Label("Yeni not", systemImage: "square.and.pencil") }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                    ForEach(pNotes) { n in
                        Button { app.selectedNoteID = n.id; app.go(.notes) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(n.title.isEmpty ? "Başlıksız" : n.title).font(.headline).lineLimit(1)
                                    Spacer()
                                    if n.favorite { Image(systemName: "star.fill").foregroundStyle(Palette.warning).font(.caption) }
                                }
                                Text(n.preview).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                                Spacer(minLength: 0)
                                Text(Fmt.ago(n.updatedAt)).font(.caption2).foregroundStyle(.tertiary)
                            }
                            .frame(height: 110, alignment: .topLeading)
                            .card(padding: 14)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 28)
        }
    }
}

// MARK: - Activity feed

struct ActivityFeed: View {
    let items: [Activity]
    let project: Project
    @Environment(\.modelContext) var context
    @State private var message = ""

    var grouped: [(Date, [Activity])] {
        Dictionary(grouping: items) { $0.date.startOfDay }.sorted { $0.key > $1.key }.map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    if items.isEmpty { EmptyState(icon: "bubble.left.and.bubble.right", title: "Henüz aktivite yok", subtitle: "Görev ekledikçe, not yazdıkça burada bir akış oluşacak.") }
                    ForEach(grouped, id: \.0) { day, acts in
                        Section {
                            ForEach(acts) { ActivityRow(activity: $0) }
                        } header: {
                            HStack {
                                VStack { Divider() }
                                Text(Fmt.relative(day) + " · " + Fmt.dayMonthWeekday.string(from: day))
                                    .font(.system(size: 11.5, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(.background)).overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                                VStack { Divider() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 10)
            }
            // Slack benzeri mesaj kutusu: projeye kısa güncelleme yaz
            HStack(spacing: 10) {
                ProjectBadge(project: project, size: 26)
                TextField("#\(project.name.lowercased()) kanalına bir güncelleme yaz…", text: $message)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let m = message.trimmingCharacters(in: .whitespaces)
                        guard !m.isEmpty else { return }
                        Store.log(context, m, icon: "text.bubble.fill", color: project.colorHex, projectID: project.id)
                        project.updatedAt = Date()
                        message = ""
                    }
                Image(systemName: "paperplane.fill").foregroundStyle(message.isEmpty ? Color.secondary : project.color)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
            .padding(.horizontal, 28).padding(.bottom, 20)
        }
    }
}

struct ActivityRow: View {
    let activity: Activity
    var compact = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: activity.icon)
                .font(.system(size: compact ? 10 : 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: compact ? 22 : 32, height: compact ? 22 : 32)
                .background(RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous).fill(Color(hex: activity.colorHex).gradient))
            VStack(alignment: .leading, spacing: 2) {
                if !compact {
                    HStack(spacing: 6) {
                        Text("Sen").font(.system(size: 13, weight: .bold))
                        Text(Fmt.time.string(from: activity.date)).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Text(LocalizedStringKey(activity.text)).font(.system(size: compact ? 12.5 : 13.5)).foregroundStyle(compact ? .secondary : .primary)
                if compact { Text(Fmt.ago(activity.date)).font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer()
        }
    }
}

// MARK: - Resources

struct ResourcesView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) var context
    @State private var title = ""
    @State private var url = ""
    @State private var kind = "link"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Picker("", selection: $kind) {
                        Label("Link", systemImage: "link").tag("link")
                        Label("Dosya", systemImage: "doc").tag("file")
                        Label("Referans", systemImage: "book").tag("ref")
                    }.labelsHidden().fixedSize()
                    TextField("Başlık", text: $title).textFieldStyle(.roundedBorder).frame(width: 220)
                    TextField(kind == "file" ? "Dosya yolu" : "URL veya not", text: $url).textFieldStyle(.roundedBorder)
                    if kind == "file" {
                        Button("Seç…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = false
                            if panel.runModal() == .OK, let u = panel.url {
                                url = u.absoluteString
                                if title.isEmpty { title = u.lastPathComponent }
                            }
                        }
                    }
                    Button("Ekle") { add() }.buttonStyle(.borderedProminent).disabled(title.isEmpty && url.isEmpty)
                }
                if project.resources.isEmpty {
                    EmptyState(icon: "link.circle", title: "Kaynak yok", subtitle: "Linkler, dosyalar ve referanslar burada toplanır.")
                }
                ForEach(project.resources) { r in
                    HStack(spacing: 12) {
                        Image(systemName: r.kind == "file" ? "doc.fill" : r.kind == "ref" ? "book.fill" : "link")
                            .foregroundStyle(.white).frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 9).fill(project.color.gradient))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.callout.weight(.semibold))
                            Text(r.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let u = URL(string: r.url), u.scheme != nil {
                            Button("Aç") { NSWorkspace.shared.open(u) }
                        }
                        Button { project.resources.removeAll { $0.id == r.id } } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    .card(padding: 12)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 28)
        }
    }

    func add() {
        var u = url.trimmingCharacters(in: .whitespaces)
        if kind == "link", !u.isEmpty, !u.contains("://") { u = "https://" + u }
        project.resources.append(ProjectResource(title: title.isEmpty ? u : title, url: u, kind: kind))
        Store.log(context, "Kaynak eklendi: **\(title.isEmpty ? u : title)**", icon: "link", color: project.colorHex, projectID: project.id)
        title = ""; url = ""
    }
}

// MARK: - Editor

struct ProjectEditor: View {
    var project: Project?
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var app: AppState
    @Query var projects: [Project]
    @State private var name = ""
    @State private var summary = ""
    @State private var color = Palette.projectColors[0]
    @State private var icon = "folder.fill"
    @State private var status: ProjectStatus = .active
    @State private var hasStart = false
    @State private var start = Date()
    @State private var hasTarget = false
    @State private var target = Date().adding(days: 30)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: color).gradient))
                TextField("Proje adı", text: $name).textFieldStyle(.plain).font(.system(size: 22, weight: .bold))
            }
            TextField("Açıklama", text: $summary, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 8) {
                Text("RENK").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Palette.projectColors, id: \.self) { hex in
                        Circle().fill(Color(hex: hex).gradient).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.primary.opacity(0.7), lineWidth: color == hex ? 2 : 0).padding(-3))
                            .onTapGesture { color = hex }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("İKON").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 10), spacing: 6) {
                    ForEach(Palette.projectIcons, id: \.self) { i in
                        Image(systemName: i).frame(width: 34, height: 34)
                            .foregroundStyle(icon == i ? .white : .primary)
                            .background(RoundedRectangle(cornerRadius: 9).fill(icon == i ? Color(hex: color) : Color.primary.opacity(0.06)))
                            .onTapGesture { icon = i }
                    }
                }
            }
            HStack(spacing: 20) {
                Picker("Durum", selection: $status) { ForEach(ProjectStatus.allCases) { Text($0.title).tag($0) } }.fixedSize()
                Toggle("Başlangıç", isOn: $hasStart)
                if hasStart { DatePicker("", selection: $start, displayedComponents: .date).labelsHidden() }
                Toggle("Hedef", isOn: $hasTarget)
                if hasTarget { DatePicker("", selection: $target, displayedComponents: .date).labelsHidden() }
            }
            Spacer()
            HStack {
                Spacer()
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(project == nil ? "Oluştur" : "Kaydet") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560, height: 520)
        .onAppear {
            guard let p = project else { color = Palette.projectColors[projects.count % Palette.projectColors.count]; return }
            name = p.name; summary = p.summary; color = p.colorHex; icon = p.icon; status = p.status
            if let s = p.startDate { hasStart = true; start = s }
            if let t = p.targetDate { hasTarget = true; target = t }
        }
    }

    func save() {
        let p: Project
        if let project { p = project } else {
            p = Project(name: name, colorHex: color, icon: icon)
            p.sortIndex = (projects.map(\.sortIndex).max() ?? 0) + 1
            context.insert(p)
            Store.log(context, "Proje oluşturuldu: **\(name)**", icon: "sparkles", color: color, projectID: p.id)
        }
        p.name = name; p.summary = summary; p.colorHex = color; p.icon = icon; p.status = status
        p.startDate = hasStart ? start.startOfDay : nil
        p.targetDate = hasTarget ? target.startOfDay : nil
        p.updatedAt = Date()
        dismiss()
        if project == nil { app.go(.project(p.id)) }
    }
}
